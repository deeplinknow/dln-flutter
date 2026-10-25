// dart:io HTTP for `GET /api/v1/sdk/resolve` (SDK-90). Imported only where dart:io exists.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'resolve_http.dart';

/// Sends the GET with dart:io's [HttpClient]. The whole request (connect, headers, body) is
/// bounded by [timeout]; on timeout the connection is closed and a [TimeoutException] thrown.
Future<DLNHttpResponse> platformHttpGet(
  Uri uri,
  Map<String, String> headers,
  Duration timeout,
) async {
  final client = HttpClient()..connectionTimeout = timeout;
  Future<DLNHttpResponse> send() async {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return DLNHttpResponse(response.statusCode, body);
  }

  try {
    return await send().timeout(timeout);
  } finally {
    client.close(force: true);
  }
}
