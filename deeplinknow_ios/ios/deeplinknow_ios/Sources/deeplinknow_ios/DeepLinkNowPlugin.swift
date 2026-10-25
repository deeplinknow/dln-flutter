import DeepLinkNow
import Flutter
import Foundation
import ObjectiveC
import UIKit

/// Flutter plugin for DeepLinkNow on iOS. Marshals the `com.deeplinknow/flutter` method channel to
/// the native `DeepLinkNow` SDK and back (FLT-01). All deferred-link behavior (pasteboard,
/// fingerprint matching, first-launch state, link parsing, the domain rule, error mapping) lives
/// in the native SDK; this file only converts arguments and results.
///
/// Shapes mirror the React Native glue (`DeepLinkNowCore.swift`) (FLT-05):
/// - `checkDeferredDeepLink` / `parseDeepLink` → camelCase.
/// - `findDeferredUser` → the server's snake_case wire shape.
/// - errors → `FlutterError(code, message, details{status, serverMessage, causeCode, causeMessage})`.
///
/// Since 1.4.0 it also observes the URLs iOS opens the app with (Universal Links through
/// `NSUserActivity`, and `openURL`) and hands them to Dart (`startLinks`, then `onLinkUrl`) for
/// `DeepLinkNow.links` (SDK-87, FLT-26). Both lifecycles are covered: the app-delegate callbacks
/// (`addApplicationDelegate`) and, on Flutter 3.38+, the UIScene callbacks (`addSceneDelegate`,
/// FLT-28). Every callback returns `false`, so other plugins and Flutter's own deep linking still
/// see the URL. No swizzling.
public final class DeepLinkNowPlugin: NSObject, FlutterPlugin {
    static let channelName = "com.deeplinknow/flutter"

    /// The channel, for pushing URLs to Dart. `nil` in unit tests.
    var channel: FlutterMethodChannel?
    /// URLs waiting for Dart's `startLinks` (the launch URL first).
    private(set) var pendingURLs: [String] = []
    private var dartListening = false
    /// Replaces the channel push in unit tests: `(url, delivered)`.
    var pushOverride: ((String, @escaping (Bool) -> Void) -> Void)?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = DeepLinkNowPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)
        registerForSceneEvents(instance, registrar: registrar)
    }

    /// FLT-28: `FlutterSceneLifeCycleDelegate` and `addSceneDelegate:` exist from Flutter 3.38, but
    /// the plugin supports Flutter 3.24 (FLT-21), so they are looked up at run time. On 3.38+ the
    /// class adopts the protocol (the engine checks `conformsToProtocol:`, then
    /// `respondsToSelector:` for the optional methods below) and registers for scene events; on
    /// older Flutter nothing happens and the app-delegate callbacks are used.
    static func registerForSceneEvents(_ instance: DeepLinkNowPlugin, registrar: AnyObject) {
        guard let proto = NSProtocolFromString("FlutterSceneLifeCycleDelegate") else { return }
        class_addProtocol(DeepLinkNowPlugin.self, proto)
        let selector = NSSelectorFromString("addSceneDelegate:")
        let target = registrar
        if target.responds(to: selector) {
            _ = target.perform(selector, with: instance)
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "startLinks":
            result(startLinks())
        case "isAppScheme":
            let scheme = (args["scheme"] as? String)?.lowercased()
            result(scheme.map { Self.declaredSchemes().contains($0) } ?? false)
        case "initialize":
            let apiKey = args["apiKey"] as? String ?? ""
            let config = args["config"] as? [String: Any] ?? [:]
            Self.run(result) {
                let info = try await DeepLinkNow.initializeThrowing(config: Self.dlnConfig(apiKey: apiKey, config))
                return Self.appInfoDict(info)
            }
        case "checkDeferredDeepLink":
            let options = DLNDeferredOptions(
                minConfidence: (args["minConfidence"] as? NSNumber)?.doubleValue,
                useClipboard: (args["useClipboard"] as? Bool) ?? true,
                force: (args["force"] as? Bool) ?? false
            )
            Self.run(result) {
                guard let link = try await DeepLinkNow.checkDeferredDeepLinkThrowing(options) else { return nil }
                return Self.deferredDict(link)
            }
        case "resetDeferredDeepLink":
            DeepLinkNow.resetDeferredDeepLink()
            result(true)
        case "findDeferredUser":
            Self.run(result) {
                Self.matchResponseDict(try await DeepLinkNow.findDeferredUserThrowing())
            }
        case "getReferrerData":
            // Android only (Install Referrer).
            result(nil)
        case "checkClipboard":
            // UIPasteboard reads happen on the main thread (SDK-56); handle(_:result:) runs there.
            result(DeepLinkNow.checkClipboard())
        case "hasDeepLinkToken":
            Self.run(result) { await DeepLinkNow.hasDeepLinkTokenAsync() }
        case "parseDeepLink":
            result((args["url"] as? String).flatMap(Self.parseDeepLink))
        case "isValidDomain":
            result((args["host"] as? String).map { DeepLinkNow.isValidDomain($0) } ?? false)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Incoming URLs (SDK-87)

    /// The custom schemes the app declares (`CFBundleURLTypes` → `CFBundleURLSchemes`), lowercased.
    static func declaredSchemes(_ info: [String: Any]? = Bundle.main.infoDictionary) -> Set<String> {
        let types = info?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        return Set(types.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }.map { $0.lowercased() })
    }

    /// A URL iOS opened the app with. Buffered until Dart calls `startLinks`, pushed after. Only
    /// http(s) and the app's schemes reach here; Dart applies the native parse rules (FLT-01).
    func offer(_ url: URL?) {
        guard let url else { return }
        let string = url.absoluteString
        guard !string.isEmpty else { return }
        guard dartListening else {
            pendingURLs.append(string)
            return
        }
        push(string) { [weak self] delivered in
            guard let self, !delivered else { return }
            // No Dart handler (a hot restart): keep it for the next `startLinks`.
            self.pendingURLs.append(string)
            self.dartListening = false
        }
    }

    /// Dart's `startLinks`: the buffered URLs, and pushing from now on.
    func startLinks() -> [String] {
        dartListening = true
        let urls = pendingURLs
        pendingURLs.removeAll()
        return urls
    }

    private func push(_ url: String, _ delivered: @escaping (Bool) -> Void) {
        if let pushOverride {
            pushOverride(url, delivered)
            return
        }
        guard let channel else {
            delivered(false)
            return
        }
        channel.invokeMethod("onLinkUrl", arguments: url) { reply in
            if reply is FlutterError {
                delivered(false)
            } else if let object = reply as? NSObject, object === FlutterMethodNotImplemented {
                delivered(false)
            } else {
                delivered(true)
            }
        }
    }

    private func offer(_ activity: NSUserActivity) {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb else { return }
        offer(activity.webpageURL)
    }

    // App-delegate lifecycle (apps without UIScene). Cold-start links arrive through these too:
    // iOS calls them after `didFinishLaunching`.

    public func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        offer(url)
        return false
    }

    public func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([Any]) -> Void
    ) -> Bool {
        offer(userActivity)
        return false
    }

    // UIScene lifecycle (Flutter 3.38+, FLT-28). Objective-C selectors of
    // `FlutterSceneLifeCycleDelegate`; the Swift names differ so they never clash with UIKit's.

    @objc(scene:willConnectToSession:options:)
    func dlnScene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions?) -> Bool {
        guard let options else { return false }
        options.urlContexts.forEach { offer($0.url) }
        options.userActivities.forEach { offer($0) }
        return false
    }

    @objc(scene:openURLContexts:)
    func dlnScene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) -> Bool {
        contexts.forEach { offer($0.url) }
        return false
    }

    @objc(scene:continueUserActivity:)
    func dlnScene(_ scene: UIScene, continue userActivity: NSUserActivity) -> Bool {
        offer(userActivity)
        return false
    }

    // MARK: - Async plumbing

    /// Runs `body`, then delivers its value or a mapped error on the main thread.
    private static func run(_ result: @escaping FlutterResult, _ body: @escaping () async throws -> Any?) {
        Task {
            let value: Any?
            do {
                value = try await body()
            } catch {
                value = flutterError(error)
            }
            await MainActor.run { result(value) }
        }
    }

    // MARK: - Arguments

    static func dlnConfig(apiKey: String, _ config: [String: Any]) -> DLNConfig {
        let timeoutMs = (config["timeoutMs"] as? NSNumber)?.doubleValue
        return DLNConfig(
            apiKey: apiKey,
            enableLogs: (config["enableLogs"] as? Bool) ?? false,
            baseUrl: config["baseUrl"] as? String,
            timeout: timeoutMs.map { $0 / 1000 },
            retryAttempts: (config["retryAttempts"] as? NSNumber)?.intValue
        )
    }

    // MARK: - Errors

    /// The shared codes (SDK-55). `invalidConfiguration` is iOS-only and maps to `badRequest`.
    static func code(_ code: DeepLinkNowError.Code) -> String {
        code == .invalidConfiguration ? "badRequest" : code.rawValue
    }

    static func flutterError(_ error: Error) -> FlutterError {
        guard let dln = error as? DeepLinkNowError else {
            if error is CancellationError {
                return FlutterError(code: "network", message: "Cancelled", details: [String: Any]())
            }
            return FlutterError(code: "invalidResponse", message: String(describing: error), details: [String: Any]())
        }
        var details: [String: Any] = [:]
        if let status = dln.statusCode { details["status"] = status }
        if let message = dln.message { details["serverMessage"] = message }
        if let cause = dln.cause {
            details["causeCode"] = code(cause.code)
            details["causeMessage"] = cause.message ?? cause.code.rawValue
        }
        return FlutterError(code: code(dln.code), message: dln.message ?? dln.code.rawValue, details: details)
    }

    // MARK: - Converters

    static func parseDeepLink(_ urlString: String) -> [String: Any]? {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let parsed = DeepLinkNow.parseLink(url) else {
            return nil
        }
        return [
            "path": parsed.path,
            "queryParams": queryDict(parsed.queryParams),
            "fullPath": parsed.fullPath,
            "url": parsed.url,
        ]
    }

    static func plain(_ value: Any?) -> Any {
        switch value {
        case nil:
            return NSNull()
        case let v as AnyCodable:
            return plain(v.value)
        case let dict as [String: AnyCodable]:
            return dict.mapValues { plain($0.value) }
        case let dict as [String: Any]:
            return dict.mapValues { plain($0) }
        case let list as [AnyCodable]:
            return list.map { plain($0.value) }
        case let list as [Any]:
            return list.map { plain($0) }
        case let v?:
            return v
        }
    }

    static func queryDict(_ params: [String: DLNQueryValue]) -> [String: Any] {
        params.mapValues { $0.anyValue }
    }

    static func appInfoDict(_ info: DLNAppInfo) -> [String: Any] {
        [
            "id": info.appId,
            "alias": info.alias,
            "name": info.name ?? NSNull(),
            "domains": info.linkDomains,
            "primaryDomain": info.primaryDomain,
            "accountStatus": info.accountStatus,
            "creditsRemaining": info.creditsRemaining ?? NSNull(),
        ]
    }

    /// `match_details` in the server's snake_case shape.
    static func matchDetailsDict(_ d: MatchDetails) -> [String: Any] {
        [
            "ip_match": [
                "matched": d.ipMatch.matched,
                "score": d.ipMatch.score,
            ],
            "device_match": [
                "matched": d.deviceMatch.matched,
                "score": d.deviceMatch.score,
                "components": [
                    "platform": d.deviceMatch.components.platform,
                    "os_version": d.deviceMatch.components.osVersion,
                    "device_model": d.deviceMatch.components.deviceModel,
                    "hardware_fingerprint": d.deviceMatch.components.hardwareFingerprint,
                ],
            ],
            "time_proximity": [
                "score": d.timeProximity.score,
                "time_difference_minutes": d.timeProximity.timeDifferenceMinutes,
            ],
            "locale_match": [
                "matched": d.localeMatch.matched,
                "score": d.localeMatch.score,
                "components": [
                    "language": d.localeMatch.components.language,
                    "timezone": d.localeMatch.components.timezone,
                ],
            ],
        ]
    }

    /// `/sdk/match` response in the server's snake_case wire shape.
    static func matchResponseDict(_ response: MatchResponse) -> [String: Any] {
        let matches: [[String: Any]] = response.matches.map { match in
            var m: [String: Any] = [
                "confidence_score": match.confidenceScore,
                "match_quality": match.matchQuality.rawValue,
                "match_details": matchDetailsDict(match.matchDetails),
            ]
            if let dl = match.deeplink {
                var d: [String: Any] = [
                    "id": dl.id,
                    "target_url": dl.targetUrl,
                    "metadata": plain(dl.metadata),
                    "campaign_id": dl.campaignId ?? NSNull(),
                    "matched_at": dl.matchedAt,
                    "expires_at": dl.expiresAt,
                ]
                if let q = dl.queryParams { d["query_params"] = queryDict(q) }
                if let fp = dl.fullPath { d["full_path"] = fp }
                m["deeplink"] = d
            }
            return m
        }
        return ["matches": matches, "ttl_seconds": response.ttlSeconds]
    }

    /// camelCase `DeferredDeepLink` (SDK-15).
    static func deferredDict(_ link: DLNDeferredDeepLink) -> [String: Any] {
        var d: [String: Any] = [
            "path": link.path,
            "queryParams": queryDict(link.queryParams),
            "fullPath": link.fullPath,
            "url": link.url,
            "source": link.source.rawValue,
            "confidenceScore": link.confidenceScore,
            "matchQuality": link.matchQuality.rawValue,
        ]
        if let v = link.deeplinkId { d["deeplinkId"] = v }
        if let v = link.targetUrl { d["targetUrl"] = v }
        if let v = link.campaignId { d["campaignId"] = v }
        if let v = link.metadata { d["metadata"] = plain(v) }
        if let v = link.matchedAt { d["matchedAt"] = v }
        if let v = link.expiresAt { d["expiresAt"] = v }
        if let v = link.matchDetails { d["matchDetails"] = matchDetailsDict(v) }
        return d
    }
}
