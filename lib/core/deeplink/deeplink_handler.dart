import 'dart:async';
import 'dart:developer' as dev;

import 'package:app_links/app_links.dart';

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
        _handleUri(initialUri);
      }
    } catch (e) {
      dev.log('DeepLink: no initial link ($e)');
    }

    // Listen for links while app is running (warm start)
    _sub = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (e) => dev.log('DeepLink stream error: $e'),
    );
  }

  void _handleUri(Uri uri) {
    dev.log('DeepLink received: $uri');

    if (uri.scheme == 'letsflutssh') {
      _handleCustomScheme(uri);
    } else if (uri.scheme == 'file' || uri.scheme == 'content') {
      _handleFileUri(uri);
    } else {
      dev.log('DeepLink: unhandled scheme "${uri.scheme}"');
    }
  }

  void _handleCustomScheme(Uri uri) {
    if (uri.host == 'connect') {
      final config = parseConnectUri(uri);
      if (config != null) {
        onConnect?.call(config);
      } else {
        dev.log('DeepLink: invalid connect params — host and user required');
      }
    } else {
      dev.log('DeepLink: unknown action "${uri.host}"');
    }
  }

  void _handleFileUri(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.endsWith('.lfs')) {
      onLfsFileOpened?.call(uri.toFilePath());
    } else if (path.endsWith('.pem') || path.endsWith('.key') || path.endsWith('.pub')) {
      onKeyFileOpened?.call(uri.toFilePath());
    } else {
      dev.log('DeepLink: unsupported file type "$path"');
    }
  }

  /// Parse a `letsflutssh://connect?...` URI into an [SSHConfig].
  /// Returns null if required params (host, user) are missing.
  static SSHConfig? parseConnectUri(Uri uri) {
    final params = uri.queryParameters;
    final host = params['host'];
    final user = params['user'];

    if (host == null || host.isEmpty || user == null || user.isEmpty) {
      return null;
    }

    return SSHConfig(
      host: host,
      port: int.tryParse(params['port'] ?? '') ?? 22,
      user: user,
      password: params['password'] ?? '',
      keyPath: params['key'] ?? '',
    );
  }

  void dispose() {
    _sub?.cancel();
  }
}
