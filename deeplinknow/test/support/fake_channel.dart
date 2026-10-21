// Test helpers for the Dart unit tests (FLT-24): a scripted native side for the method channel.
import 'package:deeplinknow/src/deeplinknow.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scripted native side for the `com.deeplinknow/flutter` channel.
class FakeNative {
  /// Every call the Dart layer made, in order.
  final List<MethodCall> calls = [];

  /// Per-method responses: a value to return, or a function `(MethodCall) => value`. Throwing a
  /// [PlatformException] from the function simulates a native error.
  final Map<String, Object? Function(MethodCall call)> handlers = {};

  /// Warnings the SDK logged.
  final List<String> logs = [];

  /// Sets a fixed return value for [method].
  void returns(String method, Object? value) => handlers[method] = (_) => value;

  /// Makes [method] fail like the native plugin does.
  void fails(
    String method, {
    required String code,
    String? message,
    Map<String, Object?>? details,
  }) =>
      handlers[method] =
          (_) => throw PlatformException(code: code, message: message, details: details);

  /// The calls made to [method].
  List<MethodCall> callsTo(String method) => calls.where((c) => c.method == method).toList();

  /// Installs the fake; removes the native handler entirely when [missingPlugin] is true.
  void install({bool missingPlugin = false}) {
    DeepLinkNow.resetForTesting();
    DeepLinkNow.logSink = logs.add;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    if (missingPlugin) {
      messenger.setMockMethodCallHandler(DeepLinkNow.channel, null);
      return;
    }
    messenger.setMockMethodCallHandler(DeepLinkNow.channel, (call) async {
      calls.add(call);
      final handler = handlers[call.method];
      if (handler == null) throw MissingPluginException('No handler for ${call.method}');
      return handler(call);
    });
  }

  /// Removes the fake.
  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DeepLinkNow.channel, null);
    DeepLinkNow.resetForTesting();
  }
}

/// Native payloads, as the iOS / Android glue sends them.
abstract final class Payloads {
  static Map<String, Object?> appInfo() => {
        'id': 'app_123',
        'alias': 'myapp',
        'name': 'My App',
        'domains': ['myapp.deeplinknow.com', 'go.myapp.com'],
        'primaryDomain': 'go.myapp.com',
        'accountStatus': 'active',
        'creditsRemaining': 990,
      };

  static Map<String, Object?> matchDetails() => {
        'ip_match': {'matched': true, 'score': 40.0},
        'device_match': {
          'matched': true,
          'score': 30,
          'components': {
            'platform': true,
            'os_version': true,
            'device_model': true,
            'hardware_fingerprint': false,
          },
        },
        'time_proximity': {'score': 20.0, 'time_difference_minutes': 2},
        'locale_match': {
          'matched': false,
          'score': 0,
          'components': {'language': false, 'timezone': true},
        },
      };

  static Map<String, Object?> clipboardLink() => {
        'path': '/products/123',
        'queryParams': {
          'ref': 'newsletter',
          'debug': true,
          'tag': ['a', 'b'],
        },
        'fullPath': '/products/123?ref=newsletter&debug&tag=a&tag=b',
        'url': 'https://myapp.deeplinknow.com/products/123?ref=newsletter&debug&tag=a&tag=b',
        'source': 'clipboard',
        'confidenceScore': 100,
        'matchQuality': 'HIGH',
      };

  static Map<String, Object?> fingerprintLink() => {
        'path': '/promo',
        'queryParams': {'code': 'SAVE20'},
        'fullPath': '/promo?code=SAVE20',
        'url': 'https://go.myapp.com/promo?code=SAVE20',
        'source': 'fingerprint',
        'confidenceScore': 62.5,
        'matchQuality': 'MEDIUM',
        'deeplinkId': 'dl_1',
        'targetUrl': 'promo?code=SAVE20',
        'campaignId': 'camp_9',
        'metadata': {
          'title': 'Promo',
          'nested': {
            'list': [1, 'x'],
          },
        },
        'matchedAt': '2026-10-21T10:00:00Z',
        'expiresAt': '2026-10-21T11:00:00Z',
        'matchDetails': matchDetails(),
      };

  static Map<String, Object?> matchResponse() => {
        'matches': [
          {
            'confidence_score': 90.0,
            'match_quality': 'HIGH',
            'match_details': matchDetails(),
            'deeplink': {
              'id': 'dl_1',
              'target_url': 'https://go.myapp.com/a',
              'metadata': <String, Object?>{},
              'campaign_id': null,
              'matched_at': '2026-10-21T10:00:00Z',
              'expires_at': '2026-10-21T11:00:00Z',
              'query_params': {'x': '1'},
              'full_path': '/a?x=1',
            },
          },
          {
            'confidence_score': 35,
            'match_quality': 'LOW',
            'match_details': matchDetails(),
          },
        ],
        'ttl_seconds': 3600,
      };
}
