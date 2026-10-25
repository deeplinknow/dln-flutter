// One link object for every open (SDK-86…92): `DLNLink`, its options, and the `dln` fragment
// rule.

import 'types.dart';

/// How a [DLNLink] reached the app (SDK-86).
enum DLNLinkType {
  /// Delivered by the first-launch chain after an install.
  deferred('deferred'),

  /// The OS opened the installed app with this URL (a Universal Link or an App Link).
  direct('direct');

  const DLNLinkType(this.value);

  /// The shared wire value (`deferred`, `direct`).
  final String value;
}

/// Where a [DLNLink] came from (SDK-86). The three deferred sources are the
/// [DeferredDeepLinkSource] values; the others describe a direct open.
/// [DeferredDeepLinkSource] keeps its three values, so existing exhaustive switches still compile.
enum DLNLinkSource {
  /// Android Play Install Referrer (deferred, exact).
  referrer('referrer'),

  /// iOS pasteboard handoff (deferred, exact).
  clipboard('clipboard'),

  /// Fingerprint matching (deferred, scored).
  fingerprint('fingerprint'),

  /// A Universal Link on one of the app's link domains opened the installed iOS app.
  universalLink('universalLink'),

  /// An App Link on one of the app's link domains opened the installed Android app.
  appLink('appLink'),

  /// The app's custom URL scheme (`myapp://products/123`), SDK-87. Never resolved (SDK-90).
  scheme('scheme');

  const DLNLinkSource(this.value);

  /// The shared wire value.
  final String value;

  /// The [DLNLinkSource] for a deferred source.
  static DLNLinkSource fromDeferred(DeferredDeepLinkSource source) => switch (source) {
        DeferredDeepLinkSource.referrer => DLNLinkSource.referrer,
        DeferredDeepLinkSource.clipboard => DLNLinkSource.clipboard,
        DeferredDeepLinkSource.fingerprint => DLNLinkSource.fingerprint,
      };
}

/// Options for `DeepLinkNow.listen` (SDK-86, SDK-89, SDK-90).
class DLNLinkOptions {
  /// Creates the options. The defaults deliver every link straight to `DeepLinkNow.links`.
  const DLNLinkOptions({
    this.minConfidence,
    this.useClipboard = true,
    this.force = false,
    this.hold = false,
    this.resolve = false,
    this.schemes = const [],
  });

  /// Passed to the deferred check (`checkDeferredDeepLink(minConfidence:)`); `null` is no filter.
  final double? minConfidence;

  /// Passed to the deferred check (iOS only, default `true`).
  final bool useClipboard;

  /// Passed to the deferred check: ignore the first-launch flag (testing).
  final bool force;

  /// Keep links in `DeepLinkNow.pendingLink` instead of delivering them, until the app calls
  /// `releasePendingLink()` or `clearPendingLink()` (SDK-89). For a sign-in gate.
  final bool hold;

  /// Look up each direct open with `GET /api/v1/sdk/resolve` before delivering it (SDK-90), to
  /// fill `deeplinkId`, `targetUrl`, `campaignId` and `metadata` (links imported from Firebase).
  /// Adds a network call to every direct open, bounded by the configured timeout.
  final bool resolve;

  /// The app's custom URL schemes (`['myapp']`), for `source: scheme` opens (SDK-87). When
  /// empty, the schemes the app declares count: iOS `CFBundleURLSchemes` in Info.plist,
  /// Android a VIEW intent filter in the manifest. System schemes (`mailto`, `tel`, …) never do.
  final List<String> schemes;
}

/// Schemes that are never the app's own (SDK-87).
const Set<String> systemSchemes = {
  'http', 'https', 'mailto', 'tel', 'telprompt', 'sms', 'facetime', 'facetime-audio', //
  'content', 'file', 'intent', 'itms', 'itms-apps', 'itms-appss', 'market', 'data', //
  'javascript', 'about', 'geo', 'maps', 'ftp', 'ws', 'wss', 'blob',
};

/// The lowercased scheme of [url] (the part before the first `:`), or `null` when it has none.
String? schemeOf(String url) {
  final colon = url.indexOf(':');
  if (colon <= 0) return null;
  final scheme = url.substring(0, colon).toLowerCase();
  final valid = RegExp(r'^[a-z][a-z0-9+.\-]*$').hasMatch(scheme);
  return valid ? scheme : null;
}

/// SDK-87: `myapp://products/123?x=1` → `/products/123?x=1` (the host is the first path
/// segment). The fragment is kept here; the native parse drops it (SDK-34).
String schemePathOf(String url) {
  var rest = url.substring(url.indexOf(':') + 1);
  if (rest.startsWith('//')) rest = rest.substring(2);
  if (!rest.startsWith('/')) rest = '/$rest';
  return rest;
}

/// The one link object the app receives for every open, deferred or direct (SDK-86).
///
/// Every [DeferredDeepLink] field, with the same names and meanings, plus [type]. A direct open
/// has `confidenceScore` 100 and `matchQuality` HIGH, and the server fields only when it was
/// resolved (SDK-90).
class DLNLink {
  /// Creates the link.
  const DLNLink({
    required this.type,
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

  /// A deferred link from `checkDeferredDeepLink` as a [DLNLink] (`type` deferred).
  factory DLNLink.fromDeferred(DeferredDeepLink link) => DLNLink(
        type: DLNLinkType.deferred,
        path: link.path,
        queryParams: link.queryParams,
        fullPath: link.fullPath,
        url: link.url,
        source: DLNLinkSource.fromDeferred(link.source),
        confidenceScore: link.confidenceScore,
        matchQuality: link.matchQuality,
        deeplinkId: link.deeplinkId,
        targetUrl: link.targetUrl,
        campaignId: link.campaignId,
        metadata: link.metadata,
        matchedAt: link.matchedAt,
        expiresAt: link.expiresAt,
        matchDetails: link.matchDetails,
      );

  /// A direct open parsed with the native rules (`type` direct, score 100, HIGH).
  factory DLNLink.direct(ParsedDeepLink parsed, DLNLinkSource source) => DLNLink(
        type: DLNLinkType.direct,
        path: parsed.path,
        queryParams: parsed.queryParams,
        fullPath: parsed.fullPath,
        url: parsed.url,
        source: source,
        confidenceScore: 100,
        matchQuality: MatchQuality.high,
      );

  /// `deferred` or `direct`.
  final DLNLinkType type;

  /// `fullPath` up to the first `?`, not decoded (e.g. `/products/123`).
  final String path;

  /// Query parameters with FLOW-53 semantics.
  final Map<String, QueryValue> queryParams;

  /// `/` + path + `?query` exactly as received.
  final String fullPath;

  /// Absolute https URL of the link, without a `dln` fragment parameter (SDK-92).
  final String url;

  /// Which signal produced the link, or how the direct open arrived.
  final DLNLinkSource source;

  /// 0–100: the server score for `fingerprint`, 100 otherwise.
  final double confidenceScore;

  /// The server label for `fingerprint`, HIGH otherwise.
  final MatchQuality matchQuality;

  /// `deeplink.id` (server sources, or a resolved direct open).
  final String? deeplinkId;

  /// `deeplink.target_url`, raw (server sources, or a resolved direct open).
  final String? targetUrl;

  /// `deeplink.campaign_id`.
  final String? campaignId;

  /// `deeplink.metadata`.
  final Map<String, Object?>? metadata;

  /// ISO-8601 match time from the server (deferred server sources).
  final String? matchedAt;

  /// ISO-8601 end of the claim window (deferred server sources).
  final String? expiresAt;

  /// The score breakdown (`fingerprint` only).
  final MatchDetails? matchDetails;

  /// This link with the stored link's fields from `/sdk/resolve` (SDK-90).
  DLNLink withResolved({
    required String deeplinkId,
    required String? targetUrl,
    required String? campaignId,
    required Map<String, Object?>? metadata,
  }) =>
      DLNLink(
        type: type,
        path: path,
        queryParams: queryParams,
        fullPath: fullPath,
        url: url,
        source: source,
        confidenceScore: confidenceScore,
        matchQuality: matchQuality,
        deeplinkId: deeplinkId,
        targetUrl: targetUrl,
        campaignId: campaignId,
        metadata: metadata,
        matchedAt: matchedAt,
        expiresAt: expiresAt,
        matchDetails: matchDetails,
      );

  @override
  String toString() => 'DLNLink(${type.value}, ${source.value}, $fullPath)';
}

/// SDK-92: removes the `dln` parameter from [url]'s fragment (`#dln=<click id>`, or one of
/// several `&`-separated fragment parameters). Other fragment content is kept, and a fragment
/// left empty drops the `#`. The path and query are never touched. Plain string handling: no
/// URL parser, no host rule (FLT-01).
String stripDlnFragment(String url) {
  final hash = url.indexOf('#');
  if (hash < 0) return url;
  final base = url.substring(0, hash);
  final parts = url.substring(hash + 1).split('&');
  final kept = <String>[];
  var removed = false;
  for (final part in parts) {
    final eq = part.indexOf('=');
    final name = eq < 0 ? part : part.substring(0, eq);
    if (_decode(name) == 'dln') {
      removed = true;
    } else {
      kept.add(part);
    }
  }
  if (!removed) return url;
  final rest = kept.where((p) => p.isNotEmpty).join('&');
  return rest.isEmpty ? base : '$base#$rest';
}

String _decode(String value) {
  try {
    return Uri.decodeComponent(value);
  } on ArgumentError {
    return value;
  } on FormatException {
    return value;
  }
}
