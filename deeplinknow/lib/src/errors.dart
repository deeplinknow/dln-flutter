/// The error codes shared by every DeepLinkNow SDK (SDK-55).
///
/// The wire value ([code]) is the same string on iOS, Android, React Native and Flutter.
enum DLNErrorCode {
  /// `initialize` was never called, failed, or the native plugin is missing.
  notInitialized('notInitialized'),

  /// HTTP 401: the API key is unknown or revoked.
  invalidApiKey('invalidApiKey'),

  /// HTTP 403 "Account is not active".
  accountInactive('accountInactive'),

  /// HTTP 403 "No credits remaining".
  noCredits('noCredits'),

  /// HTTP 429.
  rateLimited('rateLimited'),

  /// HTTP 400, or an invalid local configuration (for example a non-https `baseUrl`).
  badRequest('badRequest'),

  /// HTTP 5xx.
  server('server'),

  /// Transport error, timeout or offline.
  network('network'),

  /// A malformed or unexpected response, from the server or from the native plugin.
  invalidResponse('invalidResponse');

  const DLNErrorCode(this.code);

  /// The shared wire value (e.g. `invalidApiKey`).
  final String code;

  /// Maps a native code to the enum. iOS's `invalidConfiguration` is reported as [badRequest]
  /// (as React Native does); anything unknown is [invalidResponse].
  static DLNErrorCode fromCode(String? code) {
    if (code == 'invalidConfiguration') return DLNErrorCode.badRequest;
    for (final value in DLNErrorCode.values) {
      if (value.code == code) return value;
    }
    return DLNErrorCode.invalidResponse;
  }
}

/// A typed DeepLinkNow failure (SDK-55), kept in `DeepLinkNow.lastError` (SDK-85).
class DLNError implements Exception {
  /// Creates an error.
  const DLNError(
    this.code, {
    this.message,
    this.status,
    this.serverMessage,
    this.cause,
  });

  /// The shared error code.
  final DLNErrorCode code;

  /// A human-readable description.
  final String? message;

  /// The HTTP status, when the failure came from the server.
  final int? status;

  /// The server's `error` / `message` string, when there was one.
  final String? serverMessage;

  /// The underlying DeepLinkNow error (e.g. the init failure behind `notInitialized`).
  final DLNError? cause;

  @override
  String toString() {
    final buffer = StringBuffer('DLNError(${code.code}');
    if (status != null) buffer.write(', HTTP $status');
    if (message != null && message!.isNotEmpty) buffer.write(': $message');
    if (cause != null) buffer.write(', cause: ${cause!.code.code}');
    buffer.write(')');
    return buffer.toString();
  }
}
