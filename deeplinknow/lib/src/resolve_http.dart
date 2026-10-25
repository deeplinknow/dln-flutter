// The one HTTP request the Dart layer makes: `GET /api/v1/sdk/resolve` (SDK-90). See FLT-01 and
// FLT-30 for why it lives here rather than in the native SDKs.

export 'resolve_http_stub.dart' if (dart.library.io) 'resolve_http_io.dart' show platformHttpGet;

/// A finished HTTP response: the status code and the body text.
class DLNHttpResponse {
  /// Creates the response.
  const DLNHttpResponse(this.status, this.body);

  /// HTTP status code.
  final int status;

  /// Response body (UTF-8).
  final String body;
}

/// Sends a GET to [uri] with [headers]. Must complete or fail within [timeout].
typedef DLNHttpGet = Future<DLNHttpResponse> Function(
  Uri uri,
  Map<String, String> headers,
  Duration timeout,
);

/// `{baseUrl}/api/v1/sdk/resolve?path=<fullPath>` (API-SDK-71). A trailing `/` on [baseUrl] is
/// tolerated (SDK-01).
Uri resolveUri(String baseUrl, String fullPath) {
  final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  return Uri.parse('$base/api/v1/sdk/resolve').replace(queryParameters: {'path': fullPath});
}
