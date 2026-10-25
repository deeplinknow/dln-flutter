# Changelog

## Unreleased (1.4.0)

Not published; the version is bumped with the native 1.4.0 releases.

- Observes the URLs iOS opens the app with, without claiming them: `application(_:open:options:)` and `application(_:continue:restorationHandler:)`, plus, on Flutter 3.38+, the UIScene callbacks (`addSceneDelegate`, found at run time so Flutter 3.24 still works). It hands them to `deeplinknow`'s `DeepLinkNow.links` (`startLinks` / `onLinkUrl`).
- `isAppScheme`: whether a scheme is in the app's `CFBundleURLSchemes`.

## 1.3.0

First release. iOS implementation of `deeplinknow` 1.3.0, endorsed as its default iOS package. Wraps the native `DeepLinkNow` SDK `~> 1.3.0` (CocoaPods) or `dln-ios` from `1.3.0` up to the next minor (Swift Package Manager).
