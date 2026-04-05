// Structured SSH error types with cause unwrapping.

class SSHError implements Exception {
  final String message;
  final Object? cause;

  const SSHError(this.message, [this.cause]);

  /// Human-readable error with root cause details.
  String get userMessage {
    if (cause == null) return message;
    // Extract the root cause message, stripping wrapper types
    final causeStr = _rootCauseMessage(cause!);
    if (causeStr.isNotEmpty && causeStr != message) {
      return '$message ($causeStr)';
    }
    return message;
  }

  static String _rootCauseMessage(Object error) {
    if (error is SSHError) {
      return error.userMessage;
    }
    final s = error.toString();
    // Strip common type prefixes for cleaner display
    for (final prefix in [
      'SocketException: ',
      'SSHAuthFailError: ',
      'SSHAuthAbortError: ',
      'Exception: ',
    ]) {
      if (s.startsWith(prefix)) return s.substring(prefix.length);
    }
    return s;
  }

  @override
  String toString() {
    if (cause != null) {
      return '$runtimeType: $message (caused by: $cause)';
    }
    return '$runtimeType: $message';
  }
}

/// Authentication failure (wrong password, bad key, etc.)
class AuthError extends SSHError {
  const AuthError(super.message, [super.cause]);
}

/// Connection failure (timeout, host unreachable, etc.)
class ConnectError extends SSHError {
  const ConnectError(super.message, [super.cause]);
}

/// Host key verification failure (MITM or changed key).
class HostKeyError extends SSHError {
  const HostKeyError(super.message, [super.cause]);
}
