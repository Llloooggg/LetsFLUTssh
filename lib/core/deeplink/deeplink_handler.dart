import 'dart:async';

import 'package:app_links/app_links.dart';

import '../../src/rust/api/deeplink.dart' as rust_deeplink;
import '../../utils/logger.dart';
import '../session/qr_codec.dart';
import '../session/qr_decoded_source.dart';
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
  /// Receives a unified [QrDecodedSource] — Rust-staged handle id +
  /// preview when the FRB native lib decoded the payload, or the
  /// Dart-walked `ExportPayloadData` tree when production fell back
  /// to the legacy pipeline.
  void Function(QrDecodedSource source)? onQrImport;

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
        level: LogLevel.warn,
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

  Future<void> handleCustomScheme(Uri uri) async {
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
      // The Rust path is async (FRB qrImportOpen). Awaiting here
      // keeps tests deterministic: callers can `await
      // handleCustomScheme(...)` and immediately assert `onQrImport`
      // was called. The deep-link pump in `init()` does not need to
      // serialise on this — it already fires per URI in arrival
      // order.
      await _handleImportUri(uri);
    } else {
      AppLogger.instance.log('Unknown action "${uri.host}"', name: 'DeepLink');
    }
  }

  /// Decode a `letsflutssh://import?d=...` URI. Tries the Rust
  /// `qrImportOpen` FRB path first so bytes never cross the FRB
  /// boundary outwards; falls back to the Dart `decodeImportUri`
  /// walker when the native lib isn't loaded (flutter_test, fresh
  /// checkout) or the Rust decoder rejected the payload.
  Future<void> _handleImportUri(Uri uri) async {
    final rustResult = await tryDecodeQrPayloadViaRust(uri.toString());
    if (rustResult != null) {
      AppLogger.instance.log(
        'QR import (Rust): ${rustResult.preview.sessionCount} session(s)',
        name: 'DeepLink',
      );
      onQrImport?.call(QrDecodedSource.rust(rustResult));
      return;
    }
    try {
      final data = decodeImportUri(uri);
      if (data != null) {
        AppLogger.instance.log(
          'QR import (Dart): ${data.sessions.length} session(s)',
          name: 'DeepLink',
        );
        onQrImport?.call(QrDecodedSource.dart(data));
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
  /// Returns null if required params (host, user) are missing or
  /// invalid.
  ///
  /// Routes through `lfs_core::deeplink::parse_connect_uri` —
  /// canonical validation rules (host length, control-char
  /// rejection, port range, percent-decoding) live Rust-side.
  /// The Dart fallback below mirrors the same rules; production
  /// never reaches it (FRB native lib is loaded at app start)
  /// but flutter_test does not load it and the deeplink fuzz
  /// suite calls this synchronously over 2k random URI shapes.
  static SSHConfig? parseConnectUri(Uri uri) {
    try {
      final link = rust_deeplink.parseConnectUri(uri: uri.toString());
      if (link == null) return null;
      return SSHConfig(
        server: ServerAddress(
          host: link.host,
          port: link.port,
          user: link.user,
        ),
      );
    } catch (_) {
      return _parseConnectUriDart(uri);
    }
  }

  /// Tiny Dart mirror of `lfs_core::deeplink::parse_connect_uri`.
  /// Lives here only for the flutter_test surface — production
  /// never falls through.
  static SSHConfig? _parseConnectUriDart(Uri uri) {
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
    if (host.length > 253 ||
        host.contains('/') ||
        host.contains('\\') ||
        _containsControlChar(host)) {
      return null;
    }
    if (user.length > 256 ||
        user.contains('/') ||
        user.contains('\\') ||
        _containsControlChar(user)) {
      return null;
    }
    final port = int.tryParse(params['port'] ?? '') ?? 22;
    if (port < 1 || port > 65535) return null;
    return SSHConfig(
      server: ServerAddress(host: host, port: port, user: user),
    );
  }

  /// True if [s] contains any C0/C1 control character (0x00–0x1F,
  /// 0x7F–0x9F). Catches null bytes, CR/LF injection, BEL/escape.
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
