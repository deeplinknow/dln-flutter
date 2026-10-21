import DeepLinkNow
import Flutter
import Foundation

/// Flutter plugin for DeepLinkNow on iOS. Marshals the `com.deeplinknow/flutter` method channel to
/// the native `DeepLinkNow` SDK and back (FLT-01). All deferred-link behavior (pasteboard,
/// fingerprint matching, first-launch state, link parsing, the domain rule, error mapping) lives
/// in the native SDK; this file only converts arguments and results.
///
/// Shapes mirror the React Native glue (`DeepLinkNowCore.swift`) (FLT-05):
/// - `checkDeferredDeepLink` / `parseDeepLink` → camelCase.
/// - `findDeferredUser` → the server's snake_case wire shape.
/// - errors → `FlutterError(code, message, details{status, serverMessage, causeCode, causeMessage})`.
public final class DeepLinkNowPlugin: NSObject, FlutterPlugin {
    static let channelName = "com.deeplinknow/flutter"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(DeepLinkNowPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
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
