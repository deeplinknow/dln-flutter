# deeplinknow_ios

The iOS implementation of [`deeplinknow`](https://pub.dev/packages/deeplinknow), the DeepLinkNow Flutter plugin.

You don't add this package yourself. Add `deeplinknow` to your app; it is endorsed as the default iOS implementation and installed with it. See the `deeplinknow` README for setup.

It is a separate package because a CocoaPods pod or Swift package named `deeplinknow` collides with the native `DeepLinkNow` SDK module on case-insensitive file systems (the macOS default).
