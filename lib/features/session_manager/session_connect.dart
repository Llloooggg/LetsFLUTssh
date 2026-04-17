import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection.dart';
import '../../core/session/session.dart';
import '../../core/ssh/ssh_config.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/connection_provider.dart';
import '../../providers/key_provider.dart';
import '../../providers/session_provider.dart';
import '../../utils/logger.dart';
import '../../widgets/toast.dart';
import '../workspace/workspace_controller.dart';

/// Shared connection logic used by both main.dart and mobile_shell.dart.
///
/// Opens tabs immediately (in connecting state), connection happens in background.
/// Connection status is shown inside the terminal/SFTP tab, not as a toast.
class SessionConnect {
  SessionConnect._();

  /// Open a terminal tab and connect to session in background.
  /// Returns false if session is invalid (missing credentials).
  static Future<bool> connectTerminal(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    final conn = await _createConnection(context, ref, session, 'terminal');
    if (conn == null) return false;
    ref.read(workspaceProvider.notifier).addTerminalTab(conn);
    return true;
  }

  /// Open an SFTP tab and connect to session in background.
  /// Returns false if session is invalid (missing credentials).
  static Future<bool> connectSftp(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    final conn = await _createConnection(context, ref, session, 'SFTP');
    if (conn == null) return false;
    ref.read(workspaceProvider.notifier).addSftpTab(conn);
    return true;
  }

  /// Validate session and create a background connection, or return null on failure.
  ///
  /// The [session] passed in comes from the in-memory cache and carries no
  /// credentials — we reload it from the DB here so the plaintext password/
  /// keyData/passphrase are only on the Dart heap for the duration of the
  /// connect handshake, not for the whole app lifetime.
  static Future<Connection?> _createConnection(
    BuildContext context,
    WidgetRef ref,
    Session session,
    String logLabel,
  ) async {
    final store = ref.read(sessionStoreProvider);
    final fresh = await store.loadWithCredentials(session.id) ?? session;
    if (!fresh.isValid) {
      if (context.mounted) _showIncompleteMessage(context);
      return null;
    }
    AppLogger.instance.log(
      'Opening $logLabel for ${fresh.label}',
      name: 'Session',
    );
    final config = await _resolveConfig(ref, fresh);
    final manager = ref.read(connectionManagerProvider);
    return manager.connectAsync(
      config,
      label: fresh.label.isNotEmpty ? fresh.label : fresh.displayName,
      sessionId: fresh.id,
    );
  }

  /// Build SSHConfig, resolving keyId from the key store if set.
  static Future<SSHConfig> _resolveConfig(
    WidgetRef ref,
    Session session,
  ) async {
    final config = session.toSSHConfig();
    if (session.keyId.isEmpty) return config;

    final keyStore = ref.read(keyStoreProvider);
    final entry = await keyStore.get(session.keyId);
    if (entry == null) {
      AppLogger.instance.log(
        'Key ${session.keyId} not found in key store',
        name: 'Session',
      );
      return config;
    }
    AppLogger.instance.log('Resolved keyId ${session.keyId}', name: 'Session');
    return config.copyWith(
      auth: config.auth.copyWith(keyData: entry.privateKey),
    );
  }

  static void _showIncompleteMessage(BuildContext context) {
    Toast.show(
      context,
      message: S.of(context).sessionNoCredentials,
      level: ToastLevel.warning,
    );
  }

  /// Open a terminal tab with SSHConfig directly (quick connect).
  static void connectConfig(
    BuildContext context,
    WidgetRef ref,
    SSHConfig config,
  ) {
    AppLogger.instance.log('Quick connect to ${config.host}', name: 'Session');
    final manager = ref.read(connectionManagerProvider);
    final conn = manager.connectAsync(config);
    ref.read(workspaceProvider.notifier).addTerminalTab(conn);
  }
}
