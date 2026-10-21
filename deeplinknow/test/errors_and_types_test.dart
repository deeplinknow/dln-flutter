import 'package:deeplinknow/deeplinknow.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;

  setUp(() {
    native = FakeNative()..install();
  });
  tearDown(() => native.uninstall());

  group('error codes', () {
    test('FLT-07 every SDK-55 code maps to the same enum value', () async {
      const codes = {
        'notInitialized': DLNErrorCode.notInitialized,
        'invalidApiKey': DLNErrorCode.invalidApiKey,
        'accountInactive': DLNErrorCode.accountInactive,
        'noCredits': DLNErrorCode.noCredits,
        'rateLimited': DLNErrorCode.rateLimited,
        'badRequest': DLNErrorCode.badRequest,
        'server': DLNErrorCode.server,
        'network': DLNErrorCode.network,
        'invalidResponse': DLNErrorCode.invalidResponse,
      };
      for (final entry in codes.entries) {
        native.fails('findDeferredUser', code: entry.key, message: entry.key);
        await DeepLinkNow.findDeferredUser();
        expect(DeepLinkNow.lastError!.code, entry.value, reason: entry.key);
        expect(entry.value.code, entry.key);
      }
      expect(DLNErrorCode.values, hasLength(codes.length));
    });

    test("FLT-07 iOS's invalidConfiguration is reported as badRequest", () {
      expect(DLNErrorCode.fromCode('invalidConfiguration'), DLNErrorCode.badRequest);
    });

    test('FLT-07 an unknown native code is reported as invalidResponse', () async {
      native.fails('checkDeferredDeepLink', code: 'somethingNew', message: 'x');

      await DeepLinkNow.checkDeferredDeepLink();

      expect(DeepLinkNow.lastError!.code, DLNErrorCode.invalidResponse);
    });

    test('FLT-07 carries status, server message, message and cause', () async {
      native.fails(
        'initialize',
        code: 'accountInactive',
        message: 'Account is not active (HTTP 403)',
        details: {
          'status': 403,
          'serverMessage': 'Account is not active',
          'causeCode': 'server',
          'causeMessage': 'upstream',
        },
      );

      await DeepLinkNow.initialize('dln_pub_test');

      final error = DeepLinkNow.lastError!;
      expect(error.code, DLNErrorCode.accountInactive);
      expect(error.status, 403);
      expect(error.serverMessage, 'Account is not active');
      expect(error.message, 'Account is not active (HTTP 403)');
      expect(error.cause!.code, DLNErrorCode.server);
      expect(error.cause!.message, 'upstream');
      expect(error.toString(),
          'DLNError(accountInactive, HTTP 403: Account is not active (HTTP 403), cause: server)');
    });

    test('FLT-07 tolerates missing or malformed error details', () async {
      native.fails('initialize', code: 'network');
      await DeepLinkNow.initialize('dln_pub_test');
      expect(DeepLinkNow.lastError!.status, isNull);
      expect(DeepLinkNow.lastError!.cause, isNull);

      native.handlers['initialize'] =
          (_) => throw PlatformExceptionWithDetails.make('server', 'not a map');
      await DeepLinkNow.initialize('dln_pub_test');
      expect(DeepLinkNow.lastError!.code, DLNErrorCode.server);
      expect(DeepLinkNow.lastError!.status, isNull);
    });
  });

  group('types', () {
    test('FLT-17 QueryValue decodes the three wire shapes and exposes the RN raw shape', () {
      final single = QueryValue.fromChannel('x');
      final flag = QueryValue.fromChannel(true);
      final multiple = QueryValue.fromChannel(['a', 'b']);

      expect(single, isA<SingleQueryValue>());
      expect(single.stringValue, 'x');
      expect(single.stringValues, ['x']);
      expect(single.rawValue, 'x');

      expect(flag, isA<FlagQueryValue>());
      expect(flag.stringValue, '');
      expect(flag.stringValues, isEmpty);
      expect(flag.rawValue, true);

      expect(multiple, isA<MultipleQueryValue>());
      expect(multiple.stringValue, 'a');
      expect(multiple.stringValues, ['a', 'b']);
      expect(multiple.rawValue, ['a', 'b']);

      expect(const MultipleQueryValue([]).stringValue, '');
      expect(const MultipleQueryValue(['a']).hashCode, const MultipleQueryValue(['a']).hashCode);
      expect(const MultipleQueryValue(['a']), isNot(const MultipleQueryValue(['b'])));
    });

    test('FLT-17 QueryValue rejects other values', () {
      expect(() => QueryValue.fromChannel(false), throwsException);
      expect(() => QueryValue.fromChannel(3), throwsException);
      expect(() => QueryValue.fromChannel([1]), throwsException);
      expect(() => QueryValue.fromChannel(null), throwsException);
    });

    test('FLT-17 query values switch exhaustively', () {
      String describe(QueryValue v) => switch (v) {
            SingleQueryValue(:final value) => 'single $value',
            FlagQueryValue() => 'flag',
            MultipleQueryValue(:final values) => 'multiple ${values.length}',
          };
      expect(describe(const SingleQueryValue('a')), 'single a');
      expect(describe(const FlagQueryValue()), 'flag');
      expect(describe(const MultipleQueryValue(['a', 'b'])), 'multiple 2');
    });

    test('FLT-05 MatchQuality and DeferredDeepLinkSource use the shared wire values', () {
      expect(MatchQuality.values.map((q) => q.value), ['HIGH', 'MEDIUM', 'LOW']);
      expect(MatchQuality.parse('medium'), MatchQuality.medium);
      expect(() => MatchQuality.parse('GREAT'), throwsException);
      expect(DeferredDeepLinkSource.values.map((s) => s.value),
          ['referrer', 'clipboard', 'fingerprint']);
    });

    test('FLT-05 ConfidenceThresholds match the server labels (SDK-16)', () {
      expect(ConfidenceThresholds.high, 75);
      expect(ConfidenceThresholds.medium, 50);
      expect(ConfidenceThresholds.low, 30);
    });

    test('FLT-04 DLNConfig sends only the values that are set', () {
      expect(const DLNConfig().toMap(), {'enableLogs': false});
      expect(const DLNConfig(timeoutMs: 100).toMap(), {'enableLogs': false, 'timeoutMs': 100});
    });
  });
}

/// Builds a PlatformException whose details are not a map.
abstract final class PlatformExceptionWithDetails {
  static Exception make(String code, Object details) =>
      PlatformException(code: code, message: code, details: details);
}
