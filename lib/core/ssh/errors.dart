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
  final String? user;
  final String? host;

  const AuthError(super.message, [super.cause, this.user, this.host]);
}

/// Connection failure (timeout, host unreachable, etc.)
class ConnectError extends SSHError {
  final String? host;
  final int? port;

  const ConnectError(super.message, [super.cause, this.host, this.port]);
}

/// Host key verification failure (MITM or changed key).
class HostKeyError extends SSHError {
  final String? host;
  final int? port;

  const HostKeyError(super.message, [super.cause, this.host, this.port]);
}

/// ProxyJump chain referenced a session that links back to one
/// already in the chain. Carries the offending session id so the UI
/// can highlight the relevant row in the manager.
class ProxyJumpCycleError extends SSHError {
  final String offendingSessionId;
  ProxyJumpCycleError(this.offendingSessionId)
    : super('ProxyJump cycle detected at session $offendingSessionId');
}

/// ProxyJump chain exceeded the safety limit. Catches typos / mistakes
/// before users dial out into a 50-hop accidental loop.
class ProxyJumpDepthError extends SSHError {
  final int depth;
  ProxyJumpDepthError(this.depth)
    : super('ProxyJump chain exceeded max depth ($depth)');
}

/// Bastion connect or auth failed. The original failure is wrapped
/// as `cause` so the UI shows root cause; the message names the
/// bastion's user@host so users know which hop fell over.
class ProxyJumpBastionError extends SSHError {
  final String bastionLabel;
  ProxyJumpBastionError(this.bastionLabel, Object? cause)
    : super('Bastion $bastionLabel failed', cause);
}
