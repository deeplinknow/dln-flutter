# Changelog

## 1.4.2 (2026-11-24)

Pins `com.deeplinknow:dln-android:1.4.2` and `deeplinknow_ios` 1.4.2, which pins iOS `DeepLinkNow` `~> 1.4.2` (SDK-84, FLT-03). No Dart changes.

- **App Review Guideline 2.5.2.** iOS 1.4.2 removes the `itms-services` string from the binary; App Review rejected an app for it (IOS-42).
- The native match request sends only what scoring uses: no `advertising_id` key, no device hash, no CPU core count (SDK-21, SDK-60). Match scores don't change.

## 1.4.1 (2026-10-25)

Fixes. Pins `com.deeplinknow:dln-android:1.4.1`; `deeplinknow_ios` 1.4.1 pins iOS `DeepLinkNow` `~> 1.4.1` (SDK-84).

- Android: an activity re-created after process death (back through Recents, "Don't keep activities", low memory) no longer delivers its launch link again. The plugin saves a mark in the activity's state and skips the launch intent of a restored activity (FLT-32).
- Android: a custom scheme is checked against the manifest with the real URL, so intent filters that also set `android:host` or a path (FlutterFlow's, for one) count. Before, those links were dropped (FLT-33).
- Custom-scheme links are delivered without a successful `initialize`: they need no network (FLT-34).
- A failed deferred check in `listen()` (offline, or `initialize` failed) runs again on the next `listen()` call or successful `initialize`, instead of never in that launch (SDK-24, FLT-35).

## 1.4.0 (2026-10-25)

Published 2026-10-25 with the native 1.4.0 releases (SDK-84).

- `DeepLinkNow.links`, a broadcast `Stream<DLNLink>` with every open, deferred or direct, started by `DeepLinkNow.listen([DLNLinkOptions])`. The plugin reads the launch URL and later URLs itself: on Android with `ActivityAware` and `onNewIntent`, on iOS with the app-delegate callbacks and, on Flutter 3.38+, the UIScene callbacks. No extra package.
- Direct opens: https links on your link domains, and your custom schemes (`options.schemes`, or the ones Info.plist or the manifest declares). The same URL twice within 3 seconds is one open. On a first launch with both, the deferred link comes first.
- `hold`: `pendingLink`, `pendingLinks`, `releasePendingLink()`, `clearPendingLink()`.
- `resolve` and `resolveLink(url)`: look up a direct open with `GET /api/v1/sdk/resolve` (links imported from Firebase), with the configured timeout. On a 404 or a failure the link is delivered unresolved.
- A `#dln=` fragment parameter is removed from `url` and `fullPath` in every result.
- New types: `DLNLink`, `DLNLinkOptions`, `DLNLinkType`, `DLNLinkSource`.
- Every 1.3.0 call is unchanged.
- With the iOS SDK 1.4.0 pin, a clipboard link carrying `#dln=` is claimed on the server before it's delivered (SDK-93; native, no plugin code).

## 1.3.0

First release of the official Flutter plugin. The version matches the native SDKs it wraps (SDK-84): iOS, Android, React Native and Flutter all ship as 1.3.0.

- Wraps the native SDKs over one method channel: iOS `DeepLinkNow` `~> 1.3.0` (CocoaPods, or Swift Package Manager from `1.3.0`) and Android `com.deeplinknow:dln-android:1.3.0`. All deferred-link logic runs natively.
- Builds on Flutter 3.24 and later: the Android library applies the Kotlin Android plugin itself on AGP 8 (Flutter 3.24-era apps), and leaves Kotlin to AGP 9 on newer templates.
- `DeepLinkNow.initialize(apiKey, config:)` resolves `DLNAppInfo` or `null`, and never throws.
- `DeepLinkNow.checkDeferredDeepLink(minConfidence:, useClipboard:, force:)`: Install Referrer then fingerprint on Android, pasteboard then fingerprint on iOS. Resolves `DeferredDeepLink` or `null`, and never throws.
- `findDeferredUser`, `resetDeferredDeepLink`, `getReferrerData` (Android), `checkClipboard`, `hasDeepLinkToken`, `parseDeepLink`, `isValidDomain`, `isInitialized`, `appInfo`, `lastError`.
- Typed results (`DeferredDeepLink`, `ParsedDeepLink`, `MatchResponse`, `ReferrerData`, `QueryValue`, …) and `DLNError` with the error codes shared by every DeepLinkNow SDK.
