# dln-flutter

The official DeepLinkNow Flutter plugin. Two pub packages, released together with one version:

- [`deeplinknow`](deeplinknow/): the package apps add. Dart API, Android implementation, example app. Start with its [README](deeplinknow/README.md).
- [`deeplinknow_ios`](deeplinknow_ios/): the iOS implementation, endorsed by `deeplinknow` and installed with it.

Spec: `docs/sdks/flutter.md` (requirements `FLT-*`) in the DeepLinkNow monorepo.

## Development

```sh
cd deeplinknow
flutter pub get
flutter analyze
flutter test
cd example
flutter test
flutter build apk --debug
flutter build ios --no-codesign --debug
(cd android && ./gradlew :deeplinknow:testDebugUnitTest)      # Android glue tests
(cd ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro')   # iOS glue tests
```

`pubspec_overrides.yaml` points `deeplinknow` (and the example) at the local `deeplinknow_ios`. It is not published.

## Publishing

Publish order: the native SDKs 1.4.0 first (iOS `DeepLinkNow` on CocoaPods and the `dln-ios` 1.4.0 tag, Android `com.deeplinknow:dln-android:1.4.0` on Maven Central), then `deeplinknow_ios`, then `deeplinknow` (it depends on `deeplinknow_ios` `>=1.4.0 <1.5.0`):

```sh
cd deeplinknow_ios && flutter pub publish
cd ../deeplinknow && flutter pub publish
```
