// Typed results of the DeepLinkNow plugin. Each class is built from the plain map the native
// plugin sends over the method channel; the shapes are the shared SDK contract (SDK-15, SDK-20).

/// Server confidence thresholds (SDK-16): HIGH ≥ 75, MEDIUM ≥ 50, LOW ≥ 30.
abstract final class ConfidenceThresholds {
  /// Lowest score labelled HIGH.
  static const int high = 75;

  /// Lowest score labelled MEDIUM.
  static const int medium = 50;

  /// Lowest score the server returns at all (LOW).
  static const int low = 30;
}

/// Thrown internally when a native payload does not have the documented shape. The public API
/// reports it as `DLNErrorCode.invalidResponse`.
class DLNShapeException implements Exception {
  /// Creates the exception.
  const DLNShapeException(this.message);

  /// What was wrong.
  final String message;

  @override
  String toString() => 'DLNShapeException: $message';
}

Map<String, Object?> _map(Object? value, String what) {
  if (value is Map) {
    return value.map((key, v) => MapEntry(key.toString(), v));
  }
  throw DLNShapeException('$what is not a map');
}

Map<String, Object?>? _optMap(Object? value, String what) =>
    value == null ? null : _map(value, what);

String _str(Map<String, Object?> m, String key) {
  final value = m[key];
  if (value is String) return value;
  throw DLNShapeException('"$key" is not a string');
}

String? _optStr(Map<String, Object?> m, String key) {
  final value = m[key];
  if (value == null || value is String) return value as String?;
  throw DLNShapeException('"$key" is not a string');
}

double _num(Map<String, Object?> m, String key) {
  final value = m[key];
  if (value is num) return value.toDouble();
  throw DLNShapeException('"$key" is not a number');
}

double? _optNum(Map<String, Object?> m, String key) {
  final value = m[key];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw DLNShapeException('"$key" is not a number');
}

bool _bool(Map<String, Object?> m, String key) {
  final value = m[key];
  if (value is bool) return value;
  throw DLNShapeException('"$key" is not a bool');
}

/// Deep-copies a channel value into plain Dart types (`Map<String, Object?>`, `List<Object?>`).
Object? _plain(Object? value) {
  if (value is Map) {
    return value.map((key, v) => MapEntry(key.toString(), _plain(v)));
  }
  if (value is List) return value.map(_plain).toList();
  return value;
}

Map<String, Object?>? _optPlainMap(Object? value, String what) {
  final m = _optMap(value, what);
  return m == null ? null : _plain(m)! as Map<String, Object?>;
}

/// One query parameter value with the shared FLOW-53 semantics (SDK-35): a single string, a
/// bare flag (`?k` or `?k=`), or a list of strings for a repeated key.
///
/// The same three cases as Swift `DLNQueryValue`, Kotlin `QueryValue` and TS
/// `string | true | string[]`.
sealed class QueryValue {
  const QueryValue();

  /// Decodes the channel value (`String`, `true` or `List<String>`).
  factory QueryValue.fromChannel(Object? value) {
    if (value is String) return SingleQueryValue(value);
    if (value == true) return const FlagQueryValue();
    if (value is List && value.every((e) => e is String)) {
      return MultipleQueryValue(List<String>.unmodifiable(value.cast<String>()));
    }
    throw const DLNShapeException('query value is not a string, true or a string list');
  }

  /// The value as one string: the string, `''` for a flag, the first value of a list.
  String get stringValue;

  /// Every value: one for a string, none for a flag, all for a list.
  List<String> get stringValues;

  /// The plain value: `String`, `true` or `List<String>` (the React Native shape).
  Object get rawValue;
}

/// A key that occurs once with a value (`?ref=newsletter`).
final class SingleQueryValue extends QueryValue {
  /// Creates the value.
  const SingleQueryValue(this.value);

  /// The decoded value.
  final String value;

  @override
  String get stringValue => value;

  @override
  List<String> get stringValues => [value];

  @override
  Object get rawValue => value;

  @override
  bool operator ==(Object other) => other is SingleQueryValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A key with a single empty value (`?debug` or `?debug=`).
final class FlagQueryValue extends QueryValue {
  /// Creates the flag.
  const FlagQueryValue();

  @override
  String get stringValue => '';

  @override
  List<String> get stringValues => const [];

  @override
  Object get rawValue => true;

  @override
  bool operator ==(Object other) => other is FlagQueryValue;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'true';
}

/// A repeated key (`?tag=a&tag=b`), values in order.
final class MultipleQueryValue extends QueryValue {
  /// Creates the list value.
  const MultipleQueryValue(this.values);

  /// The decoded values in order.
  final List<String> values;

  @override
  String get stringValue => values.isEmpty ? '' : values.first;

  @override
  List<String> get stringValues => values;

  @override
  Object get rawValue => values;

  @override
  bool operator ==(Object other) =>
      other is MultipleQueryValue &&
      other.values.length == values.length &&
      Iterable<int>.generate(values.length).every((i) => other.values[i] == values[i]);

  @override
  int get hashCode => Object.hashAll(values);

  @override
  String toString() => values.toString();
}

Map<String, QueryValue> _query(Object? value, String what) {
  final m = _map(value, what);
  return Map<String, QueryValue>.unmodifiable(
    m.map((key, v) => MapEntry(key, QueryValue.fromChannel(v))),
  );
}

/// Where a deferred deep link came from.
enum DeferredDeepLinkSource {
  /// Android Play Install Referrer (exact).
  referrer('referrer'),

  /// iOS pasteboard handoff (exact).
  clipboard('clipboard'),

  /// Fingerprint matching (scored, best effort).
  fingerprint('fingerprint');

  const DeferredDeepLinkSource(this.value);

  /// The wire value.
  final String value;

  /// Parses the wire value.
  static DeferredDeepLinkSource parse(String value) {
    for (final source in DeferredDeepLinkSource.values) {
      if (source.value == value) return source;
    }
    throw DLNShapeException('unknown source "$value"');
  }
}

/// The server's match label (SDK-16).
enum MatchQuality {
  /// Score ≥ 75.
  high('HIGH'),

  /// Score 50–74.
  medium('MEDIUM'),

  /// Score 30–49.
  low('LOW');

  const MatchQuality(this.value);

  /// The wire value (`HIGH`, `MEDIUM`, `LOW`).
  final String value;

  /// Parses the wire value (case-insensitive).
  static MatchQuality parse(String value) {
    final upper = value.toUpperCase();
    for (final quality in MatchQuality.values) {
      if (quality.value == upper) return quality;
    }
    throw DLNShapeException('unknown match quality "$value"');
  }
}

/// Optional configuration for `DeepLinkNow.initialize` (SDK-01).
class DLNConfig {
  /// Creates a configuration. Unset values use the native defaults: logs off,
  /// `https://deeplinknow.com`, 10 000 ms per request, 2 retries.
  const DLNConfig({
    this.enableLogs = false,
    this.baseUrl,
    this.timeoutMs,
    this.retryAttempts,
  });

  /// Debug logs from the native SDKs (`[DeepLinkNow]` on iOS, tag `DLN` on Android).
  final bool enableLogs;

  /// API base URL; `null` uses `https://deeplinknow.com`.
  final String? baseUrl;

  /// Timeout per request in milliseconds; `null` uses 10 000.
  final int? timeoutMs;

  /// Retries for transient failures; `null` uses 2.
  final int? retryAttempts;

  /// The channel payload. Unset values are omitted so the native defaults apply.
  Map<String, Object?> toMap() => {
        'enableLogs': enableLogs,
        if (baseUrl != null) 'baseUrl': baseUrl,
        if (timeoutMs != null) 'timeoutMs': timeoutMs,
        if (retryAttempts != null) 'retryAttempts': retryAttempts,
      };
}

/// What `initialize` learned about the app (SDK-03).
class DLNAppInfo {
  /// Creates the info.
  const DLNAppInfo({
    required this.id,
    required this.alias,
    required this.domains,
    required this.primaryDomain,
    required this.accountStatus,
    this.name,
    this.creditsRemaining,
  });

  /// Decodes the channel map.
  factory DLNAppInfo.fromMap(Object? value) {
    final m = _map(value, 'app info');
    final domains = m['domains'];
    if (domains is! List || domains.any((d) => d is! String)) {
      throw const DLNShapeException('"domains" is not a string list');
    }
    return DLNAppInfo(
      id: _str(m, 'id'),
      alias: _str(m, 'alias'),
      name: _optStr(m, 'name'),
      domains: List<String>.unmodifiable(domains.cast<String>()),
      primaryDomain:
          _optStr(m, 'primaryDomain') ?? (domains.isEmpty ? '' : domains.first as String),
      accountStatus: _optStr(m, 'accountStatus') ?? 'active',
      creditsRemaining: _optNum(m, 'creditsRemaining')?.toInt(),
    );
  }

  /// App id.
  final String id;

  /// App alias (`{alias}.deeplinknow.com`).
  final String alias;

  /// App name, when the server sends one.
  final String? name;

  /// Link domains: `{alias}.deeplinknow.com` plus every verified custom domain, lowercased.
  final List<String> domains;

  /// The domain used to build `url` (the first verified custom domain, else the alias domain).
  final String primaryDomain;

  /// Account status (`active`, …).
  final String accountStatus;

  /// Credits remaining, when known.
  final int? creditsRemaining;
}

/// A link parsed by `DeepLinkNow.parseDeepLink` (SDK-30).
class ParsedDeepLink {
  /// Creates the parsed link.
  const ParsedDeepLink({
    required this.path,
    required this.queryParams,
    required this.fullPath,
    required this.url,
  });

  /// Decodes the channel map.
  factory ParsedDeepLink.fromMap(Object? value) {
    final m = _map(value, 'parsed link');
    return ParsedDeepLink(
      path: _str(m, 'path'),
      queryParams: _query(m['queryParams'], 'queryParams'),
      fullPath: _str(m, 'fullPath'),
      url: _str(m, 'url'),
    );
  }

  /// `fullPath` up to the first `?`, not decoded, always starting with `/` (SDK-34).
  final String path;

  /// Query parameters with FLOW-53 semantics (SDK-35).
  final Map<String, QueryValue> queryParams;

  /// `/` + path + `?query` exactly as in the URL (SDK-36).
  final String fullPath;

  /// The absolute URL.
  final String url;
}

/// The deferred deep link returned by `DeepLinkNow.checkDeferredDeepLink` (SDK-15).
class DeferredDeepLink {
  /// Creates the link.
  const DeferredDeepLink({
    required this.path,
    required this.queryParams,
    required this.fullPath,
    required this.url,
    required this.source,
    required this.confidenceScore,
    required this.matchQuality,
    this.deeplinkId,
    this.targetUrl,
    this.campaignId,
    this.metadata,
    this.matchedAt,
    this.expiresAt,
    this.matchDetails,
  });

  /// Decodes the channel map.
  factory DeferredDeepLink.fromMap(Object? value) {
    final m = _map(value, 'deferred deep link');
    final details = m['matchDetails'];
    return DeferredDeepLink(
      path: _str(m, 'path'),
      queryParams: _query(m['queryParams'], 'queryParams'),
      fullPath: _str(m, 'fullPath'),
      url: _str(m, 'url'),
      source: DeferredDeepLinkSource.parse(_str(m, 'source')),
      confidenceScore: _num(m, 'confidenceScore'),
      matchQuality: MatchQuality.parse(_str(m, 'matchQuality')),
      deeplinkId: _optStr(m, 'deeplinkId'),
      targetUrl: _optStr(m, 'targetUrl'),
      campaignId: _optStr(m, 'campaignId'),
      metadata: _optPlainMap(m['metadata'], 'metadata'),
      matchedAt: _optStr(m, 'matchedAt'),
      expiresAt: _optStr(m, 'expiresAt'),
      matchDetails: details == null ? null : MatchDetails.fromMap(details),
    );
  }

  /// `fullPath` up to the first `?`, not decoded (e.g. `/products/123`).
  final String path;

  /// Query parameters with FLOW-53 semantics.
  final Map<String, QueryValue> queryParams;

  /// `/` + path + `?query` exactly as received.
  final String fullPath;

  /// Absolute https URL of the link (SDK-18).
  final String url;

  /// Which signal produced the answer.
  final DeferredDeepLinkSource source;

  /// 0–100: the server score for `fingerprint`, 100 for `referrer` and `clipboard`.
  final double confidenceScore;

  /// The server label for `fingerprint`, HIGH for `referrer` and `clipboard`.
  final MatchQuality matchQuality;

  /// `deeplink.id` (server sources only).
  final String? deeplinkId;

  /// `deeplink.target_url`, raw (server sources only).
  final String? targetUrl;

  /// `deeplink.campaign_id`.
  final String? campaignId;

  /// `deeplink.metadata`.
  final Map<String, Object?>? metadata;

  /// ISO-8601 match time from the server.
  final String? matchedAt;

  /// ISO-8601 end of the claim window (1 hour).
  final String? expiresAt;

  /// The score breakdown (`fingerprint` only).
  final MatchDetails? matchDetails;
}

/// `match_details`: the score breakdown of a fingerprint candidate.
class MatchDetails {
  /// Creates the breakdown.
  const MatchDetails({
    required this.ipMatch,
    required this.deviceMatch,
    required this.timeProximity,
    required this.localeMatch,
  });

  /// Decodes the snake_case wire map.
  factory MatchDetails.fromMap(Object? value) {
    final m = _map(value, 'match_details');
    final ip = _map(m['ip_match'], 'ip_match');
    final device = _map(m['device_match'], 'device_match');
    final deviceComponents = _map(device['components'], 'device_match.components');
    final time = _map(m['time_proximity'], 'time_proximity');
    final locale = _map(m['locale_match'], 'locale_match');
    final localeComponents = _map(locale['components'], 'locale_match.components');
    return MatchDetails(
      ipMatch: IpMatch(matched: _bool(ip, 'matched'), score: _num(ip, 'score')),
      deviceMatch: DeviceMatch(
        matched: _bool(device, 'matched'),
        score: _num(device, 'score'),
        platform: _bool(deviceComponents, 'platform'),
        osVersion: _bool(deviceComponents, 'os_version'),
        deviceModel: _bool(deviceComponents, 'device_model'),
        hardwareFingerprint: _bool(deviceComponents, 'hardware_fingerprint'),
      ),
      timeProximity: TimeProximity(
        score: _num(time, 'score'),
        timeDifferenceMinutes: _num(time, 'time_difference_minutes'),
      ),
      localeMatch: LocaleMatch(
        matched: _bool(locale, 'matched'),
        score: _num(locale, 'score'),
        language: _bool(localeComponents, 'language'),
        timezone: _bool(localeComponents, 'timezone'),
      ),
    );
  }

  /// IP component (weight 40).
  final IpMatch ipMatch;

  /// Device component (weight 30).
  final DeviceMatch deviceMatch;

  /// Time component (weight 20).
  final TimeProximity timeProximity;

  /// Locale component (weight 10).
  final LocaleMatch localeMatch;
}

/// `match_details.ip_match`.
class IpMatch {
  /// Creates the component.
  const IpMatch({required this.matched, required this.score});

  /// Whether the IP matched.
  final bool matched;

  /// Points awarded.
  final double score;
}

/// `match_details.device_match`.
class DeviceMatch {
  /// Creates the component.
  const DeviceMatch({
    required this.matched,
    required this.score,
    required this.platform,
    required this.osVersion,
    required this.deviceModel,
    required this.hardwareFingerprint,
  });

  /// Whether the device matched.
  final bool matched;

  /// Points awarded.
  final double score;

  /// `components.platform`.
  final bool platform;

  /// `components.os_version`.
  final bool osVersion;

  /// `components.device_model`.
  final bool deviceModel;

  /// `components.hardware_fingerprint`.
  final bool hardwareFingerprint;
}

/// `match_details.time_proximity`.
class TimeProximity {
  /// Creates the component.
  const TimeProximity({required this.score, required this.timeDifferenceMinutes});

  /// Points awarded.
  final double score;

  /// Minutes between the click and this request.
  final double timeDifferenceMinutes;
}

/// `match_details.locale_match`.
class LocaleMatch {
  /// Creates the component.
  const LocaleMatch({
    required this.matched,
    required this.score,
    required this.language,
    required this.timezone,
  });

  /// Whether the locale matched.
  final bool matched;

  /// Points awarded.
  final double score;

  /// `components.language`.
  final bool language;

  /// `components.timezone`.
  final bool timezone;
}

/// The `deeplink` of a `/sdk/match` candidate (SDK-20).
class DeeplinkMatch {
  /// Creates the deeplink.
  const DeeplinkMatch({
    required this.id,
    required this.targetUrl,
    required this.metadata,
    this.campaignId,
    this.matchedAt,
    this.expiresAt,
    this.queryParams,
    this.fullPath,
  });

  /// Decodes the snake_case wire map.
  factory DeeplinkMatch.fromMap(Object? value) {
    final m = _map(value, 'deeplink');
    final query = m['query_params'];
    return DeeplinkMatch(
      id: _str(m, 'id'),
      targetUrl: _str(m, 'target_url'),
      metadata: _optPlainMap(m['metadata'], 'metadata') ?? const {},
      campaignId: _optStr(m, 'campaign_id'),
      matchedAt: _optStr(m, 'matched_at'),
      expiresAt: _optStr(m, 'expires_at'),
      queryParams: query == null ? null : _query(query, 'query_params'),
      fullPath: _optStr(m, 'full_path'),
    );
  }

  /// `id`.
  final String id;

  /// `target_url`, raw.
  final String targetUrl;

  /// `metadata` (`{}` when the link has none).
  final Map<String, Object?> metadata;

  /// `campaign_id`.
  final String? campaignId;

  /// `matched_at`.
  final String? matchedAt;

  /// `expires_at`.
  final String? expiresAt;

  /// `query_params` (FLOW-53), when the server sent them.
  final Map<String, QueryValue>? queryParams;

  /// `full_path`, when the server sent it.
  final String? fullPath;
}

/// One fingerprint candidate from `/sdk/match`.
class Match {
  /// Creates the candidate.
  const Match({
    required this.confidenceScore,
    required this.matchQuality,
    required this.matchDetails,
    this.deeplink,
  });

  /// Decodes the snake_case wire map.
  factory Match.fromMap(Object? value) {
    final m = _map(value, 'match');
    final deeplink = m['deeplink'];
    return Match(
      confidenceScore: _num(m, 'confidence_score'),
      matchQuality: MatchQuality.parse(_str(m, 'match_quality')),
      matchDetails: MatchDetails.fromMap(m['match_details']),
      deeplink: deeplink == null ? null : DeeplinkMatch.fromMap(deeplink),
    );
  }

  /// `confidence_score` 0–100.
  final double confidenceScore;

  /// `match_quality`.
  final MatchQuality matchQuality;

  /// `match_details`.
  final MatchDetails matchDetails;

  /// `deeplink`, or `null` for a candidate without a link.
  final DeeplinkMatch? deeplink;
}

/// The full `/sdk/match` response (SDK-20), in server order.
class MatchResponse {
  /// Creates the response.
  const MatchResponse({required this.matches, required this.ttlSeconds});

  /// Decodes the snake_case wire map.
  factory MatchResponse.fromMap(Object? value) {
    final m = _map(value, 'match response');
    final matches = m['matches'];
    if (matches is! List) throw const DLNShapeException('"matches" is not a list');
    return MatchResponse(
      matches: List<Match>.unmodifiable(matches.map(Match.fromMap)),
      ttlSeconds: _num(m, 'ttl_seconds').toInt(),
    );
  }

  /// Every candidate, in the order the server returned them (highest score first).
  final List<Match> matches;

  /// `ttl_seconds`.
  final int ttlSeconds;
}

/// The deep link resolved from the Android Install Referrer.
class ReferrerDeeplink {
  /// Creates the link.
  const ReferrerDeeplink({
    required this.id,
    required this.targetUrl,
    required this.metadata,
    this.campaignId,
    this.matchedAt,
    this.expiresAt,
    this.queryParams,
    this.fullPath,
  });

  /// Decodes the channel map (camelCase).
  factory ReferrerDeeplink.fromMap(Object? value) {
    final m = _map(value, 'referrer deeplink');
    final query = m['queryParams'];
    return ReferrerDeeplink(
      id: _str(m, 'id'),
      targetUrl: _str(m, 'targetUrl'),
      metadata: _optPlainMap(m['metadata'], 'metadata') ?? const {},
      campaignId: _optStr(m, 'campaignId'),
      matchedAt: _optStr(m, 'matchedAt'),
      expiresAt: _optStr(m, 'expiresAt'),
      queryParams: query == null ? null : _query(query, 'queryParams'),
      fullPath: _optStr(m, 'fullPath'),
    );
  }

  /// Deeplink id.
  final String id;

  /// Raw target URL.
  final String targetUrl;

  /// Metadata.
  final Map<String, Object?> metadata;

  /// Campaign id.
  final String? campaignId;

  /// Match time.
  final String? matchedAt;

  /// End of the claim window.
  final String? expiresAt;

  /// Query parameters, when the server sent them.
  final Map<String, QueryValue>? queryParams;

  /// Full path, when the server sent it.
  final String? fullPath;
}

/// The raw Android Install Referrer result (Android only).
class ReferrerData {
  /// Creates the data.
  const ReferrerData({
    required this.referrerString,
    required this.processedAt,
    this.fpId,
    this.deeplinkId,
    this.deeplinkData,
  });

  /// Decodes the channel map.
  factory ReferrerData.fromMap(Object? value) {
    final m = _map(value, 'referrer data');
    final data = m['deeplinkData'];
    return ReferrerData(
      referrerString: _str(m, 'referrerString'),
      processedAt: DateTime.fromMillisecondsSinceEpoch(
        _num(m, 'processedAt').toInt(),
        isUtc: true,
      ),
      fpId: _optStr(m, 'fpId'),
      deeplinkId: _optStr(m, 'deeplinkId'),
      deeplinkData: data == null ? null : ReferrerDeeplink.fromMap(data),
    );
  }

  /// The referrer string from Google Play.
  final String referrerString;

  /// When the SDK processed it.
  final DateTime processedAt;

  /// `fp_id` from the referrer, if present.
  final String? fpId;

  /// `deeplink_id` from the referrer, if present.
  final String? deeplinkId;

  /// The looked-up link, if any.
  final ReferrerDeeplink? deeplinkData;
}
