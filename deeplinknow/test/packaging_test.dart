// Build and packaging checks. They read the plugin's own files, the way the React Native
// package's build-config tests do, so a native pin or a version can't drift silently.
import 'dart:io';

import 'package:deeplinknow/deeplinknow.dart';
import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

// The iOS implementation is the sibling package deeplinknow_ios (FLT-23).
const iosPubspec = '../deeplinknow_ios/pubspec.yaml';
const iosPodspec = '../deeplinknow_ios/ios/deeplinknow_ios.podspec';
const iosPackageSwift = '../deeplinknow_ios/ios/deeplinknow_ios/Package.swift';
const iosPlugin =
    '../deeplinknow_ios/ios/deeplinknow_ios/Sources/deeplinknow_ios/DeepLinkNowPlugin.swift';
const iosPrivacy =
    '../deeplinknow_ios/ios/deeplinknow_ios/Sources/deeplinknow_ios/PrivacyInfo.xcprivacy';

String pubspecVersion() =>
    RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(read('pubspec.yaml'))!.group(1)!;

void main() {
  group('version (SDK-84)', () {
    test('FLT-02 the pub package is deeplinknow 1.4.x, in step with sdkVersion', () {
      final pubspec = read('pubspec.yaml');
      expect(RegExp(r'^name:\s*deeplinknow\s*$', multiLine: true).hasMatch(pubspec), isTrue);
      expect(pubspecVersion(), DeepLinkNow.sdkVersion);
      expect(DeepLinkNow.sdkVersion, startsWith('1.4.'));
    });

    test('FLT-02 deeplinknow_ios has the same version and deeplinknow pins its minor', () {
      final version = pubspecVersion();
      final minor = version.substring(0, version.lastIndexOf('.'));
      final nextMinor = '${minor.split('.')[0]}.${int.parse(minor.split('.')[1]) + 1}.0';
      expect(read(iosPubspec), contains('version: $version'));
      expect(read('pubspec.yaml'), contains("  deeplinknow_ios: '>=$minor.0 <$nextMinor'"));
      expect(read('../deeplinknow_ios/CHANGELOG.md'), contains('## ${pubspecVersion()}'));
    });

    test('FLT-02 the podspec and the Android library carry the same version', () {
      expect(read(iosPodspec), contains("s.version          = '${pubspecVersion()}'"));
      expect(read('android/build.gradle.kts'), contains('version = "${pubspecVersion()}"'));
    });

    test('FLT-02 the CHANGELOG has an entry for the current version', () {
      expect(read('CHANGELOG.md'), contains('## ${pubspecVersion()}'));
    });
  });

  group('native SDK pins', () {
    test('FLT-03 iOS CocoaPods depends on DeepLinkNow ~> 1.4.1', () {
      expect(read(iosPodspec), contains("s.dependency 'DeepLinkNow', '~> 1.4.1'"));
    });

    test('FLT-03 iOS Swift Package Manager depends on dln-ios from 1.4.1 (same minor)', () {
      final manifest = read(iosPackageSwift);
      expect(
        manifest,
        contains(
            '.package(url: "https://github.com/deeplinknow/dln-ios", .upToNextMinor(from: "1.4.1"))'),
      );
      expect(manifest, contains('.product(name: "DeepLinkNow", package: "dln-ios")'));
    });

    test('FLT-03 Android depends on com.deeplinknow:dln-android:1.4.1', () {
      expect(read('android/build.gradle.kts'),
          contains('implementation("com.deeplinknow:dln-android:1.4.1")'));
    });
  });

  group('platforms', () {
    test('FLT-21 minimums: iOS 13 (podspec and SPM), Android API 24', () {
      expect(read(iosPodspec), contains("s.platform         = :ios, '13.0'"));
      expect(read(iosPackageSwift), contains('.iOS("13.0")'));
      expect(read('android/build.gradle.kts'), contains('minSdk = 24'));
    });

    test('FLT-21 the Android build works from Flutter 3.24 (AGP 8) to AGP 9 templates', () {
      final pubspec = read('pubspec.yaml');
      expect(pubspec, contains("flutter: '>=3.24.0'"));
      final gradle = read('android/build.gradle.kts');
      // AGP 8 needs the Kotlin plugin, and older Flutter tooling doesn't apply it for plugins.
      // AGP 9 compiles Kotlin itself and rejects the plugin, so it is applied only below 9.
      expect(gradle, contains('com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION'));
      expect(
          gradle,
          contains(
              'if (agpMajor < 9 && !pluginManager.hasPlugin("org.jetbrains.kotlin.android"))'));
      expect(gradle, contains('apply(plugin = "org.jetbrains.kotlin.android")'));
      // The `kotlin { compilerOptions }` accessor doesn't exist when the plugin isn't in `plugins {}`.
      expect(RegExp(r'^kotlin\s*\{', multiLine: true).hasMatch(gradle), isFalse);
      expect(gradle, contains('tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()'));
    });

    test('FLT-21 FLT-23 Android registers in deeplinknow, iOS in the endorsed deeplinknow_ios', () {
      final pubspec = read('pubspec.yaml');
      expect(pubspec, contains('package: com.deeplinknow.flutter'));
      expect(pubspec, contains('pluginClass: DeepLinkNowPlugin'));
      expect(pubspec, contains('default_package: deeplinknow_ios'));
      final ios = read(iosPubspec);
      expect(ios, contains('implements: deeplinknow'));
      expect(ios, contains('pluginClass: DeepLinkNowPlugin'));
      expect(
        File('android/src/main/kotlin/com/deeplinknow/flutter/DeepLinkNowPlugin.kt').existsSync(),
        isTrue,
      );
      expect(File(iosPlugin).existsSync(), isTrue);
    });
  });

  group('iOS naming', () {
    test('FLT-23 no iOS pod, Swift package or target is named like the DeepLinkNow module', () {
      final names = [
        RegExp(r"s\.name\s*=\s*'([^']+)'").firstMatch(read(iosPodspec))!.group(1)!,
        ...RegExp(r'name: "([^"]+)"').allMatches(read(iosPackageSwift)).map((m) => m.group(1)!),
      ].where((n) => n != 'FlutterFramework' && n != 'DeepLinkNow');
      expect(names, isNotEmpty);
      for (final name in names) {
        expect(name.toLowerCase(), isNot('deeplinknow'), reason: name);
      }
      expect(read(iosPodspec), contains("s.name             = 'deeplinknow_ios'"));
      expect(read(iosPackageSwift),
          contains('.library(name: "deeplinknow-ios", targets: ["deeplinknow_ios"])'));
    });
  });

  group('layering', () {
    test('FLT-01 the Dart layer has no network, clipboard or host-rule code', () {
      // The one exception is SDK-90's resolve request (FLT-30), which lives in its own files.
      const resolveFiles = ['resolve_http.dart', 'resolve_http_io.dart', 'resolve_http_stub.dart'];
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      String code(Iterable<File> fs) => fs
          .expand((f) => f.readAsLinesSync())
          // Code only: doc comments may mention domains and the clipboard.
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      final dart = code(files.where((f) => !resolveFiles.any(f.path.endsWith)));
      expect(dart, isNot(contains("import 'dart:io'")));
      expect(dart, isNot(contains('package:http')));
      expect(dart, isNot(contains('HttpClient')));
      expect(dart, isNot(contains('Clipboard.')));
      expect(dart, isNot(contains('.deeplinknow.com')));
      expect(dart, isNot(contains('Uri.parse')));
      final all = code(files);
      expect(all, isNot(contains('package:http')), reason: 'no HTTP package dependency');
      expect(all, isNot(contains('Clipboard.')));
      expect(all, isNot(contains('.deeplinknow.com')));
    });

    test('FLT-30 dart:io is imported only by the resolve transport, behind a conditional import',
        () {
      final importers = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.readAsStringSync().contains("import 'dart:io'"))
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(importers, ['resolve_http_io.dart']);
      expect(read('lib/src/resolve_http.dart'),
          contains("if (dart.library.io) 'resolve_http_io.dart'"));
    });

    test('FLT-01 iOS and Android use the same single method channel name as Dart', () {
      const name = 'com.deeplinknow/flutter';
      expect(DeepLinkNow.channel.name, name);
      expect(read(iosPlugin), contains('"$name"'));
      expect(read('android/src/main/kotlin/com/deeplinknow/flutter/DeepLinkNowPlugin.kt'),
          contains('"$name"'));
    });

    test('FLT-01 both native plugins handle every method the Dart layer calls', () {
      const methods = [
        'initialize',
        'checkDeferredDeepLink',
        'resetDeferredDeepLink',
        'findDeferredUser',
        'getReferrerData',
        'checkClipboard',
        'hasDeepLinkToken',
        'parseDeepLink',
        'isValidDomain',
        'startLinks',
        'isAppScheme',
        'parseSchemePath',
      ];
      final dart = read('lib/src/deeplinknow.dart');
      final swift = read(iosPlugin);
      final kotlin = read('android/src/main/kotlin/com/deeplinknow/flutter/DeepLinkNowPlugin.kt');
      for (final m in methods) {
        expect(dart, contains("'$m'"), reason: 'Dart calls $m');
        expect(swift, contains('case "$m":'), reason: 'iOS handles $m');
        expect(kotlin, contains('"$m" ->'), reason: 'Android handles $m');
      }
    });

    test('SDK-87 FLT-26 both native plugins push later URLs to Dart as onLinkUrl', () {
      expect(read('lib/src/deeplinknow.dart'), contains("call.method == 'onLinkUrl'"));
      expect(read(iosPlugin), contains('invokeMethod("onLinkUrl"'));
      final kotlin = read('android/src/main/kotlin/com/deeplinknow/flutter/DeepLinkNowPlugin.kt');
      expect(kotlin, contains('"onLinkUrl"'));
      expect(kotlin, contains('ActivityAware'));
      expect(kotlin, contains('PluginRegistry.NewIntentListener'));
    });

    test('SDK-87 FLT-28 iOS observes app-delegate and scene URLs without claiming or swizzling',
        () {
      final swift = read(iosPlugin);
      expect(swift, contains('registrar.addApplicationDelegate(instance)'));
      expect(swift, contains('NSSelectorFromString("addSceneDelegate:")'));
      expect(swift, contains('@objc(scene:openURLContexts:)'));
      expect(swift, contains('@objc(scene:continueUserActivity:)'));
      expect(swift, contains('@objc(scene:willConnectToSession:options:)'));
      expect(swift, isNot(contains('method_exchangeImplementations')));
    });

    test('FLT-08 Android runs SDK calls in a plugin scope on the main thread, cancelled on detach',
        () {
      final kotlin = read('android/src/main/kotlin/com/deeplinknow/flutter/DeepLinkNowPlugin.kt');
      expect(kotlin, contains('CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)'));
      expect(kotlin, contains('scope.cancel()'));
    });

    test('FLT-08 iOS delivers async results on the main actor', () {
      final swift = read(iosPlugin);
      expect(swift, contains('await MainActor.run { result(value) }'));
    });
  });

  group('privacy', () {
    test('FLT-22 the plugin adds no advertising ID or tracking dependency', () {
      final files = [
        read(iosPodspec),
        read(iosPackageSwift),
        read('android/build.gradle.kts'),
        read(iosPlugin),
        read('android/src/main/kotlin/com/deeplinknow/flutter/DeepLinkNowPlugin.kt'),
      ].join('\n');
      expect(files, isNot(contains('AdSupport')));
      expect(files, isNot(contains('AppTrackingTransparency')));
      expect(files, isNot(contains('play-services-ads')));
    });

    test('FLT-22 the iOS privacy manifest is bundled and declares no tracking', () {
      final manifest = read(iosPrivacy);
      expect(manifest, contains('<key>NSPrivacyTracking</key>\n\t<false/>'));
      expect(read(iosPodspec), contains('PrivacyInfo.xcprivacy'));
      expect(read(iosPackageSwift), contains('.process("PrivacyInfo.xcprivacy")'));
    });

    test('FLT-22 the Android manifest asks for no permissions', () {
      expect(read('android/src/main/AndroidManifest.xml'), isNot(contains('uses-permission')));
    });
  });
}
