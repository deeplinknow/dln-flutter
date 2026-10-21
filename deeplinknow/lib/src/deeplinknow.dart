import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'errors.dart';
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
abstract final class DeepLinkNow {
  /// Plugin version. iOS, Android, React Native and Flutter share major.minor (SDK-84).
  static const String sdkVersion = '1.3.0';

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
      _succeeded(_CallKind.initialize);
      return info;
    } catch (e) {
      _initialized = false;
      _appInfo = null;
      _failed(_CallKind.initialize, 'initialize', e);
      return null;
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
    try {
      final raw = await channel.invokeMethod<Object?>('checkDeferredDeepLink', {
        'minConfidence': minConfidence,
        'useClipboard': useClipboard,
        'force': force,
      });
      final link = raw == null ? null : DeferredDeepLink.fromMap(raw);
      _succeeded(_CallKind.check);
      return link;
    } catch (e) {
      _failed(_CallKind.check, 'checkDeferredDeepLink', e);
      return null;
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

  /// Clears the Dart-side state (not the native SDKs).
  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
    _appInfo = null;
    _lastError = null;
    _lastErrorKind = null;
    logSink = _defaultLog;
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
