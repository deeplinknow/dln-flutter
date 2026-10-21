import 'package:deeplinknow/deeplinknow.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;

  setUp(() {
    native = FakeNative()..install();
  });
  tearDown(() => native.uninstall());

  group('findDeferredUser', () {
    test('FLT-12 FLT-05 decodes the full wire response in server order, unfiltered', () async {
      native.returns('findDeferredUser', Payloads.matchResponse());

      final response = (await DeepLinkNow.findDeferredUser())!;

      expect(response.ttlSeconds, 3600);
      expect(response.matches, hasLength(2));
      final first = response.matches[0];
      expect(first.confidenceScore, 90);
      expect(first.matchQuality, MatchQuality.high);
      expect(first.matchDetails.ipMatch.score, 40);
      expect(first.deeplink!.id, 'dl_1');
      expect(first.deeplink!.targetUrl, 'https://go.myapp.com/a');
      expect(first.deeplink!.campaignId, isNull);
      expect(first.deeplink!.metadata, isEmpty);
      expect(first.deeplink!.queryParams, {'x': const SingleQueryValue('1')});
      expect(first.deeplink!.fullPath, '/a?x=1');
      final second = response.matches[1];
      expect(second.confidenceScore, 35);
      expect(second.matchQuality, MatchQuality.low);
      expect(second.deeplink, isNull);
    });

    test('FLT-12 zero matches is a successful empty response', () async {
      native.returns('findDeferredUser', {'matches': <Object?>[], 'ttl_seconds': 3600});

      final response = await DeepLinkNow.findDeferredUser();

      expect(response!.matches, isEmpty);
      expect(DeepLinkNow.lastError, isNull);
    });

    test('FLT-12 FLT-09 never throws: a failure resolves null and sets lastError', () async {
      native.fails('findDeferredUser',
          code: 'rateLimited', message: 'slow down', details: {'status': 429});

      expect(await DeepLinkNow.findDeferredUser(), isNull);
      expect(DeepLinkNow.lastError!.code, DLNErrorCode.rateLimited);
      expect(DeepLinkNow.lastError!.status, 429);

      native.returns('findDeferredUser', Payloads.matchResponse());
      await DeepLinkNow.findDeferredUser();
      expect(DeepLinkNow.lastError, isNull);
    });

    test('FLT-10 a malformed response resolves null with invalidResponse', () async {
      native.returns('findDeferredUser', {'matches': 'nope', 'ttl_seconds': 1});

      expect(await DeepLinkNow.findDeferredUser(), isNull);
      expect(DeepLinkNow.lastError!.code, DLNErrorCode.invalidResponse);
    });
  });

  group('getReferrerData', () {
    test('FLT-13 decodes the Android referrer result', () async {
      native.returns('getReferrerData', {
        'referrerString': 'fp_id=abc',
        'processedAt': 1792576800000,
        'fpId': 'abc',
        'deeplinkData': {
          'id': 'dl_3',
          'targetUrl': 'https://myapp.deeplinknow.com/x',
          'metadata': <String, Object?>{},
          'matchedAt': '2026-10-21T10:00:00Z',
          'expiresAt': '2026-10-21T11:00:00Z',
          'queryParams': {'flag': true},
          'fullPath': '/x?flag',
        },
      });

      final data = (await DeepLinkNow.getReferrerData())!;

      expect(data.referrerString, 'fp_id=abc');
      expect(data.processedAt, DateTime.fromMillisecondsSinceEpoch(1792576800000, isUtc: true));
      expect(data.fpId, 'abc');
      expect(data.deeplinkId, isNull);
      expect(data.deeplinkData!.id, 'dl_3');
      expect(data.deeplinkData!.campaignId, isNull);
      expect(data.deeplinkData!.queryParams, {'flag': const FlagQueryValue()});
      expect(data.deeplinkData!.fullPath, '/x?flag');
    });

    test('FLT-13 resolves null on iOS (the native plugin returns nil)', () async {
      native.returns('getReferrerData', null);

      expect(await DeepLinkNow.getReferrerData(), isNull);
    });

    test('FLT-13 never throws', () async {
      native.fails('getReferrerData', code: 'invalidResponse', message: 'boom');

      expect(await DeepLinkNow.getReferrerData(), isNull);
      expect(native.logs.single, startsWith('[DeepLinkNow] getReferrerData failed'));
    });
  });

  group('clipboard', () {
    test('FLT-14 checkClipboard returns the native result', () async {
      native.returns('checkClipboard', 'https://myapp.deeplinknow.com/a');

      expect(await DeepLinkNow.checkClipboard(), 'https://myapp.deeplinknow.com/a');
      expect(native.calls.single.arguments, isNull);
    });

    test('FLT-14 checkClipboard resolves null when there is no DLN link or on failure', () async {
      native.returns('checkClipboard', null);
      expect(await DeepLinkNow.checkClipboard(), isNull);

      native.fails('checkClipboard', code: 'invalidResponse');
      expect(await DeepLinkNow.checkClipboard(), isNull);
    });

    test('FLT-14 hasDeepLinkToken returns the native no-prompt result', () async {
      native.returns('hasDeepLinkToken', true);
      expect(await DeepLinkNow.hasDeepLinkToken(), isTrue);

      native.returns('hasDeepLinkToken', false);
      expect(await DeepLinkNow.hasDeepLinkToken(), isFalse);
    });

    test('FLT-14 hasDeepLinkToken resolves false on failure or a missing value', () async {
      native.returns('hasDeepLinkToken', null);
      expect(await DeepLinkNow.hasDeepLinkToken(), isFalse);

      native.fails('hasDeepLinkToken', code: 'invalidResponse');
      expect(await DeepLinkNow.hasDeepLinkToken(), isFalse);
    });

    test('FLT-14 FLT-07 clipboard calls without the native plugin resolve null / false', () async {
      native.uninstall();
      native = FakeNative()..install(missingPlugin: true);

      expect(await DeepLinkNow.checkClipboard(), isNull);
      expect(await DeepLinkNow.hasDeepLinkToken(), isFalse);
    });
  });

  group('parseDeepLink', () {
    test('FLT-15 sends the URL to native and decodes the parsed link', () async {
      native.returns('parseDeepLink', {
        'path': '/products/123',
        'queryParams': {'q': 'a b'},
        'fullPath': '/products/123?q=a+b',
        'url': 'https://go.myapp.com/products/123?q=a+b',
      });

      final parsed = (await DeepLinkNow.parseDeepLink('https://go.myapp.com/products/123?q=a+b'))!;

      expect(native.calls.single.arguments, {'url': 'https://go.myapp.com/products/123?q=a+b'});
      expect(parsed.path, '/products/123');
      expect(parsed.queryParams['q']!.stringValue, 'a b');
      expect(parsed.fullPath, '/products/123?q=a+b');
      expect(parsed.url, 'https://go.myapp.com/products/123?q=a+b');
    });

    test('FLT-15 returns null for a URL that is not on the app domains', () async {
      native.returns('parseDeepLink', null);

      expect(await DeepLinkNow.parseDeepLink('https://evil.com/?u=x.deeplinknow.com'), isNull);
    });

    test('FLT-15 never throws: native errors and bad shapes resolve null', () async {
      native.fails('parseDeepLink', code: 'invalidResponse');
      expect(await DeepLinkNow.parseDeepLink('https://myapp.deeplinknow.com/a'), isNull);

      native.returns('parseDeepLink', {'path': 1});
      expect(await DeepLinkNow.parseDeepLink('https://myapp.deeplinknow.com/a'), isNull);
    });

    test('FLT-15 FLT-01 has no Dart fallback: without the native plugin it resolves null',
        () async {
      native.uninstall();
      native = FakeNative()..install(missingPlugin: true);

      expect(await DeepLinkNow.parseDeepLink('https://myapp.deeplinknow.com/a'), isNull);
    });
  });

  group('isValidDomain', () {
    test('FLT-16 sends the host to native and returns its answer', () async {
      native.handlers['isValidDomain'] =
          (call) => (call.arguments as Map)['host'] == 'myapp.deeplinknow.com';

      expect(await DeepLinkNow.isValidDomain('myapp.deeplinknow.com'), isTrue);
      expect(await DeepLinkNow.isValidDomain('myapp.deeplink.now'), isFalse);
      expect(native.calls.first.arguments, {'host': 'myapp.deeplinknow.com'});
    });

    test('FLT-16 FLT-01 resolves false on failure, with no Dart host rule', () async {
      native.fails('isValidDomain', code: 'invalidResponse');
      expect(await DeepLinkNow.isValidDomain('myapp.deeplinknow.com'), isFalse);

      native.uninstall();
      native = FakeNative()..install(missingPlugin: true);
      expect(await DeepLinkNow.isValidDomain('myapp.deeplinknow.com'), isFalse);
    });
  });
}
