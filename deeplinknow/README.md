# deeplinknow

The official Flutter plugin for [DeepLinkNow](https://deeplinknow.com): privacy-first deferred deep linking.

A user taps `https://myapp.deeplinknow.com/products/123?ref=newsletter`, installs your app, and opens it. One call gives your app `/products/123` and `{ref: newsletter}`, so you can send them to the right screen.

- **Android**: the Play Install Referrer (exact), then fingerprint matching as a backup.
- **iOS**: the pasteboard handoff from the DeepLinkNow link page (exact), then fingerprint matching as a backup.
- Any path and query on your link domain works. You don't create links in a dashboard first.
- No attribution, no ad tracking, no advertising ID, no ATT prompt.

The plugin is a thin wrapper. All deferred-link logic runs in the native DeepLinkNow SDKs (iOS `DeepLinkNow` 1.3, Android `com.deeplinknow:dln-android` 1.3), so Flutter, React Native, iOS and Android apps get the same answers.

## Requirements

- Flutter 3.24+ (Dart 3.5+)
- iOS 13+ (CocoaPods or Swift Package Manager)
- Android API 24+ (`minSdk 24`)
- A DeepLinkNow app and its public key (`dln_pub_…`) from the dashboard

## Install

```sh
flutter pub add deeplinknow
```

This also installs `deeplinknow_ios`, the plugin's iOS implementation. You don't add it yourself.

**iOS**: nothing else to install. With Swift Package Manager (the default in recent Flutter) Xcode fetches `dln-ios`; with CocoaPods, `pod install` (run by `flutter build` / `flutter run`) fetches the `DeepLinkNow` pod. If you use CocoaPods, set at least `platform :ios, '13.0'` in `ios/Podfile`.

**Android**: the native SDK comes from Maven Central, which new Flutter projects already list in `android/settings.gradle(.kts)`. Make sure `minSdk` is at least 24 in `android/app/build.gradle(.kts)`.

## Set up your link domains

DeepLinkNow serves the `.well-known` files for your domains from your dashboard settings, so links open your app when it's installed.

1. In the dashboard, set your **Team ID** and **Bundle ID** (iOS) and your **package name** and **SHA-256 certificate fingerprints** (Android).
2. **iOS**: open `ios/Runner.xcworkspace` in Xcode, go to **Runner → Signing & Capabilities → + Capability → Associated Domains**, and add `applinks:<alias>.deeplinknow.com` (and `applinks:<your custom domain>` if you have one).
3. **Android**: add an App Links intent filter to the `MainActivity` in `android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https" android:host="<alias>.deeplinknow.com" />
</intent-filter>
```

Replace `<alias>` with your app's alias. Add one `<data>` line per custom domain.

## Quick start

```dart
import 'package:deeplinknow/deeplinknow.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize. Never throws: null means it failed (see DeepLinkNow.lastError).
  await DeepLinkNow.initialize('dln_pub_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx');

  // 2. Get the deferred link. Delivered once per install; null on later launches.
  final link = await DeepLinkNow.checkDeferredDeepLink();

  runApp(MyApp(initialRoute: link?.path ?? '/'));
}
```

`link.path` is the path the user tapped (`/products/123`) and `link.queryParams` holds the query (`{ref: newsletter}`). Route on them the way you route any other link. The example app in `example/` shows the whole first-launch flow with a plain `Navigator`.

With go_router:

```dart
final link = await DeepLinkNow.checkDeferredDeepLink();
if (link != null) router.go(link.fullPath); // path + query, as tapped
```

### How sure is the match?

Every result says where it came from:

| `source` | `confidenceScore` | `matchQuality` | Meaning |
|---|---|---|---|
| `referrer` (Android) | 100 | `HIGH` | Exact: Google Play handed over the click |
| `clipboard` (iOS) | 100 | `HIGH` | Exact: the link page copied the link |
| `fingerprint` | 30–100 | `HIGH` ≥ 75, `MEDIUM` ≥ 50, `LOW` ≥ 30 | Best effort: matched on IP, device, time and locale |

You decide how much to trust a fingerprint match. Filter in the call:

```dart
final link = await DeepLinkNow.checkDeferredDeepLink(minConfidence: 50);
```

or look at `link.source` and `link.matchQuality` yourself. `minConfidence` is off by default.

## Links that open the installed app

When the app is already installed, a tap on your link opens it directly (Universal Link / App Link). Receive the URL with a package such as [`app_links`](https://pub.dev/packages/app_links), then parse it with the same rules as the deferred result:

```dart
final parsed = await DeepLinkNow.parseDeepLink(uri.toString());
if (parsed != null) router.go(parsed.fullPath);
```

`parseDeepLink` returns `null` for any URL that isn't on your link domains.

## API

All members are static on `DeepLinkNow`.

| Member | Returns | Notes |
|---|---|---|
| `initialize(apiKey, {config})` | `Future<DLNAppInfo?>` | One native init. `null` on failure, never throws. `DLNConfig(enableLogs, baseUrl, timeoutMs, retryAttempts)` |
| `isInitialized` | `bool` | Whether the last `initialize` succeeded |
| `appInfo` | `DLNAppInfo?` | App id, alias, link domains, primary domain |
| `checkDeferredDeepLink({minConfidence, useClipboard, force})` | `Future<DeferredDeepLink?>` | **The one call.** `null` = no link or failure; never throws. `useClipboard` (default `true`) is iOS only. `force: true` ignores the first-launch flag |
| `resetDeferredDeepLink()` | `Future<void>` | Clears the first-launch state, for testing. Throws `DLNError` if the native reset fails |
| `findDeferredUser()` | `Future<MatchResponse?>` | Low level: every fingerprint candidate, in server order. `null` on failure |
| `getReferrerData()` | `Future<ReferrerData?>` | Android only: the raw Install Referrer result. `null` on iOS |
| `checkClipboard()` | `Future<String?>` | Low level: the clipboard text if it is one of your links. May show the iOS paste prompt |
| `hasDeepLinkToken()` | `Future<bool>` | Low level: cheap check without a paste prompt |
| `parseDeepLink(url)` | `Future<ParsedDeepLink?>` | `{path, queryParams, fullPath, url}`, or `null` if not your link |
| `isValidDomain(host)` | `Future<bool>` | Whether the host is one of your link domains |
| `lastError` | `DLNError?` | Last failure of `initialize`, `checkDeferredDeepLink` or `findDeferredUser`; cleared by the next success of the same call |
| `sdkVersion` | `String` | `1.3.0` |

`parseDeepLink` and `isValidDomain` are synchronous in the native SDKs but return a `Future` here, because Flutter platform channels are asynchronous.

### Query parameters

`queryParams` is a `Map<String, QueryValue>`. A `QueryValue` is one of:

- `SingleQueryValue` for `?ref=newsletter`
- `FlagQueryValue` for `?debug` or `?debug=`
- `MultipleQueryValue` for a repeated key, `?tag=a&tag=b`

Use `.stringValue` for the common case (`link.queryParams['ref']?.stringValue`), `.stringValues` for lists, or switch on the type.

### Errors

Failures never throw from the everyday calls. They return `null` (or `false`), log one `[DeepLinkNow]` warning, and are kept in `DeepLinkNow.lastError`, a `DLNError` with:

- `code`: `notInitialized`, `invalidApiKey`, `accountInactive`, `noCredits`, `rateLimited`, `badRequest`, `server`, `network` or `invalidResponse` (the same codes as every DeepLinkNow SDK)
- `status` (HTTP), `serverMessage`, `message`, `cause`

```dart
final link = await DeepLinkNow.checkDeferredDeepLink();
if (link == null && DeepLinkNow.lastError != null) {
  // Offline or misconfigured. The next call tries again: errors don't use up the first launch.
}
```

## FlutterFlow

1. In **Custom Code → Dependencies** (or the action's **Pubspec Dependencies** field), add `deeplinknow: ^1.3.0`.
2. Create a custom action `getDeferredDeepLink` with one `String` argument `apiKey`, return type `String` (nullable):

```dart
// Automatic FlutterFlow imports
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/custom_code/actions/index.dart';
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:deeplinknow/deeplinknow.dart';

/// Returns the path and query the user tapped before installing (e.g.
/// "/products/123?ref=newsletter"), or null. Never throws.
Future<String?> getDeferredDeepLink(String apiKey) async {
  if (!DeepLinkNow.isInitialized) {
    await DeepLinkNow.initialize(apiKey);
  }
  final link = await DeepLinkNow.checkDeferredDeepLink();
  return link?.fullPath;
}
```

3. Run it from the **On Page Load** actions of your initial page, save the result to a page or app state variable, and navigate when it isn't empty.

Test on a real device or emulator build. The plugin has no web implementation, so FlutterFlow's web-based Test and Run modes return `null` (with `lastError` set to `notInitialized`). Universal Links and App Links also need the iOS Associated Domains entitlement and the Android intent filter above in the native project.

## Testing your integration

- First launch only: a link is delivered once per install. To try again without reinstalling, call `DeepLinkNow.resetDeferredDeepLink()` or pass `force: true`.
- iOS: open your link in Safari on the device, tap the App Store button (this copies the link), then run the app from Xcode.
- Android: test the Install Referrer with an internal test track install from a link; a sideloaded build has no referrer and falls back to fingerprint matching.
- `DLNConfig(enableLogs: true)` turns on native debug logs (`[DeepLinkNow]` in the Xcode console, tag `DLN` in Logcat). The API key is never logged.
- `MissingPluginException` / `lastError` "native plugin is not available": stop the app and rebuild it after adding the package. Hot restart doesn't load native code.

## Privacy

The plugin adds nothing to what the native SDKs collect: the device fields used for matching (platform, OS version, device model, screen size, language, time zone, the app-scoped install ID), sent only to DeepLinkNow, and no advertising identifiers. See the [iOS](https://deeplinknow.com/docs/ios) and [Android](https://deeplinknow.com/docs/android) docs for App Store privacy labels and the Play Data safety form. The iOS SDK ships a privacy manifest.

## License

MIT. See [LICENSE](LICENSE).
