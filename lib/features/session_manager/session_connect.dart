import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session.dart';
import '../../core/ssh/errors.dart';
import '../../core/ssh/ssh_config.dart';
import '../../providers/connection_provider.dart';
import '../../widgets/toast.dart';
import '../tabs/tab_controller.dart';

/// Shared connection logic used by both main.dart and mobile_shell.dart.
class SessionConnect {
  SessionConnect._();

  /// Connect to a session via SSH and open a terminal tab.
  static Future<void> connectTerminal(BuildContext context, WidgetRef ref, Session session) async {
    final config = session.toSSHConfig();
    try {
      final manager = ref.read(connectionManagerProvider);
      final conn = await manager.connect(
        config,
        label: session.label.isNotEmpty ? session.label : session.displayName,
      );
      ref.read(tabProvider.notifier).addTerminalTab(conn);
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  /// Connect to a session via SSH and open an SFTP tab.
  static Future<void> connectSftp(BuildContext context, WidgetRef ref, Session session) async {
    final config = session.toSSHConfig();
    try {
      final manager = ref.read(connectionManagerProvider);
      final conn = await manager.connect(
        config,
        label: session.label.isNotEmpty ? session.label : session.displayName,
      );
      ref.read(tabProvider.notifier).addSftpTab(conn);
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  /// Connect with SSHConfig directly (without saving a session).
  static Future<void> connectConfig(BuildContext context, WidgetRef ref, SSHConfig config) async {
    try {
      final manager = ref.read(connectionManagerProvider);
      final conn = await manager.connect(config);
      ref.read(tabProvider.notifier).addTerminalTab(conn);
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  /// Show a descriptive error toast for connection failures.
  static void _showError(BuildContext context, Object error) {
    final String msg;
    if (error is HostKeyError) {
      msg = error.userMessage;
    } else if (error is AuthError) {
      msg = 'Auth failed: ${error.userMessage}';
    } else if (error is ConnectError) {
      msg = error.userMessage;
    } else {
      msg = 'Connection error: $error';
    }
    Toast.show(context, message: msg, level: ToastLevel.error);
  }
}
