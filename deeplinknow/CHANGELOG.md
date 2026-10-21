# Changelog

## 1.3.0

First release of the official Flutter plugin. The version matches the native SDKs it wraps (SDK-84): iOS, Android, React Native and Flutter all ship as 1.3.0.

- Wraps the native SDKs over one method channel: iOS `DeepLinkNow` `~> 1.3.0` (CocoaPods, or Swift Package Manager from `1.3.0`) and Android `com.deeplinknow:dln-android:1.3.0`. All deferred-link logic runs natively.
- Builds on Flutter 3.24 and later: the Android library applies the Kotlin Android plugin itself on AGP 8 (Flutter 3.24-era apps), and leaves Kotlin to AGP 9 on newer templates.
- `DeepLinkNow.initialize(apiKey, config:)` resolves `DLNAppInfo` or `null`, and never throws.
- `DeepLinkNow.checkDeferredDeepLink(minConfidence:, useClipboard:, force:)`: Install Referrer then fingerprint on Android, pasteboard then fingerprint on iOS. Resolves `DeferredDeepLink` or `null`, and never throws.
- `findDeferredUser`, `resetDeferredDeepLink`, `getReferrerData` (Android), `checkClipboard`, `hasDeepLinkToken`, `parseDeepLink`, `isValidDomain`, `isInitialized`, `appInfo`, `lastError`.
- Typed results (`DeferredDeepLink`, `ParsedDeepLink`, `MatchResponse`, `ReferrerData`, `QueryValue`, …) and `DLNError` with the error codes shared by every DeepLinkNow SDK.
