import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'errors.dart';
import 'link.dart';
import 'resolve_http.dart';
import 'types.dart';

/// Which kind of call set [DeepLinkNow.lastError]; a success of the same kind clears it (SDK-85).
enum _CallKind { initialize, check, find }

/// DeepLinkNow deferred deep linking for Flutter.
///
/// A thin wrapper over the native iOS (`DeepLinkNow` pod) and Android
/// (`com.deeplinknow:dln-android`) SDKs: every call goes over one method channel, and all
/// deferred-link logic (pasteboard / Install Referrer, fingerprint matching, first-launch
/// state, link parsing, the domain rule, error mapping) runs natively (FLT-01).
///
/// ```dart
/// await DeepLinkNow.initialize('dln_pub_…');
/// final link = await DeepLinkNow.checkDeferredDeepLink();
/// if (link != null) router.go(link.path);
/// ```
///
/// The everyday calls never throw (SDK-85): a failure resolves `null` (or `false`), logs one
/// warning and is kept in [lastError].
///
/// Since 1.4.0, [links] delivers every open, deferred or direct, as one [DLNLink] (SDK-86):
///
/// ```dart
/// DeepLinkNow.links.listen((link) => router.go(link.fullPath));
/// DeepLinkNow.listen();
/// await DeepLinkNow.initialize('dln_pub_…');
/// ```
abstract final class DeepLinkNow {
  /// Plugin version. iOS, Android, React Native and Flutter share major.minor (SDK-84).
  static const String sdkVersion = '1.4.2';

  /// The method channel to the native plugin.
  @visibleForTesting
  static const MethodChannel channel = MethodChannel('com.deeplinknow/flutter');

  /// Where warnings go. Tests replace it; apps don't need to.
  @visibleForTesting
  static void Function(String message) logSink = _defaultLog;

  static void _defaultLog(String message) => debugPrint(message);

  static bool _initialized = false;
  static DLNAppInfo? _appInfo;
  static DLNError? _lastError;
  static _CallKind? _lastErrorKind;

  /// Whether the last `initialize` call from Dart succeeded (SDK-05).
  static bool get isInitialized => _initialized;

  /// The app info from the last successful [initialize], or `null`.
  static DLNAppInfo? get appInfo => _appInfo;

  /// The typed error (SDK-55) of the last failed [initialize], [checkDeferredDeepLink] or
  /// [findDeferredUser]. Cleared by the next successful call of the same kind; "no link
  /// found" is a success (SDK-85).
  static DLNError? get lastError => _lastError;

  /// Validates the API key, loads the app's link domains and starts the platform chain
  /// (SDK-01…09). Makes exactly one native initialize call, which makes at most one `/init`
  /// request (none when the native 24-hour init cache serves it, SDK-83).
  ///
  /// Resolves the app info, or `null` on failure. Never throws: the failure is logged and kept
  /// in [lastError] (SDK-85). Use your public key (`dln_pub_…`).
  static Future<DLNAppInfo?> initialize(
    String apiKey, {
    DLNConfig config = const DLNConfig(),
  }) async {
    try {
      final raw = await channel.invokeMethod<Object?>('initialize', {
        'apiKey': apiKey,
        'config': config.toMap(),
      });
      final info = DLNAppInfo.fromMap(raw);
      _initialized = true;
      _appInfo = info;
      _resolveConfig = (
        apiKey: apiKey,
        baseUrl: config.baseUrl ?? _defaultBaseUrl,
        timeout: Duration(milliseconds: config.timeoutMs ?? _defaultTimeoutMs),
      );
      _succeeded(_CallKind.initialize);
      return info;
    } catch (e) {
      _initialized = false;
      _appInfo = null;
      _resolveConfig = null;
      _failed(_CallKind.initialize, 'initialize', e);
      return null;
    } finally {
      // The link pipeline (listen) waits for the first initialize to finish, either way.
      if (!_initFinished.isCompleted) _initFinished.complete();
      // SDK-24: a deferred check that failed (offline, or before this initialize) runs again.
      if (_initialized) _retryDeferredCheck();
    }
  }

  /// **The one call.** Runs the platform chain and resolves the deferred deep link, or `null`
  /// (SDK-10):
  ///
  /// * Android: Play Install Referrer, then fingerprint matching.
  /// * iOS: the pasteboard (when [useClipboard] is `true`), then fingerprint matching.
  ///
  /// Delivers a link once per install; later calls resolve `null` without network access
  /// unless [force] is `true` (SDK-23). [minConfidence] (0–100) discards fingerprint
  /// candidates below it; it is off by default (SDK-14). [useClipboard] is ignored on Android.
  ///
  /// Never throws. `null` means "no link" or "failed"; check [lastError] to tell them apart.
  static Future<DeferredDeepLink?> checkDeferredDeepLink({
    double? minConfidence,
    bool useClipboard = true,
    bool force = false,
  }) async {
    final result = await _checkDeferred(
      minConfidence: minConfidence,
      useClipboard: useClipboard,
      force: force,
    );
    return result.link;
  }

  /// [checkDeferredDeepLink], telling a failure (SDK-24) apart from "no link".
  static Future<({DeferredDeepLink? link, bool failed})> _checkDeferred({
    required double? minConfidence,
    required bool useClipboard,
    required bool force,
  }) async {
    try {
      final raw = await channel.invokeMethod<Object?>('checkDeferredDeepLink', {
        'minConfidence': minConfidence,
        'useClipboard': useClipboard,
        'force': force,
      });
      final link = raw == null ? null : DeferredDeepLink.fromMap(raw);
      _succeeded(_CallKind.check);
      return (link: link, failed: false);
    } catch (e) {
      _failed(_CallKind.check, 'checkDeferredDeepLink', e);
      return (link: null, failed: true);
    }
  }

  /// Clears the first-launch state and any cached referrer result, in memory and on disk
  /// (SDK-26), so the next [checkDeferredDeepLink] runs the chain again. For testing and
  /// debugging. Throws a [DLNError] if the native reset fails.
  static Future<void> resetDeferredDeepLink() async {
    try {
      await channel.invokeMethod<Object?>('resetDeferredDeepLink');
    } catch (e) {
      throw _toError(e);
    }
  }

  /// Low level: every fingerprint candidate from `/sdk/match`, unfiltered and in server order
  /// (SDK-20). Zero matches is an empty response, not an error. Never throws: a failure
  /// resolves `null` and is kept in [lastError].
  static Future<MatchResponse?> findDeferredUser() async {
    try {
      final raw = await channel.invokeMethod<Object?>('findDeferredUser');
      final response = MatchResponse.fromMap(raw);
      _succeeded(_CallKind.find);
      return response;
    } catch (e) {
      _failed(_CallKind.find, 'findDeferredUser', e);
      return null;
    }
  }

  /// Android only: the raw Install Referrer result, after the referrer step has finished.
  /// `null` on iOS, before [initialize], or when there is none. Never throws.
  static Future<ReferrerData?> getReferrerData() async {
    try {
      final raw = await channel.invokeMethod<Object?>('getReferrerData');
      return raw == null ? null : ReferrerData.fromMap(raw);
    } catch (e) {
      _warn('getReferrerData', e);
      return null;
    }
  }

  /// Low level: the clipboard text if it is exactly one of the app's DLN links (SDK-40), else
  /// `null`. On iOS this may show the system paste prompt. Never throws.
  static Future<String?> checkClipboard() async {
    try {
      return await channel.invokeMethod<String>('checkClipboard');
    } catch (e) {
      _warn('checkClipboard', e);
      return null;
    }
  }

  /// Low level: a cheap check, without a paste prompt, that the clipboard probably holds a
  /// link (SDK-41). `true` means "worth calling [checkClipboard]". Never throws.
  static Future<bool> hasDeepLinkToken() async {
    try {
      return await channel.invokeMethod<bool>('hasDeepLinkToken') ?? false;
    } catch (e) {
      _warn('hasDeepLinkToken', e);
      return false;
    }
  }

  /// Parses a link that opened the installed app (Universal Link / App Link) with the native
  /// rules (SDK-30…37): `{path, queryParams, fullPath, url}`, or `null` when [url] is not a
  /// link on the app's domains. No network, no clipboard. Never throws.
  static Future<ParsedDeepLink?> parseDeepLink(String url) async {
    try {
      final raw = await channel.invokeMethod<Object?>('parseDeepLink', {'url': url});
      return raw == null ? null : ParsedDeepLink.fromMap(raw);
    } catch (e) {
      _warn('parseDeepLink', e);
      return null;
    }
  }

  /// Whether [host] is one of the app's link domains (SDK-31, SDK-38). Never throws.
  static Future<bool> isValidDomain(String host) async {
    try {
      return await channel.invokeMethod<bool>('isValidDomain', {'host': host}) ?? false;
    } catch (e) {
      _warn('isValidDomain', e);
      return false;
    }
  }

  // ---------------------------------------------------------------------------------------------
  // One link object for every open (1.4.0, SDK-86…92)
  // ---------------------------------------------------------------------------------------------

  static const String _defaultBaseUrl = 'https://deeplinknow.com';
  static const int _defaultTimeoutMs = 10000;

  /// The same URL again within this window is one open (SDK-88, settled across SDKs).
  static const Duration _replayWindow = Duration(seconds: 3);

  static StreamController<DLNLink> _links = _newLinksController();
  static DLNLinkOptions _linkOptions = const DLNLinkOptions();
  static bool _listening = false;
  static bool _holding = false;
  // The deferred check of [listen] (SDK-86): running, or finished without a failure. A failed
  // check runs again on the next [listen] or successful [initialize] (SDK-24).
  static bool _deferredRunning = false;
  static bool _deferredDone = false;
  // The latest link of each kind, held (SDK-89) or waiting for a listener (SDK-86).
  static DLNLink? _pendingDeferred;
  static DLNLink? _pendingDirect;
  static DLNLink? _undeliveredDeferred;
  static DLNLink? _undeliveredDirect;
  static Future<void> _linkQueue = Future<void>.value();
  static Completer<void> _initFinished = Completer<void>();
  static ({String apiKey, String baseUrl, Duration timeout})? _resolveConfig;
  static String? _lastDirectUrl;
  static DateTime? _lastDirectAt;

  /// The HTTP GET used by resolving (SDK-90). Tests replace it; apps don't need to.
  @visibleForTesting
  static DLNHttpGet httpGet = platformHttpGet;

  /// The clock used for the replay window (SDK-88). Tests replace it; apps don't need to.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static StreamController<DLNLink> _newLinksController() =>
      StreamController<DLNLink>.broadcast(onListen: _replayUndelivered);

  /// Every link the app should open, deferred or direct, as one [DLNLink] (SDK-86).
  ///
  /// A broadcast stream. Call [listen] once at startup (before or after [initialize]) to start
  /// it: links arrive after the first [initialize] call has finished. While nothing listens, the
  /// latest link of each kind (one deferred, one direct) is kept and replayed once to the next
  /// listener, deferred first.
  static Stream<DLNLink> get links => _links.stream;

  /// Starts [links] (SDK-86, SDK-87). Call it once at startup; it doesn't need to wait for
  /// [initialize].
  ///
  /// * Runs the first-launch deferred check once ([checkDeferredDeepLink] with the options'
  ///   `minConfidence`, `useClipboard` and `force`) after the first [initialize] finishes, and
  ///   delivers its link as `type: deferred`.
  /// * Reads the URL that launched the app and every later URL the OS hands it through the
  ///   plugin's platform code, and delivers as `type: direct` the ones on the app's link domains
  ///   (Universal Links on iOS, App Links on Android) and the app's custom schemes
  ///   ([DLNLinkOptions.schemes], else the ones the app declares). The app doesn't forward URLs.
  ///
  /// Calling it again only updates the options: [DLNLinkOptions.hold] and
  /// [DLNLinkOptions.resolve] apply to links delivered after the call; the deferred check is not
  /// run twice (SDK-91). A deferred check that failed (offline, or no successful [initialize]
  /// yet) runs again on the next [listen] call or successful [initialize] (SDK-24). Never
  /// throws.
  static void listen([DLNLinkOptions options = const DLNLinkOptions()]) {
    _linkOptions = options;
    _holding = options.hold;
    if (_listening) {
      _retryDeferredCheck();
      return;
    }
    _listening = true;
    _deferredRunning = true;
    channel.setMethodCallHandler(_onNativeCall);
    _enqueue(() async {
      await _initFinished.future;
      // Deferred first when both are known at once (SDK-88): the URLs the platform side
      // buffered are only taken after the deferred check.
      await _runDeferredCheck();
      for (final url in await _startLinks()) {
        await _handleDirect(url);
      }
    });
  }

  static Future<void> _runDeferredCheck() async {
    final result = await _checkDeferred(
      minConfidence: _linkOptions.minConfidence,
      useClipboard: _linkOptions.useClipboard,
      force: _linkOptions.force,
    );
    _deferredRunning = false;
    _deferredDone = !result.failed;
    final deferred = result.link;
    if (deferred != null) _deliver(DLNLink.fromDeferred(deferred));
  }

  /// SDK-24: runs the deferred check again when the last one failed. Not before the first
  /// [initialize] has finished: the first run waits for it.
  static void _retryDeferredCheck() {
    if (!_listening || _deferredRunning || _deferredDone || !_initFinished.isCompleted) return;
    _deferredRunning = true;
    _enqueue(_runDeferredCheck);
  }

  /// The link kept by [DLNLinkOptions.hold] (SDK-89), or `null`: the next one
  /// [releasePendingLink] delivers. The latest link of each kind is kept (one deferred, one
  /// direct); when both are held this is the deferred one, and the direct one follows it.
  static DLNLink? get pendingLink => _pendingDeferred ?? _pendingDirect;

  /// Every held link (SDK-89), deferred first: at most one deferred and one direct. Empty when
  /// nothing is held. [pendingLink] is the first of them.
  static List<DLNLink> get pendingLinks =>
      List.unmodifiable([_pendingDeferred, _pendingDirect].whereType<DLNLink>());

  /// Ends the hold and delivers the held links, deferred first, to [links] (SDK-89). Later
  /// links are delivered straight away until [listen] is called again with `hold: true`.
  static void releasePendingLink() {
    _holding = false;
    final held = [_pendingDeferred, _pendingDirect];
    _pendingDeferred = null;
    _pendingDirect = null;
    for (final link in held) {
      if (link != null) _deliver(link);
    }
  }

  /// Drops the held links without delivering them (SDK-89). The hold stays on.
  static void clearPendingLink() {
    _pendingDeferred = null;
    _pendingDirect = null;
  }

  /// Parses [url] with the native rules and looks it up with `GET /api/v1/sdk/resolve`
  /// (SDK-90), filling `deeplinkId`, `targetUrl`, `campaignId` and `metadata` on a 200.
  ///
  /// Resolves `null` when [url] isn't a link on the app's domains or one of its schemes. A
  /// 404, a timeout (the configured timeout), any other failure, or no successful
  /// [initialize] gives the link unresolved; a scheme link is never resolved. Never throws.
  static Future<DLNLink?> resolveLink(String url) async {
    final link = await _directLink(url);
    return link == null ? null : _resolve(link);
  }

  static Future<Object?> _onNativeCall(MethodCall call) async {
    if (call.method == 'onLinkUrl') {
      final url = call.arguments;
      if (url is String) _enqueue(() => _handleDirect(url));
      return null;
    }
    throw MissingPluginException('DeepLinkNow: unknown method ${call.method}');
  }

  /// The URLs the platform side buffered (the launch URL first); from now on it sends each new
  /// one with `onLinkUrl`.
  static Future<List<String>> _startLinks() async {
    try {
      final raw = await channel.invokeMethod<List<Object?>>('startLinks');
      return [...?raw?.whereType<String>()];
    } catch (e) {
      _warn('startLinks', e);
      return const [];
    }
  }

  /// Links are handled one at a time, in arrival order.
  static void _enqueue(Future<void> Function() task) {
    _linkQueue = _linkQueue.then((_) => task()).then<void>(
          (_) {},
          onError: (Object e) => _warn('links', e),
        );
  }

  static Future<void> _handleDirect(String url) async {
    final now = clock();
    final last = _lastDirectAt;
    if (url == _lastDirectUrl && last != null && now.difference(last) < _replayWindow) return;
    _lastDirectUrl = url;
    _lastDirectAt = now;
    final link = await _directLink(url);
    if (link == null) return;
    _deliver(_linkOptions.resolve ? await _resolve(link) : link);
  }

  static Future<DLNLink?> _directLink(String url) async {
    final scheme = schemeOf(url.trim());
    if (scheme == null) return null;
    if (scheme == 'http' || scheme == 'https') {
      final parsed = await parseDeepLink(url);
      if (parsed == null) return null;
      final source = defaultTargetPlatform == TargetPlatform.android
          ? DLNLinkSource.appLink
          : DLNLinkSource.universalLink;
      return DLNLink.direct(parsed, source);
    }
    return _schemeLink(url.trim(), scheme);
  }

  /// SDK-87 custom schemes. The native plugin parses the path and query (SDK-30…37) on the
  /// app's primary domain, or on a provisional link host before a successful [initialize], so
  /// Dart has no query parser or host rule (FLT-01); `url` stays the scheme URL. No network: a
  /// scheme open is delivered without a successful initialize (FLT-34), like the native SDKs and
  /// React Native.
  static Future<DLNLink?> _schemeLink(String url, String scheme) async {
    if (systemSchemes.contains(scheme) || !await _isAppScheme(scheme, url)) return null;
    ParsedDeepLink? parsed;
    try {
      final raw = await channel.invokeMethod<Object?>('parseSchemePath', {
        'path': schemePathOf(url),
        'domain': _appInfo?.primaryDomain,
      });
      parsed = raw == null ? null : ParsedDeepLink.fromMap(raw);
    } catch (e) {
      _warn('parseSchemePath', e);
    }
    if (parsed == null) return null;
    return DLNLink(
      type: DLNLinkType.direct,
      path: parsed.path,
      queryParams: parsed.queryParams,
      fullPath: parsed.fullPath,
      url: stripDlnFragment(url),
      source: DLNLinkSource.scheme,
      confidenceScore: 100,
      matchQuality: MatchQuality.high,
    );
  }

  static Future<bool> _isAppScheme(String scheme, String url) async {
    final listed = _linkOptions.schemes.map((s) => s.toLowerCase()).toSet();
    if (listed.isNotEmpty) return listed.contains(scheme);
    try {
      // The URL lets Android match intent filters that also set a host or path (FLT-33).
      return await channel.invokeMethod<bool>('isAppScheme', {'scheme': scheme, 'url': url}) ??
          false;
    } catch (e) {
      _warn('isAppScheme', e);
      return false;
    }
  }

  static void _deliver(DLNLink link) {
    final deferred = link.type == DLNLinkType.deferred;
    if (_holding) {
      deferred ? _pendingDeferred = link : _pendingDirect = link;
    } else if (_links.hasListener) {
      _links.add(link);
    } else {
      deferred ? _undeliveredDeferred = link : _undeliveredDirect = link;
    }
  }

  static void _replayUndelivered() {
    final waiting = [_undeliveredDeferred, _undeliveredDirect];
    _undeliveredDeferred = null;
    _undeliveredDirect = null;
    for (final link in waiting) {
      if (link != null) scheduleMicrotask(() => _deliver(link));
    }
  }

  static Future<DLNLink> _resolve(DLNLink link) async {
    final config = _resolveConfig;
    // Scheme opens are never resolved (SDK-87, SDK-90).
    if (config == null || link.source == DLNLinkSource.scheme) return link;
    try {
      final response = await httpGet(
        resolveUri(config.baseUrl, link.fullPath),
        {'x-api-key': config.apiKey, 'accept': 'application/json'},
        config.timeout,
      ).timeout(config.timeout);
      if (response.status == 404) return link;
      if (response.status != 200) {
        throw DLNError(
          _statusCode(response.status),
          message: 'HTTP ${response.status}',
          status: response.status,
        );
      }
      final body = jsonDecode(response.body);
      final deeplink = body is Map ? body['deeplink'] : null;
      if (deeplink is! Map || deeplink['id'] is! String) {
        throw const DLNShapeException('resolve response has no deeplink');
      }
      final targetUrl = deeplink['target_url'];
      final campaignId = deeplink['campaign_id'];
      final metadata = deeplink['metadata'];
      return link.withResolved(
        deeplinkId: deeplink['id'] as String,
        targetUrl: targetUrl is String ? targetUrl : null,
        campaignId: campaignId is String ? campaignId : null,
        metadata: metadata is Map ? Map<String, Object?>.from(metadata) : null,
      );
    } on TimeoutException {
      _warn('resolveLink', const DLNError(DLNErrorCode.network, message: 'timed out'));
      return link;
    } catch (e) {
      _warn('resolveLink', e);
      return link;
    }
  }

  static DLNErrorCode _statusCode(int status) => switch (status) {
        400 => DLNErrorCode.badRequest,
        401 => DLNErrorCode.invalidApiKey,
        403 => DLNErrorCode.accountInactive,
        429 => DLNErrorCode.rateLimited,
        >= 500 => DLNErrorCode.server,
        _ => DLNErrorCode.invalidResponse,
      };

  /// Clears the Dart-side state (not the native SDKs).
  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
    _appInfo = null;
    _lastError = null;
    _lastErrorKind = null;
    logSink = _defaultLog;
    channel.setMethodCallHandler(null);
    unawaited(_links.close());
    _links = _newLinksController();
    _linkOptions = const DLNLinkOptions();
    _listening = false;
    _holding = false;
    _deferredRunning = false;
    _deferredDone = false;
    _pendingDeferred = null;
    _pendingDirect = null;
    _undeliveredDeferred = null;
    _undeliveredDirect = null;
    _linkQueue = Future<void>.value();
    _initFinished = Completer<void>();
    _resolveConfig = null;
    _lastDirectUrl = null;
    _lastDirectAt = null;
    httpGet = platformHttpGet;
    clock = DateTime.now;
  }

  static void _succeeded(_CallKind kind) {
    if (_lastErrorKind == kind) {
      _lastError = null;
      _lastErrorKind = null;
    }
  }

  static void _failed(_CallKind kind, String method, Object error) {
    final dlnError = _toError(error);
    _lastError = dlnError;
    _lastErrorKind = kind;
    logSink('[DeepLinkNow] $method failed: $dlnError');
  }

  static void _warn(String method, Object error) {
    logSink('[DeepLinkNow] $method failed: ${_toError(error)}');
  }

  /// Maps anything the channel or the decoders throw to a [DLNError] (SDK-55).
  static DLNError _toError(Object error) {
    if (error is DLNError) return error;
    if (error is PlatformException) {
      final details = error.details;
      final info = details is Map ? details : const <Object?, Object?>{};
      final status = info['status'];
      final serverMessage = info['serverMessage'];
      final causeCode = info['causeCode'];
      final causeMessage = info['causeMessage'];
      return DLNError(
        DLNErrorCode.fromCode(error.code),
        message: error.message,
        status: status is num ? status.toInt() : null,
        serverMessage: serverMessage is String ? serverMessage : null,
        cause: causeCode is String
            ? DLNError(
                DLNErrorCode.fromCode(causeCode),
                message: causeMessage is String ? causeMessage : null,
              )
            : null,
      );
    }
    if (error is MissingPluginException) {
      return const DLNError(
        DLNErrorCode.notInitialized,
        message: 'The DeepLinkNow native plugin is not available. It supports iOS and '
            'Android; after adding the package, stop the app and rebuild it (hot restart '
            'does not load native code).',
      );
    }
    if (error is DLNShapeException) {
      return DLNError(DLNErrorCode.invalidResponse, message: error.message);
    }
    return DLNError(DLNErrorCode.invalidResponse, message: error.toString());
  }
}
