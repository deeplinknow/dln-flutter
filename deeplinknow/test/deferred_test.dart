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

  group('checkDeferredDeepLink', () {
    test('FLT-06 passes the default options through unchanged', () async {
      native.returns('checkDeferredDeepLink', null);

      await DeepLinkNow.checkDeferredDeepLink();

      expect(native.calls.single.method, 'checkDeferredDeepLink');
      expect(native.calls.single.arguments, {
        'minConfidence': null,
        'useClipboard': true,
        'force': false,
      });
    });

    test('FLT-06 passes minConfidence, useClipboard and force through unchanged', () async {
      native.returns('checkDeferredDeepLink', null);

      await DeepLinkNow.checkDeferredDeepLink(minConfidence: 75, useClipboard: false, force: true);

      expect(native.calls.single.arguments, {
        'minConfidence': 75.0,
        'useClipboard': false,
        'force': true,
      });
    });

    test('FLT-06 resolves null when there is no link, without setting lastError', () async {
      native.returns('checkDeferredDeepLink', null);

      expect(await DeepLinkNow.checkDeferredDeepLink(), isNull);
      expect(DeepLinkNow.lastError, isNull);
    });

    test('FLT-05 FLT-17 decodes an exact clipboard result with every query value kind', () async {
      native.returns('checkDeferredDeepLink', Payloads.clipboardLink());

      final link = (await DeepLinkNow.checkDeferredDeepLink())!;

      expect(link.path, '/products/123');
      expect(link.fullPath, '/products/123?ref=newsletter&debug&tag=a&tag=b');
      expect(
          link.url, 'https://myapp.deeplinknow.com/products/123?ref=newsletter&debug&tag=a&tag=b');
      expect(link.source, DeferredDeepLinkSource.clipboard);
      expect(link.confidenceScore, 100.0);
      expect(link.matchQuality, MatchQuality.high);
      expect(link.queryParams['ref'], const SingleQueryValue('newsletter'));
      expect(link.queryParams['debug'], const FlagQueryValue());
      expect(link.queryParams['tag'], const MultipleQueryValue(['a', 'b']));
      expect(link.queryParams.keys, ['ref', 'debug', 'tag']);
      expect(link.deeplinkId, isNull);
      expect(link.matchDetails, isNull);
    });

    test('FLT-05 decodes a fingerprint result with the server fields and match details', () async {
      native.returns('checkDeferredDeepLink', Payloads.fingerprintLink());

      final link = (await DeepLinkNow.checkDeferredDeepLink())!;

      expect(link.source, DeferredDeepLinkSource.fingerprint);
      expect(link.confidenceScore, 62.5);
      expect(link.matchQuality, MatchQuality.medium);
      expect(link.deeplinkId, 'dl_1');
      expect(link.targetUrl, 'promo?code=SAVE20');
      expect(link.campaignId, 'camp_9');
      expect(link.metadata, {
        'title': 'Promo',
        'nested': {
          'list': [1, 'x'],
        },
      });
      expect(link.matchedAt, '2026-10-21T10:00:00Z');
      expect(link.expiresAt, '2026-10-21T11:00:00Z');
      final details = link.matchDetails!;
      expect(details.ipMatch.matched, isTrue);
      expect(details.ipMatch.score, 40);
      expect(details.deviceMatch.score, 30);
      expect(details.deviceMatch.osVersion, isTrue);
      expect(details.deviceMatch.hardwareFingerprint, isFalse);
      expect(details.timeProximity.timeDifferenceMinutes, 2);
      expect(details.localeMatch.matched, isFalse);
      expect(details.localeMatch.timezone, isTrue);
    });

    test('FLT-05 decodes an Android referrer result', () async {
      native.returns('checkDeferredDeepLink', {
        'path': '/a',
        'queryParams': <String, Object?>{},
        'fullPath': '/a',
        'url': 'https://myapp.deeplinknow.com/a',
        'source': 'referrer',
        'confidenceScore': 100.0,
        'matchQuality': 'HIGH',
        'deeplinkId': 'dl_2',
      });

      final link = (await DeepLinkNow.checkDeferredDeepLink())!;

      expect(link.source, DeferredDeepLinkSource.referrer);
      expect(link.queryParams, isEmpty);
    });

    test('FLT-06 FLT-07 never throws: notInitialized with its cause resolves null', () async {
      native.fails(
        'checkDeferredDeepLink',
        code: 'notInitialized',
        message: 'notInitialized',
        details: {'causeCode': 'invalidApiKey', 'causeMessage': 'Invalid API key'},
      );

      expect(await DeepLinkNow.checkDeferredDeepLink(), isNull);
      final error = DeepLinkNow.lastError!;
      expect(error.code, DLNErrorCode.notInitialized);
      expect(error.cause!.code, DLNErrorCode.invalidApiKey);
      expect(error.cause!.message, 'Invalid API key');
      expect(native.logs.single, startsWith('[DeepLinkNow] checkDeferredDeepLink failed'));
    });

    test('FLT-09 lastError is cleared by the next successful check, even with no link', () async {
      native.fails('checkDeferredDeepLink', code: 'network', message: 'offline');
      await DeepLinkNow.checkDeferredDeepLink();
      expect(DeepLinkNow.lastError!.code, DLNErrorCode.network);

      native.returns('checkDeferredDeepLink', null);
      await DeepLinkNow.checkDeferredDeepLink();
      expect(DeepLinkNow.lastError, isNull);
    });

    test('FLT-09 a success of another kind does not clear lastError', () async {
      native.fails('checkDeferredDeepLink',
          code: 'server', message: 'boom', details: {'status': 503});
      await DeepLinkNow.checkDeferredDeepLink();

      native.returns('initialize', Payloads.appInfo());
      await DeepLinkNow.initialize('dln_pub_test');

      expect(DeepLinkNow.lastError!.code, DLNErrorCode.server);
      expect(DeepLinkNow.lastError!.status, 503);
    });

    test('FLT-10 a malformed result resolves null with invalidResponse', () async {
      native.returns('checkDeferredDeepLink', {
        ...Payloads.clipboardLink(),
        'source': 'carrier-pigeon',
      });

      expect(await DeepLinkNow.checkDeferredDeepLink(), isNull);
      expect(DeepLinkNow.lastError!.code, DLNErrorCode.invalidResponse);
    });

    test('FLT-10 a non-map result resolves null with invalidResponse', () async {
      native.returns('checkDeferredDeepLink', 'not a map');

      expect(await DeepLinkNow.checkDeferredDeepLink(), isNull);
      expect(DeepLinkNow.lastError!.code, DLNErrorCode.invalidResponse);
    });

    test('FLT-10 a bad query value resolves null with invalidResponse', () async {
      native.returns('checkDeferredDeepLink', {
        ...Payloads.clipboardLink(),
        'queryParams': {'n': 3},
      });

      expect(await DeepLinkNow.checkDeferredDeepLink(), isNull);
      expect(DeepLinkNow.lastError!.code, DLNErrorCode.invalidResponse);
    });
  });

  group('resetDeferredDeepLink', () {
    test('FLT-11 calls the native reset', () async {
      native.returns('resetDeferredDeepLink', true);

      await DeepLinkNow.resetDeferredDeepLink();

      expect(native.callsTo('resetDeferredDeepLink'), hasLength(1));
    });

    test('FLT-11 throws a DLNError when the native reset fails', () async {
      native.fails('resetDeferredDeepLink', code: 'invalidResponse', message: 'disk full');

      await expectLater(
        DeepLinkNow.resetDeferredDeepLink(),
        throwsA(isA<DLNError>().having((e) => e.code, 'code', DLNErrorCode.invalidResponse)),
      );
    });
  });
}
