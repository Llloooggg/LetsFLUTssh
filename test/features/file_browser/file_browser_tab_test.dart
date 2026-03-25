import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/transfer/transfer_manager.dart';
import 'package:letsflutssh/features/file_browser/file_browser_tab.dart';
import 'package:letsflutssh/providers/transfer_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  late TransferManager manager;

  setUp(() {
    manager = TransferManager();
  });

  tearDown(() {
    manager.dispose();
  });

  group('FileBrowserTab', () {
    testWidgets('shows error when SFTP init fails (no SSH connection)', (tester) async {
      final conn = Connection(
        id: 'test-1',
        label: 'Test Server',
        sshConfig: const SSHConfig(host: 'example.com', user: 'root'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: FileBrowserTab(connection: conn),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show error state since sshConnection is null
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('Failed to initialize SFTP'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('error message contains relevant context', (tester) async {
      final conn = Connection(
        id: 'test-2',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: FileBrowserTab(connection: conn),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error text should mention SSH connection
      expect(find.textContaining('SSH connection not available'), findsOneWidget);
    });

    testWidgets('Retry button re-attempts SFTP init', (tester) async {
      final conn = Connection(
        id: 'test-3',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: FileBrowserTab(connection: conn),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error state should be showing
      expect(find.text('Retry'), findsOneWidget);

      // Tap Retry — triggers re-init (which will fail again since no SSH)
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // Back to error state after retry fails
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('Retry button is a FilledButton.tonal', (tester) async {
      final conn = Connection(
        id: 'test-4',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transferManagerProvider.overrideWithValue(manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: FileBrowserTab(connection: conn),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsOneWidget);
    });
  });
}
