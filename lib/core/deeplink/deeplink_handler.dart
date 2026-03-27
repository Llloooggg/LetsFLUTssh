import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../utils/logger.dart';
import '../ssh/ssh_config.dart';

/// Handles deep links and file open intents:
///
/// 1. `letsflutssh://connect?host=X&port=22&user=Y&password=Z` — SSH connect
/// 2. `file://.../*.pem`, `content://.../*.key` — import SSH key
/// 3. `file://.../*.lfs`, `content://.../*.lfs` — import data archive
class DeepLinkHandler {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription? _sub;

  /// Callback invoked when a valid SSH connect link is received.
  void Function(SSHConfig config)? onConnect;

  /// Callback invoked when an SSH key file is opened (.pem, .key).
  void Function(String filePath)? onKeyFileOpened;

  /// Callback invoked when a .lfs archive is opened.
  void Function(String filePath)? onLfsFileOpened;

  /// Start listening for incoming deep links.
  Future<void> init() async {
    // Check if app was opened via deep link (cold start)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        handleUri(initialUri);
      }
    } catch (e) {
      AppLogger.instance.log('No initial link ($e)', name: 'DeepLink');
    }

    // Listen for links while app is running (warm start)
    _sub = _appLinks.uriLinkStream.listen(
      handleUri,
      onError: (e) => AppLogger.instance.log('Stream error: $e', name: 'DeepLink'),
    );
  }

  /// Sanitize URI for logging — deep links no longer carry credentials,
  /// but we still strip any unexpected sensitive-looking parameters.
  static String _sanitizeUri(Uri uri) {
    if (uri.queryParameters.isEmpty) return uri.toString();
    final safe = Map<String, String>.from(uri.queryParameters);
    for (final key in ['password', 'passphrase', 'key_data', 'key']) {
      if (safe.containsKey(key)) safe[key] = '***';
    }
    return uri.replace(queryParameters: safe).toString();
  }

  @visibleForTesting
  void handleUri(Uri uri) {
    AppLogger.instance.log('Received: ${_sanitizeUri(uri)}', name: 'DeepLink');

    if (uri.scheme == 'letsflutssh') {
      handleCustomScheme(uri);
    } else if (uri.scheme == 'file' || uri.scheme == 'content') {
      handleFileUri(uri);
    } else {
      AppLogger.instance.log('Unhandled scheme "${uri.scheme}"', name: 'DeepLink');
    }
  }

  @visibleForTesting
  void handleCustomScheme(Uri uri) {
    if (uri.host == 'connect') {
      final config = parseConnectUri(uri);
      if (config != null) {
        onConnect?.call(config);
      } else {
        AppLogger.instance.log('Invalid connect params — host and user required', name: 'DeepLink');
      }
    } else {
      AppLogger.instance.log('Unknown action "${uri.host}"', name: 'DeepLink');
    }
  }

  @visibleForTesting
  void handleFileUri(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.endsWith('.lfs')) {
      onLfsFileOpened?.call(uri.toFilePath());
    } else if (path.endsWith('.pem') || path.endsWith('.key') || path.endsWith('.pub')) {
      onKeyFileOpened?.call(uri.toFilePath());
    } else {
      AppLogger.instance.log('Unsupported file type "$path"', name: 'DeepLink');
    }
  }

  /// Parse a `letsflutssh://connect?...` URI into an [SSHConfig].
  /// Returns null if required params (host, user) are missing or invalid.
  static SSHConfig? parseConnectUri(Uri uri) {
    final params = uri.queryParameters;
    final host = params['host']?.trim();
    final user = params['user']?.trim();

    if (host == null || host.isEmpty || user == null || user.isEmpty) {
      return null;
    }

    // Validate host: no path separators, null bytes, reasonable length
    if (host.length > 253 || host.contains('/') || host.contains('\\') || host.contains('\x00')) {
      AppLogger.instance.log('Invalid host', name: 'DeepLink');
      return null;
    }

    // Validate port range
    final port = int.tryParse(params['port'] ?? '') ?? 22;
    if (port < 1 || port > 65535) {
      AppLogger.instance.log('Invalid port $port', name: 'DeepLink');
      return null;
    }

    // No credentials in deep links — passwords and keys are never transmitted
    // via URL for security reasons (URLs can be logged by OS, clipboard, etc.)

    return SSHConfig(
      server: ServerAddress(host: host, port: port, user: user),
    );
  }

  void dispose() {
    _sub?.cancel();
  }
}
