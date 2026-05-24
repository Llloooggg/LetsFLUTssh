import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_step.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/terminal/connection_progress.dart';
import 'package:letsflutssh/widgets/terminal/readonly_terminal_grid_view.dart';

import '../helpers/frb_bootstrap.dart';

void main() {
  // ConnectionProgress opens a Rust TerminalReplay in initState, so these
  // widget tests need the native library loaded.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await requireFrbLoaded();
  });

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

  Widget host(Connection conn, {double? fontSize, String? channelLabel}) =>
      MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: ConnectionProgress(
            connection: conn,
            fontSize: fontSize ?? 14.0,
            channelLabel: channelLabel,
          ),
        ),
      );

  group('ConnectionProgress', () {
    testWidgets('renders the read-only grid view', (tester) async {
      await tester.pumpWidget(host(makeConnection()));
      expect(find.byType(ReadOnlyTerminalGridView), findsOneWidget);
    });

    testWidgets('defaults fontSize to 14', (tester) async {
      await tester.pumpWidget(host(makeConnection()));
      final widget = tester.widget<ConnectionProgress>(
        find.byType(ConnectionProgress),
      );
      expect(widget.fontSize, 14.0);
    });

    testWidgets('passes custom fontSize to the grid view', (tester) async {
      await tester.pumpWidget(host(makeConnection(), fontSize: 18));
      final view = tester.widget<ReadOnlyTerminalGridView>(
        find.byType(ReadOnlyTerminalGridView),
      );
      expect(view.fontSize, 18.0);
    });

    testWidgets('accepts channelLabel parameter', (tester) async {
      await tester.pumpWidget(
        host(makeConnection(), channelLabel: 'Opening SFTP…'),
      );
      final widget = tester.widget<ConnectionProgress>(
        find.byType(ConnectionProgress),
      );
      expect(widget.channelLabel, 'Opening SFTP…');
    });

    testWidgets('addStep feeds the engine without throwing', (tester) async {
      final key = GlobalKey<ConnectionProgressState>();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: ConnectionProgress(key: key, connection: makeConnection()),
          ),
        ),
      );

      key.currentState!.addStep(
        const ConnectionStep(
          phase: ConnectionPhase.openChannel,
          status: StepStatus.inProgress,
          detail: 'Opening SFTP channel',
        ),
      );
      await tester.pump();
    });

    testWidgets('writeError feeds the engine without throwing', (tester) async {
      final key = GlobalKey<ConnectionProgressState>();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: ConnectionProgress(key: key, connection: makeConnection()),
          ),
        ),
      );

      key.currentState!.writeError('Connection refused');
      await tester.pump();
    });

    testWidgets('disposes cleanly', (tester) async {
      await tester.pumpWidget(host(makeConnection()));
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
    });
  });
}
