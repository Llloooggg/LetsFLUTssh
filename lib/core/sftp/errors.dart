/// Structured SFTP error types.
///
/// Wraps raw russh-sftp errors (surfaced as strings through the FRB
/// boundary) with user-friendly messages and optional path context
/// for UI display.
class SFTPError implements Exception {
  final String message;
  final Object? cause;

  /// Remote path involved in the operation, if available.
  final String? path;

  const SFTPError(this.message, {this.cause, this.path});

  /// SFTP status code from the server, or `null` if the error is not
  /// a status response (e.g. local I/O failure, connection lost). The
  /// Rust transport surfaces server status as a free-form string, so
  /// this returns `null` until a structured StatusError type lands.
  int? get statusCode => null;

  /// Human-readable error with root cause details.
  String get userMessage {
    if (cause == null) return message;
    final causeStr = _rootCauseMessage(cause!);
    if (causeStr.isNotEmpty && causeStr != message) {
      return '$message ($causeStr)';
    }
    return message;
  }

  static String _rootCauseMessage(Object error) {
    if (error is SFTPError) return error.userMessage;
    final s = error.toString();
    for (final prefix in [
      'SftpStatusError: ',
      'SftpError: ',
      'SftpAbortError: ',
    ]) {
      if (s.startsWith(prefix)) return s.substring(prefix.length);
    }
    return s;
  }

  /// Wrap an exception thrown by an SFTP operation into a typed [SFTPError].
  ///
  /// [operation] describes what was being done (e.g. "list", "upload").
  /// [path] is the remote path involved.
  static SFTPError wrap(Object error, String operation, [String? path]) {
    return SFTPError('SFTP $operation failed', cause: error, path: path);
  }

  @override
  String toString() {
    final parts = <String>['SFTPError: $message'];
    if (path != null) parts.add('path: $path');
    if (cause != null) parts.add('caused by: $cause');
    return parts.join(' ');
  }
}
