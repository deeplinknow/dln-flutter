// Platforms without dart:io (web): the plugin has no native side there either, so resolving
// fails and the link is delivered unresolved (SDK-90 fail-open).

import 'resolve_http.dart';

/// Always fails: there is no HTTP client without dart:io.
Future<DLNHttpResponse> platformHttpGet(
  Uri uri,
  Map<String, String> headers,
  Duration timeout,
) =>
    Future.error(UnsupportedError('DeepLinkNow resolve needs dart:io'));
