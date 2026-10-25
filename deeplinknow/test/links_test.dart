// One link object for every open (1.4.0): SDK-86…92, FLT-25…31.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:deeplinknow/deeplinknow.dart';
import 'package:deeplinknow/src/link.dart' show stripDlnFragment;
import 'package:deeplinknow/src/resolve_http.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_channel.dart';

const _host = 'https://myapp.deeplinknow.com';

/// The native parse, for the fake: links on myapp.deeplinknow.com and go.myapp.com only.
/// Keeps the fragment in `url`, as the 1.3.0 native SDKs do.
Map<String, Object?>? _parse(String url) {
  final host = [_host, 'https://go.myapp.com'].where((h) => url.startsWith('$h/')).firstOrNull;
  if (host == null) return null;
  final rest = url.substring(host.length);
  final noFragment = rest.split('#').first;
  final q = noFragment.indexOf('?');
  return {
    'path': q < 0 ? noFragment : noFragment.substring(0, q),
    'queryParams': <String, Object?>{},
    'fullPath': noFragment,
    'url': url,
  };
}

/// The native side sends a URL event (`onLinkUrl`) to Dart.
Future<void> _nativeOpens(String url) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    DeepLinkNow.channel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall('onLinkUrl', url)),
    (_) {},
  );
  await pumpEventQueue();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;
  late List<String> launchUrls;
  late List<DLNLink> received;
  StreamSubscription<DLNLink>? sub;

  setUp(() {
    native = FakeNative()..install();
    launchUrls = [];
    received = [];
    native
      ..returns('initialize', Payloads.appInfo())
      ..returns('checkDeferredDeepLink', null);
    native.handlers['parseDeepLink'] = (call) => _parse((call.arguments as Map)['url'] as String);
    native.handlers['startLinks'] = (_) {
      final urls = [...launchUrls];
      launchUrls.clear();
      return urls;
    };
  });

  tearDown(() async {
    await sub?.cancel();
    sub = null;
    debugDefaultTargetPlatformOverride = null;
    native.uninstall();
  });

  void subscribe() => sub = DeepLinkNow.links.listen(received.add);

  Future<void> start([DLNLinkOptions options = const DLNLinkOptions()]) async {
    DeepLinkNow.listen(options);
    await DeepLinkNow.initialize('dln_pub_test');
    await pumpEventQueue();
  }

  group('delivery (SDK-86, SDK-87)', () {
    test('SDK-86 FLT-25 a deferred link arrives on the stream as type deferred', () async {
      native.returns('checkDeferredDeepLink', Payloads.fingerprintLink());
      subscribe();

      await start(const DLNLinkOptions(minConfidence: 50, useClipboard: false));

      final link = received.single;
      expect(link.type, DLNLinkType.deferred);
      expect(link.source, DLNLinkSource.fingerprint);
      expect(link.fullPath, '/promo?code=SAVE20');
      expect(link.confidenceScore, 62.5);
      expect(link.matchQuality, MatchQuality.medium);
      expect(link.deeplinkId, 'dl_1');
      expect(link.matchDetails, isNotNull);
      expect(native.callsTo('checkDeferredDeepLink').single.arguments,
          {'minConfidence': 50.0, 'useClipboard': false, 'force': false});
    });

    test('SDK-86 FLT-25 the deferred check waits for initialize, which may come later', () async {
      native.returns('checkDeferredDeepLink', Payloads.clipboardLink());
      subscribe();
      DeepLinkNow.listen();
      await pumpEventQueue();
      expect(native.callsTo('checkDeferredDeepLink'), isEmpty);

      await DeepLinkNow.initialize('dln_pub_test');
      await pumpEventQueue();

      expect(received.single.source, DLNLinkSource.clipboard);
    });

    test('SDK-86 a failed initialize still releases the stream: no link, lastError set', () async {
      native.fails('initialize', code: 'network');
      native.fails('checkDeferredDeepLink', code: 'notInitialized');
      launchUrls.add('$_host/direct');
      subscribe();

      await start();

      expect(received.single.fullPath, '/direct');
      expect(DeepLinkNow.lastError?.code, DLNErrorCode.notInitialized);
    });

    test('SDK-87 FLT-26 the launch URL from the platform side arrives as type direct', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      launchUrls.add('$_host/products/123?ref=x');
      subscribe();

      await start();

      final link = received.single;
      expect(link.type, DLNLinkType.direct);
      expect(link.source, DLNLinkSource.universalLink);
      expect(link.path, '/products/123');
      expect(link.fullPath, '/products/123?ref=x');
      expect(link.confidenceScore, 100);
      expect(link.matchQuality, MatchQuality.high);
      expect(link.deeplinkId, isNull);
    });

    test('SDK-87 FLT-26 later URL events arrive too; App Links are appLink on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      subscribe();
      await start();

      await _nativeOpens('$_host/later');

      expect(received.single.fullPath, '/later');
      expect(received.single.source, DLNLinkSource.appLink);
    });

    test('SDK-87 a URL that is not on the app\'s link domains is not delivered', () async {
      launchUrls.add('https://evil.com/a');
      subscribe();
      await start();
      await _nativeOpens('myapp://products/1');

      expect(received, isEmpty);
    });

    test('SDK-86 FLT-25 a listener that subscribes late gets the latest undelivered link once',
        () async {
      launchUrls.addAll(['$_host/first', '$_host/second']);
      await start();

      subscribe();
      await pumpEventQueue();
      final late2 = <DLNLink>[];
      final sub2 = DeepLinkNow.links.listen(late2.add);
      await pumpEventQueue();
      await sub2.cancel();

      expect(received.map((l) => l.fullPath), ['/second']);
      expect(late2, isEmpty, reason: 'replayed once, not to every new listener');
    });
  });

  group('dedupe (SDK-88)', () {
    test('SDK-88 FLT-27 an OS replay of the same URL is delivered once', () async {
      var now = DateTime.utc(2026, 10, 24, 12);
      DeepLinkNow.clock = () => now;
      launchUrls.add('$_host/a');
      subscribe();
      await start();

      now = now.add(const Duration(milliseconds: 2900));
      await _nativeOpens('$_host/a');
      expect(received, hasLength(1), reason: 'within 3 seconds: one open');

      now = now.add(const Duration(seconds: 5));
      await _nativeOpens('$_host/a');
      expect(received, hasLength(2), reason: 'the same link tapped again later is a new open');
    });

    test('SDK-88 FLT-27 a deferred link and a direct open on first launch: both, deferred first',
        () async {
      native.returns('checkDeferredDeepLink', Payloads.clipboardLink());
      launchUrls.add('$_host/direct');
      subscribe();

      await start();

      expect(received.map((l) => l.type), [DLNLinkType.deferred, DLNLinkType.direct]);
    });
  });

  group('hold (SDK-89)', () {
    test('SDK-89 FLT-29 hold keeps the latest link in pendingLink instead of delivering it',
        () async {
      launchUrls.addAll(['$_host/one', '$_host/two']);
      subscribe();

      await start(const DLNLinkOptions(hold: true));

      expect(received, isEmpty);
      expect(DeepLinkNow.pendingLink?.fullPath, '/two');
    });

    test('SDK-89 FLT-29 one held link of each kind, released deferred first', () async {
      native.returns('checkDeferredDeepLink', Payloads.clipboardLink());
      launchUrls.addAll(['$_host/one', '$_host/two']);
      subscribe();
      await start(const DLNLinkOptions(hold: true));

      expect(DeepLinkNow.pendingLink?.type, DLNLinkType.deferred, reason: 'next to deliver');
      expect(DeepLinkNow.pendingLinks.map((l) => l.fullPath),
          ['/products/123?ref=newsletter&debug&tag=a&tag=b', '/two']);
      expect(DeepLinkNow.pendingLinks.first, same(DeepLinkNow.pendingLink));
      DeepLinkNow.releasePendingLink();
      await pumpEventQueue();

      expect(received.map((l) => '${l.type.value} ${l.fullPath}'), [
        'deferred /products/123?ref=newsletter&debug&tag=a&tag=b',
        'direct /two',
      ]);
    });

    test('SDK-86 SDK-89 with no listener, one link of each kind is replayed, deferred first',
        () async {
      native.returns('checkDeferredDeepLink', Payloads.clipboardLink());
      launchUrls.addAll(['$_host/one', '$_host/two']);
      await start();

      subscribe();
      await pumpEventQueue();

      expect(received.map((l) => l.type), [DLNLinkType.deferred, DLNLinkType.direct]);
      expect(received.last.fullPath, '/two');
    });

    test('SDK-89 FLT-29 releasePendingLink delivers it and ends the hold', () async {
      launchUrls.add('$_host/gated');
      subscribe();
      await start(const DLNLinkOptions(hold: true));

      DeepLinkNow.releasePendingLink();
      await pumpEventQueue();
      expect(received.single.fullPath, '/gated');
      expect(DeepLinkNow.pendingLink, isNull);

      await _nativeOpens('$_host/after');
      expect(received.map((l) => l.fullPath), ['/gated', '/after']);
    });

    test('SDK-89 FLT-29 clearPendingLink drops it; the hold stays on', () async {
      launchUrls.add('$_host/dropped');
      subscribe();
      await start(const DLNLinkOptions(hold: true));

      DeepLinkNow.clearPendingLink();
      await pumpEventQueue();
      expect(DeepLinkNow.pendingLink, isNull);
      expect(DeepLinkNow.pendingLinks, isEmpty);
      expect(received, isEmpty);

      await _nativeOpens('$_host/next');
      expect(received, isEmpty);
      expect(DeepLinkNow.pendingLink?.fullPath, '/next');
    });

    test('SDK-89 FLT-29 a held deferred link is released like a direct one', () async {
      native.returns('checkDeferredDeepLink', Payloads.clipboardLink());
      subscribe();
      await start(const DLNLinkOptions(hold: true));

      expect(DeepLinkNow.pendingLink?.type, DLNLinkType.deferred);
      DeepLinkNow.releasePendingLink();
      await pumpEventQueue();
      expect(received.single.type, DLNLinkType.deferred);
    });
  });

  group('resolve (SDK-90)', () {
    late List<(Uri, Map<String, String>, Duration)> requests;

    void server(FutureOr<DLNHttpResponse> Function(Uri uri) respond) {
      requests = [];
      DeepLinkNow.httpGet = (uri, headers, timeout) async {
        requests.add((uri, headers, timeout));
        return respond(uri);
      };
    }

    final found = jsonEncode({
      'deeplink': {
        'id': 'dl_fdl',
        'target_url': 'https://yourapp.com/invite/8Fk2',
        'metadata': {
          'fdl': {'short_link': 'https://links.yourapp.com/abc123'},
        },
        'campaign_id': 'camp_1',
        'matched_at': '2026-10-24T09:20:00.000Z',
        'expires_at': '2026-10-24T10:20:00.000Z',
        'full_path': '/abc123',
        'query_params': <String, Object?>{},
      },
    });

    test('SDK-90 FLT-30 a 200 fills deeplinkId, targetUrl, campaignId and metadata', () async {
      server((_) => DLNHttpResponse(200, found));
      launchUrls.add('$_host/abc123?utm_source=x');
      subscribe();

      await start(const DLNLinkOptions(resolve: true));

      final link = received.single;
      expect(link.type, DLNLinkType.direct);
      expect(link.deeplinkId, 'dl_fdl');
      expect(link.targetUrl, 'https://yourapp.com/invite/8Fk2');
      expect(link.campaignId, 'camp_1');
      expect(link.metadata, {
        'fdl': {'short_link': 'https://links.yourapp.com/abc123'},
      });
      expect(link.fullPath, '/abc123?utm_source=x', reason: 'what the user opened is kept');
      final (uri, headers, timeout) = requests.single;
      expect(uri.toString(),
          'https://deeplinknow.com/api/v1/sdk/resolve?path=%2Fabc123%3Futm_source%3Dx');
      expect(uri.queryParameters['path'], '/abc123?utm_source=x');
      expect(headers['x-api-key'], 'dln_pub_test');
      expect(timeout, const Duration(seconds: 10), reason: 'the default timeout');
    });

    test('SDK-90 FLT-30 a 404 delivers the link unresolved', () async {
      server((_) => const DLNHttpResponse(404, '{"error":"Deeplink not found"}'));
      launchUrls.add('$_host/plain');
      subscribe();

      await start(const DLNLinkOptions(resolve: true));

      expect(received.single.fullPath, '/plain');
      expect(received.single.deeplinkId, isNull);
      expect(native.logs, isEmpty, reason: 'a 404 is normal, not a warning');
    });

    test('SDK-90 FLT-30 a timeout delivers the link unresolved, within the configured timeout',
        () async {
      DeepLinkNow.httpGet = (uri, headers, timeout) => Completer<DLNHttpResponse>().future;
      launchUrls.add('$_host/slow');
      subscribe();
      DeepLinkNow.listen(const DLNLinkOptions(resolve: true));
      await DeepLinkNow.initialize('dln_pub_test', config: const DLNConfig(timeoutMs: 50));
      final started = DateTime.now();

      while (received.isEmpty && DateTime.now().difference(started) < const Duration(seconds: 2)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(received.single.fullPath, '/slow');
      expect(received.single.deeplinkId, isNull);
      expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 1)));
      expect(native.logs.single, contains('resolveLink'));
    });

    test('SDK-90 FLT-30 a server error or a bad body delivers the link unresolved', () async {
      var body = const DLNHttpResponse(500, 'oops');
      server((_) => body);
      await DeepLinkNow.initialize('dln_pub_test');

      expect((await DeepLinkNow.resolveLink('$_host/x'))!.deeplinkId, isNull);
      body = const DLNHttpResponse(200, '<html>captive portal</html>');
      expect((await DeepLinkNow.resolveLink('$_host/x'))!.deeplinkId, isNull);
      expect(native.logs, hasLength(2));
      expect(native.logs.join(), isNot(contains('dln_pub_test')),
          reason: 'the key is never logged');
    });

    test('SDK-90 FLT-30 resolve is off by default: no request', () async {
      server((_) => DLNHttpResponse(200, found));
      launchUrls.add('$_host/abc123');
      subscribe();

      await start();

      expect(requests, isEmpty);
      expect(received.single.deeplinkId, isNull);
    });

    test('SDK-90 FLT-30 resolveLink: resolved, null off-domain, unresolved before initialize',
        () async {
      server((_) => DLNHttpResponse(200, found));

      expect((await DeepLinkNow.resolveLink('$_host/abc123'))!.deeplinkId, isNull,
          reason: 'no key yet: unresolved, no request');
      expect(requests, isEmpty);

      await DeepLinkNow.initialize('dln_pub_test',
          config: const DLNConfig(baseUrl: 'https://staging.example.com/', timeoutMs: 2500));
      final link = (await DeepLinkNow.resolveLink('$_host/abc123'))!;
      expect(link.deeplinkId, 'dl_fdl');
      expect(link.type, DLNLinkType.direct);
      expect(requests.single.$1.toString(),
          'https://staging.example.com/api/v1/sdk/resolve?path=%2Fabc123');
      expect(requests.single.$3, const Duration(milliseconds: 2500));

      expect(await DeepLinkNow.resolveLink('https://evil.com/abc123'), isNull);
    });

    test('SDK-90 FLT-30 the dart:io transport: 200, 404 and timeout against a local server',
        () async {
      final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => httpServer.close(force: true));
      httpServer.listen((request) async {
        final path = request.uri.queryParameters['path'];
        if (path == '/slow') {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        request.response
          ..statusCode = path == '/abc123' && request.headers.value('x-api-key') == 'k' ? 200 : 404
          ..write(path == '/abc123' ? found : '{"error":"Deeplink not found"}');
        await request.response.close();
      });
      final base = 'http://127.0.0.1:${httpServer.port}';

      // flutter_test answers every HttpClient request with 400; use the real client here.
      final saved = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = saved);
      await Future<void>(() async {
        final ok = await platformHttpGet(
            resolveUri(base, '/abc123'), {'x-api-key': 'k'}, const Duration(seconds: 5));
        expect(ok.status, 200);
        expect(((jsonDecode(ok.body) as Map)['deeplink'] as Map)['id'], 'dl_fdl');

        final missing = await platformHttpGet(
            resolveUri(base, '/nope'), {'x-api-key': 'k'}, const Duration(seconds: 5));
        expect(missing.status, 404);

        await expectLater(
          platformHttpGet(resolveUri(base, '/slow'), {}, const Duration(milliseconds: 100)),
          throwsA(isA<TimeoutException>()),
        );
      });
    });
  });

  group('custom schemes (SDK-87)', () {
    test('SDK-87 FLT-26 a declared scheme opens as source scheme; host is the first segment',
        () async {
      native.handlers['isAppScheme'] = (call) => (call.arguments as Map)['scheme'] == 'myapp';
      DeepLinkNow.httpGet = (uri, headers, timeout) => fail('scheme opens are never resolved');
      launchUrls.add('myapp://products/123?x=1#dln=fp_1');
      subscribe();

      await start(const DLNLinkOptions(resolve: true));

      final link = received.single;
      expect(link.type, DLNLinkType.direct);
      expect(link.source, DLNLinkSource.scheme);
      expect(link.path, '/products/123');
      expect(link.fullPath, '/products/123?x=1');
      expect(link.url, 'myapp://products/123?x=1', reason: 'the scheme URL, dln stripped');
      expect(link.deeplinkId, isNull);
      expect(native.callsTo('parseDeepLink').last.arguments,
          {'url': 'https://go.myapp.com/products/123?x=1#dln=fp_1'},
          reason: 'parsed natively as if on the primary domain (FLT-01)');
    });

    test('SDK-87 FLT-26 undeclared and system schemes are not delivered', () async {
      native.handlers['isAppScheme'] = (call) => (call.arguments as Map)['scheme'] == 'myapp';
      launchUrls.addAll(['other://a', 'mailto:x@y.z', 'tel:123', 'not a url']);
      subscribe();

      await start();

      expect(received, isEmpty);
      expect(native.callsTo('isAppScheme').map((c) => (c.arguments as Map)['scheme']), ['other']);
    });

    test('SDK-87 FLT-26 options.schemes replaces the declared ones', () async {
      native.handlers['isAppScheme'] = (_) => true;
      launchUrls.addAll(['declared://a', 'listed://b']);
      subscribe();

      await start(const DLNLinkOptions(schemes: ['Listed']));

      expect(received.map((l) => l.fullPath), ['/b']);
      expect(native.callsTo('isAppScheme'), isEmpty);
    });

    test('SDK-87 FLT-26 SDK-90 resolveLink returns a scheme link unresolved', () async {
      native.returns('isAppScheme', true);
      var requests = 0;
      DeepLinkNow.httpGet = (uri, headers, timeout) async {
        requests++;
        return const DLNHttpResponse(404, '');
      };
      await DeepLinkNow.initialize('dln_pub_test');

      final link = await DeepLinkNow.resolveLink('myapp://invite');
      expect(link?.source, DLNLinkSource.scheme);
      expect(link?.fullPath, '/invite');
      expect(requests, 0);
    });
  });

  group('dln fragment (SDK-92)', () {
    test('SDK-92 FLT-31 the dln fragment parameter is stripped, other fragment content kept', () {
      expect(stripDlnFragment('$_host/a?x=1#dln=fp_1'), '$_host/a?x=1');
      expect(stripDlnFragment('$_host/a#top&dln=fp_1'), '$_host/a#top');
      expect(stripDlnFragment('$_host/a#dln=fp_1&top'), '$_host/a#top');
      expect(stripDlnFragment('$_host/a#%64ln=fp_1'), '$_host/a', reason: 'decoded name');
      expect(stripDlnFragment('$_host/a#dlnx=1'), '$_host/a#dlnx=1');
      expect(stripDlnFragment('$_host/a#top'), '$_host/a#top');
      expect(stripDlnFragment('$_host/a?dln=keep'), '$_host/a?dln=keep',
          reason: 'the query is never touched');
    });

    test('SDK-92 FLT-31 parseDeepLink, deferred and direct links never carry it', () async {
      final parsed = await DeepLinkNow.parseDeepLink('$_host/p?x=1#dln=fp_1');
      expect(parsed!.url, '$_host/p?x=1');
      expect(parsed.fullPath, '/p?x=1');

      native.returns('checkDeferredDeepLink', {
        ...Payloads.clipboardLink(),
        'url': '$_host/products/123?ref=newsletter#dln=fp_9',
      });
      launchUrls.add('$_host/d#dln=fp_2');
      subscribe();
      await start();

      expect(received.map((l) => l.url), [
        '$_host/products/123?ref=newsletter',
        '$_host/d',
      ]);
    });
  });

  group('existing calls (SDK-91)', () {
    test('SDK-91 FLT-25 listen runs one deferred check, however often it is called', () async {
      subscribe();
      DeepLinkNow.listen();
      DeepLinkNow.listen(const DLNLinkOptions(hold: true));
      await DeepLinkNow.initialize('dln_pub_test');
      await pumpEventQueue();

      expect(native.callsTo('checkDeferredDeepLink'), hasLength(1));
      expect(native.callsTo('startLinks'), hasLength(1));
    });

    test('SDK-91 checkDeferredDeepLink and parseDeepLink are unchanged without listen', () async {
      native.returns('checkDeferredDeepLink', Payloads.clipboardLink());
      await DeepLinkNow.initialize('dln_pub_test');

      final link = await DeepLinkNow.checkDeferredDeepLink(force: true);
      final parsed = await DeepLinkNow.parseDeepLink('$_host/a?b=1');

      expect(link, isA<DeferredDeepLink>());
      expect(link!.source, DeferredDeepLinkSource.clipboard);
      expect(native.callsTo('checkDeferredDeepLink').single.arguments,
          {'minConfidence': null, 'useClipboard': true, 'force': true});
      expect(parsed!.fullPath, '/a?b=1');
      expect(native.callsTo('startLinks'), isEmpty, reason: 'nothing new runs until listen');
    });

    test('SDK-91 without the native plugin, listen never throws and delivers nothing', () async {
      native.uninstall();
      native = FakeNative()..install(missingPlugin: true);
      subscribe();

      DeepLinkNow.listen();
      await DeepLinkNow.initialize('dln_pub_test');
      await pumpEventQueue();

      expect(received, isEmpty);
      expect(DeepLinkNow.pendingLink, isNull);
    });
  });
}
