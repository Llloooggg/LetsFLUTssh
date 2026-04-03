import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection.dart';
import '../../core/session/session.dart';
import '../../core/ssh/ssh_config.dart';
import '../../providers/connection_provider.dart';
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
  /// Returns false if session is incomplete (missing credentials).
  static bool connectTerminal(BuildContext context, WidgetRef ref, Session session) {
    final conn = _createConnection(context, ref, session, 'terminal');
    if (conn == null) return false;
    ref.read(workspaceProvider.notifier).addTerminalTab(conn);
    return true;
  }

  /// Open an SFTP tab and connect to session in background.
  /// Returns false if session is incomplete (missing credentials).
  static bool connectSftp(BuildContext context, WidgetRef ref, Session session) {
    final conn = _createConnection(context, ref, session, 'SFTP');
    if (conn == null) return false;
    ref.read(workspaceProvider.notifier).addSftpTab(conn);
    return true;
  }

  /// Validate session and create a background connection, or return null on failure.
  static Connection? _createConnection(
    BuildContext context,
    WidgetRef ref,
    Session session,
    String logLabel,
  ) {
    if (session.incomplete) {
      _showIncompleteMessage(context);
      return null;
    }
    AppLogger.instance.log('Opening $logLabel for ${session.label}', name: 'Session');
    final config = session.toSSHConfig();
    final manager = ref.read(connectionManagerProvider);
    return manager.connectAsync(
      config,
      label: session.label.isNotEmpty ? session.label : session.displayName,
      sessionId: session.id,
    );
  }

  static void _showIncompleteMessage(BuildContext context) {
    Toast.show(
      context,
      message: 'Session has no credentials — edit it first to add a password or key',
      level: ToastLevel.warning,
    );
  }

  /// Open a terminal tab with SSHConfig directly (quick connect).
  static void connectConfig(BuildContext context, WidgetRef ref, SSHConfig config) {
    AppLogger.instance.log('Quick connect to ${config.host}', name: 'Session');
    final manager = ref.read(connectionManagerProvider);
    final conn = manager.connectAsync(config);
    ref.read(workspaceProvider.notifier).addTerminalTab(conn);
  }
}
