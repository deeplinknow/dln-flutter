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

  group('initialize', () {
    test('FLT-04 makes exactly one native initialize call with the key and the config', () async {
      native.returns('initialize', Payloads.appInfo());

      await DeepLinkNow.initialize(
        'dln_pub_test',
        config: const DLNConfig(
          enableLogs: true,
          baseUrl: 'https://staging.deeplinknow.com',
          timeoutMs: 5000,
          retryAttempts: 1,
        ),
      );

      expect(native.calls, hasLength(1));
      expect(native.calls.single.method, 'initialize');
      expect(native.calls.single.arguments, {
        'apiKey': 'dln_pub_test',
        'config': {
          'enableLogs': true,
          'baseUrl': 'https://staging.deeplinknow.com',
          'timeoutMs': 5000,
          'retryAttempts': 1,
        },
      });
    });

    test('FLT-04 omits unset config values so the native defaults apply (SDK-01)', () async {
      native.returns('initialize', Payloads.appInfo());

      await DeepLinkNow.initialize('dln_pub_test');

      expect(native.calls.single.arguments, {
        'apiKey': 'dln_pub_test',
        'config': {'enableLogs': false},
      });
    });

    test('FLT-04 FLT-05 resolves the typed app info on success', () async {
      native.returns('initialize', Payloads.appInfo());

      final info = await DeepLinkNow.initialize('dln_pub_test');

      expect(info, isNotNull);
      expect(info!.id, 'app_123');
      expect(info.alias, 'myapp');
      expect(info.name, 'My App');
      expect(info.domains, ['myapp.deeplinknow.com', 'go.myapp.com']);
      expect(info.primaryDomain, 'go.myapp.com');
      expect(info.accountStatus, 'active');
      expect(info.creditsRemaining, 990);
    });

    test('FLT-05 tolerates the Android shape (null name and credits)', () async {
      native.returns('initialize', {
        'id': 'app_1',
        'alias': 'myapp',
        'name': null,
        'domains': ['myapp.deeplinknow.com'],
        'primaryDomain': 'myapp.deeplinknow.com',
        'accountStatus': 'active',
        'creditsRemaining': null,
      });

      final info = await DeepLinkNow.initialize('dln_pub_test');

      expect(info!.name, isNull);
      expect(info.creditsRemaining, isNull);
    });

    test('FLT-19 isInitialized and appInfo follow the last initialize', () async {
      expect(DeepLinkNow.isInitialized, isFalse);
      expect(DeepLinkNow.appInfo, isNull);

      native.returns('initialize', Payloads.appInfo());
      await DeepLinkNow.initialize('dln_pub_test');
      expect(DeepLinkNow.isInitialized, isTrue);
      expect(DeepLinkNow.appInfo!.alias, 'myapp');

      native.fails('initialize',
          code: 'invalidApiKey', message: 'Invalid API key', details: {'status': 401});
      await DeepLinkNow.initialize('dln_pub_revoked');
      expect(DeepLinkNow.isInitialized, isFalse);
      expect(DeepLinkNow.appInfo, isNull);
    });

    test('FLT-04 FLT-09 never throws: a failure resolves null and sets lastError', () async {
      native.fails(
        'initialize',
        code: 'invalidApiKey',
        message: 'Invalid API key (HTTP 401)',
        details: {'status': 401, 'serverMessage': 'Invalid API key'},
      );

      final info = await DeepLinkNow.initialize('dln_pub_bad');

      expect(info, isNull);
      final error = DeepLinkNow.lastError!;
      expect(error.code, DLNErrorCode.invalidApiKey);
      expect(error.status, 401);
      expect(error.serverMessage, 'Invalid API key');
    });

    test('FLT-18 a failure logs one [DeepLinkNow] warning without the API key', () async {
      native.fails('initialize', code: 'network', message: 'offline');

      await DeepLinkNow.initialize('dln_pub_secretkey1234');

      expect(native.logs, hasLength(1));
      expect(native.logs.single, startsWith('[DeepLinkNow] initialize failed'));
      expect(native.logs.single, isNot(contains('dln_pub_secretkey1234')));
    });

    test('FLT-09 a successful initialize clears an initialize error', () async {
      native.fails('initialize', code: 'network', message: 'offline');
      await DeepLinkNow.initialize('dln_pub_test');
      expect(DeepLinkNow.lastError?.code, DLNErrorCode.network);

      native.returns('initialize', Payloads.appInfo());
      await DeepLinkNow.initialize('dln_pub_test');
      expect(DeepLinkNow.lastError, isNull);
    });

    test('FLT-10 a malformed app info resolves null with invalidResponse', () async {
      native.returns('initialize', {'id': 42});

      final info = await DeepLinkNow.initialize('dln_pub_test');

      expect(info, isNull);
      expect(DeepLinkNow.isInitialized, isFalse);
      expect(DeepLinkNow.lastError!.code, DLNErrorCode.invalidResponse);
    });

    test('FLT-07 a missing native plugin resolves null with notInitialized', () async {
      native.uninstall();
      native = FakeNative()..install(missingPlugin: true);

      final info = await DeepLinkNow.initialize('dln_pub_test');

      expect(info, isNull);
      expect(DeepLinkNow.lastError!.code, DLNErrorCode.notInitialized);
      expect(DeepLinkNow.lastError!.message, contains('native plugin is not available'));
    });
  });
}
