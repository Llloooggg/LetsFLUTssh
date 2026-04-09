import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_step.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/connection_progress.dart';
import 'package:letsflutssh/widgets/readonly_terminal_view.dart';

void main() {
  Connection makeConnection({
    SSHConnectionState state = SSHConnectionState.connecting,
  }) {
    return Connection(
      id: 'c1',
      label: 'Test Server',
      sshConfig: const SSHConfig(
        server: ServerAddress(host: '10.0.0.1', user: 'root'),
      ),
      state: state,
    );
  }

  group('ConnectionProgress', () {
    testWidgets('renders ReadOnlyTerminalView', (tester) async {
      final conn = makeConnection();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(body: ConnectionProgress(connection: conn)),
        ),
      );

      expect(find.byType(ReadOnlyTerminalView), findsOneWidget);
    });

    testWidgets('uses default fontSize of 14', (tester) async {
      final conn = makeConnection();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(body: ConnectionProgress(connection: conn)),
        ),
      );

      final widget = tester.widget<ConnectionProgress>(
        find.byType(ConnectionProgress),
      );
      expect(widget.fontSize, 14.0);
    });

    testWidgets('passes custom fontSize to ReadOnlyTerminalView', (
      tester,
    ) async {
      final conn = makeConnection();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: ConnectionProgress(connection: conn, fontSize: 18),
          ),
        ),
      );

      final termView = tester.widget<ReadOnlyTerminalView>(
        find.byType(ReadOnlyTerminalView),
      );
      expect(termView.fontSize, 18.0);
    });

    testWidgets('accepts channelLabel parameter', (tester) async {
      final conn = makeConnection();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: ConnectionProgress(
              connection: conn,
              channelLabel: 'Opening SFTP…',
            ),
          ),
        ),
      );

      final widget = tester.widget<ConnectionProgress>(
        find.byType(ConnectionProgress),
      );
      expect(widget.channelLabel, 'Opening SFTP…');
    });

    testWidgets('addStep does not throw', (tester) async {
      final conn = makeConnection();
      final key = GlobalKey<ConnectionProgressState>();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: ConnectionProgress(key: key, connection: conn),
          ),
        ),
      );

      // addStep should not throw
      key.currentState!.addStep(
        const ConnectionStep(
          phase: ConnectionPhase.openChannel,
          status: StepStatus.inProgress,
          detail: 'Opening SFTP channel',
        ),
      );
      await tester.pump();
    });

    testWidgets('writeError does not throw', (tester) async {
      final conn = makeConnection();
      final key = GlobalKey<ConnectionProgressState>();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: ConnectionProgress(key: key, connection: conn),
          ),
        ),
      );

      // writeError should not throw
      key.currentState!.writeError('Connection refused');
      await tester.pump();
    });

    testWidgets('disposes cleanly', (tester) async {
      final conn = makeConnection();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(body: ConnectionProgress(connection: conn)),
        ),
      );

      // Replacing widget should trigger dispose without errors
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
    });
  });
}
