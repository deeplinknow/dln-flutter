import DeepLinkNow
import Flutter
import UIKit
import XCTest

@testable import deeplinknow_ios

/// Tests of the iOS method-channel glue (deeplinknow_ios) against the real DeepLinkNow SDK.
/// No network: every call here fails or answers locally.
class RunnerTests: XCTestCase {
  private let plugin = DeepLinkNowPlugin()

  override func setUp() {
    super.setUp()
    DeepLinkNow.resetDeferredDeepLink()
  }

  private func call(_ method: String, _ args: [String: Any]? = nil) -> Any? {
    let done = expectation(description: method)
    var value: Any?
    plugin.handle(FlutterMethodCall(methodName: method, arguments: args)) { result in
      value = result
      done.fulfill()
    }
    wait(for: [done], timeout: 5)
    return value
  }

  func test_FLT_15_parseDeepLink_returnsTheCamelCaseShape() {
    let parsed = call("parseDeepLink", ["url": "https://myapp.deeplinknow.com/products/123?ref=news&debug&tag=a&tag=b"])
      as? [String: Any]
    XCTAssertEqual(parsed?["path"] as? String, "/products/123")
    XCTAssertEqual(parsed?["fullPath"] as? String, "/products/123?ref=news&debug&tag=a&tag=b")
    let query = parsed?["queryParams"] as? [String: Any]
    XCTAssertEqual(query?["ref"] as? String, "news")
    XCTAssertEqual(query?["debug"] as? Bool, true)
    XCTAssertEqual(query?["tag"] as? [String], ["a", "b"])
  }

  func test_FLT_15_parseDeepLink_rejectsOtherHosts() {
    XCTAssertNil(call("parseDeepLink", ["url": "https://evil.com/?u=x.deeplinknow.com"]))
    XCTAssertNil(call("parseDeepLink", ["url": "https://myapp.deeplink.now/a"]))
    XCTAssertNil(call("parseDeepLink", [:]))
  }

  func test_FLT_16_isValidDomain_usesTheNativeRule() {
    XCTAssertEqual(call("isValidDomain", ["host": "myapp.deeplinknow.com"]) as? Bool, true)
    XCTAssertEqual(call("isValidDomain", ["host": "deeplinknow.com.evil.com"]) as? Bool, false)
    XCTAssertEqual(call("isValidDomain", [:]) as? Bool, false)
  }

  func test_FLT_13_getReferrerData_isNilOnIOS() {
    XCTAssertNil(call("getReferrerData"))
  }

  func test_FLT_11_resetDeferredDeepLink_returnsTrue() {
    XCTAssertEqual(call("resetDeferredDeepLink") as? Bool, true)
  }

  func test_FLT_07_initialize_invalidConfigurationIsReportedAsBadRequest() {
    let error = call("initialize", ["apiKey": "dln_pub_test", "config": ["baseUrl": "http://evil.com"]]) as? FlutterError
    XCTAssertEqual(error?.code, "badRequest")
  }

  func test_FLT_07_errors_carryTheSharedCodeAndDetails() {
    let cause = DeepLinkNowError(.network, message: "offline")
    let error = DeepLinkNowPlugin.flutterError(
      DeepLinkNowError(.invalidApiKey, statusCode: 401, message: "Invalid API key", underlying: cause))
    XCTAssertEqual(error.code, "invalidApiKey")
    XCTAssertEqual(error.message, "Invalid API key")
    let details = error.details as? [String: Any]
    XCTAssertEqual(details?["status"] as? Int, 401)
    XCTAssertEqual(details?["serverMessage"] as? String, "Invalid API key")
    XCTAssertEqual(details?["causeCode"] as? String, "network")
    XCTAssertEqual(DeepLinkNowPlugin.flutterError(NSError(domain: "x", code: 1)).code, "invalidResponse")
    XCTAssertEqual(DeepLinkNowPlugin.flutterError(CancellationError()).code, "network")
  }

  func test_FLT_04_initialize_passesTheConfigToTheSDK() {
    let config = DeepLinkNowPlugin.dlnConfig(
      apiKey: "dln_pub_test",
      ["enableLogs": true, "baseUrl": "https://staging.example.com", "timeoutMs": 2500, "retryAttempts": 1])
    XCTAssertEqual(config.apiKey, "dln_pub_test")
    XCTAssertTrue(config.enableLogs)
    XCTAssertEqual(config.timeout, 2.5)
    XCTAssertEqual(config.retryAttempts, 1)
  }

  func test_FLT_01_unknownMethodsAreNotImplemented() {
    XCTAssertTrue((call("getPlatformVersion") as AnyObject) === FlutterMethodNotImplemented)
  }

  // MARK: - Incoming URLs (SDK-87, FLT-26…28)

  func test_SDK_87_FLT_26_launchURLsAreBufferedUntilStartLinks() {
    let link = URL(string: "https://myapp.deeplinknow.com/launch?x=1")!
    XCTAssertFalse(plugin.application(UIApplication.shared, open: link, options: [:]),
                   "observes only: never claims the URL")
    XCTAssertEqual(call("startLinks") as? [String], ["https://myapp.deeplinknow.com/launch?x=1"])
    XCTAssertEqual(call("startLinks") as? [String], [], "taken once")
  }

  func test_SDK_87_FLT_26_universalLinksArriveThroughTheUserActivity() {
    let web = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
    web.webpageURL = URL(string: "https://myapp.deeplinknow.com/ul")
    let other = NSUserActivity(activityType: "com.example.handoff")
    other.webpageURL = URL(string: "https://myapp.deeplinknow.com/not-a-link")
    XCTAssertFalse(plugin.application(UIApplication.shared, continue: web, restorationHandler: { _ in }))
    _ = plugin.application(UIApplication.shared, continue: other, restorationHandler: { _ in })
    XCTAssertEqual(plugin.startLinks(), ["https://myapp.deeplinknow.com/ul"])
  }

  func test_SDK_87_FLT_26_afterStartLinksURLsArePushed_andAFailedPushIsBufferedAgain() {
    var pushed: [String] = []
    var answer = true
    plugin.pushOverride = { url, delivered in
      pushed.append(url)
      delivered(answer)
    }
    XCTAssertEqual(plugin.startLinks(), [])
    _ = plugin.application(UIApplication.shared, open: URL(string: "https://a.deeplinknow.com/1")!, options: [:])
    XCTAssertEqual(pushed, ["https://a.deeplinknow.com/1"])
    answer = false // no Dart handler (hot restart)
    _ = plugin.application(UIApplication.shared, open: URL(string: "https://a.deeplinknow.com/2")!, options: [:])
    _ = plugin.application(UIApplication.shared, open: URL(string: "https://a.deeplinknow.com/3")!, options: [:])
    XCTAssertEqual(pushed, ["https://a.deeplinknow.com/1", "https://a.deeplinknow.com/2"])
    XCTAssertEqual(plugin.startLinks(), ["https://a.deeplinknow.com/2", "https://a.deeplinknow.com/3"])
  }

  func test_FLT_28_answersTheFlutterSceneLifeCycleSelectors() {
    for name in ["scene:willConnectToSession:options:", "scene:openURLContexts:", "scene:continueUserActivity:"] {
      XCTAssertTrue(plugin.responds(to: NSSelectorFromString(name)), name)
    }
  }

  func test_FLT_28_adoptsTheSceneProtocolWhenTheEngineHasIt() throws {
    let proto = try XCTUnwrap(NSProtocolFromString("FlutterSceneLifeCycleDelegate"),
                              "this example builds with Flutter 3.38+")
    final class Registrar: NSObject {
      var sceneDelegates: [AnyObject] = []
      @objc(addSceneDelegate:) func addSceneDelegate(_ delegate: AnyObject) { sceneDelegates.append(delegate) }
    }
    let registrar = Registrar()
    DeepLinkNowPlugin.registerForSceneEvents(plugin, registrar: registrar)
    XCTAssertTrue(plugin.conforms(to: proto))
    XCTAssertTrue(registrar.sceneDelegates.first === plugin)
  }

  func test_SDK_87_FLT_26_declaredSchemesComeFromCFBundleURLTypes() {
    let info: [String: Any] = ["CFBundleURLTypes": [
      ["CFBundleURLSchemes": ["MyApp", "myapp-dev"]],
      ["CFBundleURLName": "no schemes"],
    ]]
    XCTAssertEqual(DeepLinkNowPlugin.declaredSchemes(info), ["myapp", "myapp-dev"])
    XCTAssertEqual(DeepLinkNowPlugin.declaredSchemes([:]), [])
    XCTAssertEqual(call("isAppScheme", [:]) as? Bool, false)
  }
}
