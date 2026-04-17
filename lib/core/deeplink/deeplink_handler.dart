import 'dart:async';

import 'package:app_links/app_links.dart';

import '../../utils/logger.dart';
import '../session/qr_codec.dart';
import '../ssh/ssh_config.dart';

/// Handles deep links and file open intents:
///
/// 1. `letsflutssh://connect?host=X&port=22&user=Y&password=Z` — SSH connect
/// 2. `file://.../*.pem`, `content://.../*.key` — import SSH key
/// 3. `file://.../*.lfs`, `content://.../*.lfs` — import data archive
class DeepLinkHandler {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription? _sub;

  /// Tracks the last processed URI and timestamp to prevent duplicate handling.
  /// Cold start: getInitialLink + uriLinkStream can fire the same URI.
  /// The dedup window is limited to [_deduplicationWindow] so that
  /// re-scanning the same QR code or re-opening the same link after the
  /// cold-start race window still works.
  Uri? _lastProcessedUri;
  DateTime? _lastProcessedTime;

  /// Duration during which a duplicate URI is suppressed.
  /// Only needs to cover the cold-start double-fire race (typically < 1 s).
  static const _deduplicationWindow = Duration(seconds: 2);

  /// Callback invoked when a valid SSH connect link is received.
  void Function(SSHConfig config)? onConnect;

  /// Callback invoked when a QR import link is received.
  void Function(ExportPayloadData data)? onQrImport;

  /// Callback invoked when a QR import link carries a payload schema version
  /// newer than this build understands. The UI should surface an "update
  /// the app" prompt instead of silently dropping the import.
  void Function(int found, int supported)? onQrImportVersionTooNew;

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
      onError: (e) =>
          AppLogger.instance.log('Stream error: $e', name: 'DeepLink'),
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

  void handleUri(Uri uri) {
    // Deduplicate: cold start can fire both getInitialLink and uriLinkStream.
    // The window is time-limited so re-scanning the same QR after the
    // cold-start race still works (e.g. app resumed from background).
    final now = DateTime.now();
    if (_lastProcessedUri == uri &&
        _lastProcessedTime != null &&
        now.difference(_lastProcessedTime!) < _deduplicationWindow) {
      AppLogger.instance.log(
        'Skipping duplicate: ${_sanitizeUri(uri)}',
        name: 'DeepLink',
      );
      return;
    }
    _lastProcessedUri = uri;
    _lastProcessedTime = now;

    AppLogger.instance.log('Received: ${_sanitizeUri(uri)}', name: 'DeepLink');

    if (uri.scheme == 'letsflutssh') {
      handleCustomScheme(uri);
    } else if (uri.scheme == 'file' || uri.scheme == 'content') {
      handleFileUri(uri);
    } else {
      AppLogger.instance.log(
        'Unhandled scheme "${uri.scheme}"',
        name: 'DeepLink',
      );
    }
  }

  void handleCustomScheme(Uri uri) {
    if (uri.host == 'connect') {
      final config = parseConnectUri(uri);
      if (config != null) {
        onConnect?.call(config);
      } else {
        AppLogger.instance.log(
          'Invalid connect params — host and user required',
          name: 'DeepLink',
        );
      }
    } else if (uri.host == 'import') {
      try {
        final data = decodeImportUri(uri);
        if (data != null) {
          AppLogger.instance.log(
            'QR import: ${data.sessions.length} session(s)',
            name: 'DeepLink',
          );
          onQrImport?.call(data);
        } else {
          AppLogger.instance.log('Invalid import data', name: 'DeepLink');
        }
      } on QrPayloadVersionTooNewException catch (e) {
        AppLogger.instance.log(
          'QR import rejected: payload v${e.found} > supported v${e.supported}',
          name: 'DeepLink',
        );
        onQrImportVersionTooNew?.call(e.found, e.supported);
      }
    } else {
      AppLogger.instance.log('Unknown action "${uri.host}"', name: 'DeepLink');
    }
  }

  void handleFileUri(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.endsWith('.lfs')) {
      onLfsFileOpened?.call(uri.toFilePath());
    } else if (path.endsWith('.pem') ||
        path.endsWith('.key') ||
        path.endsWith('.pub')) {
      onKeyFileOpened?.call(uri.toFilePath());
    } else {
      AppLogger.instance.log('Unsupported file type "$path"', name: 'DeepLink');
    }
  }

  /// Parse a `letsflutssh://connect?...` URI into an [SSHConfig].
  /// Returns null if required params (host, user) are missing or invalid.
  ///
  /// Inputs come from external deep links (OS-level URI handlers), so the
  /// parser must never throw on garbage. Malformed percent-encoding in
  /// the query string raises FormatException from dart:core's lazy
  /// queryParameters decoder; treat that as "invalid URI, return null"
  /// to keep the contract single-typed for callers.
  static SSHConfig? parseConnectUri(Uri uri) {
    final Map<String, String> params;
    try {
      params = uri.queryParameters;
    } on FormatException catch (e) {
      AppLogger.instance.log('Malformed query string: $e', name: 'DeepLink');
      return null;
    }
    final host = params['host']?.trim();
    final user = params['user']?.trim();

    if (host == null || host.isEmpty || user == null || user.isEmpty) {
      return null;
    }

    // Validate host: no path separators, null bytes, reasonable length
    if (host.length > 253 ||
        host.contains('/') ||
        host.contains('\\') ||
        _containsControlChar(host)) {
      AppLogger.instance.log('Invalid host', name: 'DeepLink');
      return null;
    }

    // Validate user: bound the length, reject control chars / null bytes /
    // path separators. POSIX `useradd` caps at 32 chars; allow more to cover
    // domain-style accounts (`user@domain`) but stay well under DoS-able size.
    if (user.length > 256 ||
        user.contains('/') ||
        user.contains('\\') ||
        _containsControlChar(user)) {
      AppLogger.instance.log('Invalid user', name: 'DeepLink');
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

  /// True if [s] contains any C0/C1 control character (0x00–0x1F, 0x7F–0x9F).
  /// Catches null bytes, CR/LF injection into ssh-config, BEL/escape chars
  /// that could mangle terminal prompts.
  static bool _containsControlChar(String s) {
    for (final cu in s.codeUnits) {
      if (cu < 0x20 || (cu >= 0x7F && cu <= 0x9F)) return true;
    }
    return false;
  }

  void dispose() {
    _sub?.cancel();
    onConnect = null;
    onQrImport = null;
    onKeyFileOpened = null;
    onLfsFileOpened = null;
  }
}
