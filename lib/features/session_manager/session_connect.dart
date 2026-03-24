import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session.dart';
import '../../core/ssh/errors.dart';
import '../../providers/connection_provider.dart';
import '../../widgets/toast.dart';
import '../tabs/tab_controller.dart';
import 'quick_connect_dialog.dart';

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
    } on AuthError catch (e) {
      if (context.mounted) Toast.show(context, message: 'Authentication failed: ${e.message}', level: ToastLevel.error);
    } on ConnectError catch (e) {
      if (context.mounted) Toast.show(context, message: 'Connection failed: ${e.message}', level: ToastLevel.error);
    } catch (e) {
      if (context.mounted) Toast.show(context, message: 'Error: $e', level: ToastLevel.error);
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
    } on AuthError catch (e) {
      if (context.mounted) Toast.show(context, message: 'Authentication failed: ${e.message}', level: ToastLevel.error);
    } on ConnectError catch (e) {
      if (context.mounted) Toast.show(context, message: 'Connection failed: ${e.message}', level: ToastLevel.error);
    } catch (e) {
      if (context.mounted) Toast.show(context, message: 'Error: $e', level: ToastLevel.error);
    }
  }

  /// Show quick connect dialog and open a terminal tab.
  static Future<void> quickConnect(BuildContext context, WidgetRef ref) async {
    final config = await QuickConnectDialog.show(context);
    if (config == null || !context.mounted) return;

    try {
      final manager = ref.read(connectionManagerProvider);
      final conn = await manager.connect(config);
      ref.read(tabProvider.notifier).addTerminalTab(conn);
    } on AuthError catch (e) {
      if (context.mounted) Toast.show(context, message: 'Authentication failed: ${e.message}', level: ToastLevel.error);
    } on ConnectError catch (e) {
      if (context.mounted) Toast.show(context, message: 'Connection failed: ${e.message}', level: ToastLevel.error);
    } catch (e) {
      if (context.mounted) Toast.show(context, message: 'Error: $e', level: ToastLevel.error);
    }
  }
}
