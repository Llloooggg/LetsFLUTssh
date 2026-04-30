import 'dart:async';

import 'package:app_links/app_links.dart';

import '../../src/rust/api/archive.dart' as rust_archive;
import '../../src/rust/api/deeplink.dart' as rust_deeplink;
import '../../utils/logger.dart';
import '../session/qr_decoded_source.dart';
import '../ssh/ssh_config.dart';

/// Handles deep links and file open intents:
///
/// 1. `letsflutssh://connect?host=X&port=22&user=Y` — SSH connect
/// 2. `letsflutssh://import?d=...` — import sessions / keys / config
/// 3. `file://.../*.pem`, `content://.../*.key` — import SSH key
/// 4. `file://.../*.lfs`, `content://.../*.lfs` — import data archive
///
/// Routing, dedup, and QR-payload staging all live Rust-side in
/// `lfs_core::deeplink::DeeplinkDispatcher`. The Dart side is the
/// thin URI pump: subscribe to `app_links` (a Flutter plugin —
/// stays Dart), forward every URI through `deeplinkDispatch`, then
/// switch on the typed [rust_deeplink.DbDeeplinkOutcome] to fire
/// the matching UI callback.
class DeepLinkHandler {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription? _sub;

  /// Callback invoked when a valid SSH connect link is received.
  void Function(SSHConfig config)? onConnect;

  /// Callback invoked when a QR import link is received with a
  /// payload this build can decode. The wrapped
  /// [QrDecodedSource.rust] carries the Rust-staged handle id +
  /// sanitised preview — bytes never crossed the FRB boundary.
  void Function(QrDecodedSource source)? onQrImport;

  /// Callback invoked when a QR import link carries a payload schema
  /// version newer than this build understands. The UI surfaces an
  /// "update the app" prompt instead of silently dropping the import.
  void Function(int found, int supported)? onQrImportVersionTooNew;

  /// Callback invoked when an SSH key file is opened (.pem, .key, .pub).
  void Function(String filePath)? onKeyFileOpened;

  /// Callback invoked when a .lfs archive is opened.
  void Function(String filePath)? onLfsFileOpened;

  /// Start listening for incoming deep links.
  Future<void> init() async {
    // Cold-start: app launched via deep link.
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        await handleUri(initialUri);
      }
    } catch (e) {
      AppLogger.instance.log('No initial link ($e)', name: 'DeepLink');
    }

    // Warm-start: links arriving while the app is running.
    _sub = _appLinks.uriLinkStream.listen(
      (uri) => unawaited(handleUri(uri)),
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

  /// Pump one URI through the Rust dispatcher and route to the
  /// matching callback. Public so tests can drive the handler
  /// without going through `app_links`.
  Future<void> handleUri(Uri uri) async {
    AppLogger.instance.log('Received: ${_sanitizeUri(uri)}', name: 'DeepLink');
    final rust_deeplink.DbDeeplinkOutcome outcome;
    try {
      outcome = await rust_deeplink.deeplinkDispatch(uri: uri.toString());
    } catch (e) {
      AppLogger.instance.log(
        'deeplinkDispatch failed: $e',
        name: 'DeepLink',
        level: LogLevel.warn,
      );
      return;
    }
    _route(outcome);
  }

  void _route(rust_deeplink.DbDeeplinkOutcome outcome) {
    switch (outcome) {
      case rust_deeplink.DbDeeplinkOutcome_Connect(
        :final host,
        :final port,
        :final user,
      ):
        onConnect?.call(
          SSHConfig(
            server: ServerAddress(host: host, port: port, user: user),
          ),
        );
      case rust_deeplink.DbDeeplinkOutcome_QrImport(
        :final handleId,
        :final preview,
      ):
        AppLogger.instance.log(
          'QR import (Rust): ${preview.sessionCount} session(s)',
          name: 'DeepLink',
        );
        onQrImport?.call(
          QrDecodedSource.rust(
            rust_archive.DbImportOpenResult(
              handleId: handleId,
              preview: preview,
            ),
          ),
        );
      case rust_deeplink.DbDeeplinkOutcome_QrImportRejected(
        :final found,
        :final supported,
      ):
        AppLogger.instance.log(
          'QR import rejected: payload v$found > supported v$supported',
          name: 'DeepLink',
        );
        onQrImportVersionTooNew?.call(found, supported);
      case rust_deeplink.DbDeeplinkOutcome_OpenLfs(:final path):
        onLfsFileOpened?.call(path);
      case rust_deeplink.DbDeeplinkOutcome_OpenKeyFile(:final path):
        onKeyFileOpened?.call(path);
      case rust_deeplink.DbDeeplinkOutcome_Unknown():
        AppLogger.instance.log(
          'No actionable mapping',
          name: 'DeepLink',
          level: LogLevel.warn,
        );
      case rust_deeplink.DbDeeplinkOutcome_Duplicate():
        AppLogger.instance.log(
          'Skipping duplicate (Rust dedup)',
          name: 'DeepLink',
        );
    }
  }

  /// Parse a `letsflutssh://connect?...` URI into an [SSHConfig].
  /// Returns null if required params (host, user) are missing or
  /// invalid.
  ///
  /// Routes through `lfs_core::deeplink::parse_connect_uri` —
  /// canonical validation rules (host length, control-char
  /// rejection, port range, percent-decoding) live Rust-side.
  static SSHConfig? parseConnectUri(Uri uri) {
    final link = rust_deeplink.parseConnectUri(uri: uri.toString());
    if (link == null) return null;
    return SSHConfig(
      server: ServerAddress(host: link.host, port: link.port, user: link.user),
    );
  }

  void dispose() {
    _sub?.cancel();
    onConnect = null;
    onQrImport = null;
    onKeyFileOpened = null;
    onLfsFileOpened = null;
  }
}
