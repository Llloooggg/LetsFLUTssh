// Structured SSH error types with cause unwrapping.

class SSHError implements Exception {
  final String message;
  final Object? cause;

  const SSHError(this.message, [this.cause]);

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
