import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/global_error_dialog.dart';
import 'package:letsflutssh/utils/logger.dart';

void main() {
  // The crash-boundary dialog is the last thing a user sees before the
  // app either recovers or they have to file a bug. The contract pinned
  // here:
  //   1. Shows the error runtime-type so support traces can correlate.
  //   2. When routine logging is off, offers a one-tap "Enable Logging"
  //      action — the "oh no something broke, now what" path relies on
  //      the full trace being captured for the *next* recurrence.
  //   3. Both action buttons dismiss cleanly.
  //
  // All four cases below pump a minimal MaterialApp that carries the
  // error boundary's contract — state from one test does not leak into
  // the next because AppLogger's enabled flag is explicitly restored in
  // tearDown.

  late bool initialLoggingEnabled;

  setUp(() {
    initialLoggingEnabled = AppLogger.instance.enabled;
  });

  tearDown(() {
    AppLogger.instance.setEnabled(initialLoggingEnabled);
  });

  Future<BuildContext> pumpAndCapture(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) {
            captured = ctx;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('renders the unexpected-error title + runtime-type line', (
    tester,
  ) async {
    final ctx = await pumpAndCapture(tester);
    showGlobalErrorDialog(ctx, const FormatException('oops'));
    await tester.pumpAndSettle();

    expect(find.text('Unexpected Error'), findsOneWidget);
    expect(find.textContaining('Error: FormatException'), findsOneWidget);
    expect(
      find.text('An unexpected error occurred. The app will continue running.'),
      findsOneWidget,
    );
  });

  testWidgets('shows the Enable Logging button only when logging is off', (
    tester,
  ) async {
    AppLogger.instance.setEnabled(false);
    final ctx = await pumpAndCapture(tester);
    showGlobalErrorDialog(ctx, StateError('boom'));
    await tester.pumpAndSettle();

    // Routine logging is off so the user has never seen a log line on
    // disk for this error — surface the one-tap enable path.
    expect(find.text('Enable Logging'), findsOneWidget);
    expect(
      find.text('Enable logging in Settings to save error details.'),
      findsOneWidget,
    );
  });

  testWidgets('hides the Enable Logging button when logging is already on', (
    tester,
  ) async {
    AppLogger.instance.setEnabled(true);
    final ctx = await pumpAndCapture(tester);
    showGlobalErrorDialog(ctx, Exception('x'));
    await tester.pumpAndSettle();

    // Logging already active — no nag, just the primary OK action.
    expect(find.text('Enable Logging'), findsNothing);
    expect(
      find.text('Full details have been saved to the log file.'),
      findsOneWidget,
    );
  });

  testWidgets('Enable Logging tap flips the flag and dismisses the dialog', (
    tester,
  ) async {
    AppLogger.instance.setEnabled(false);
    final ctx = await pumpAndCapture(tester);
    showGlobalErrorDialog(ctx, Exception('x'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enable Logging'));
    await tester.pumpAndSettle();

    expect(AppLogger.instance.enabled, isTrue);
    // After the tap the dialog should be gone and the success toast
    // lands on screen.
    expect(find.text('Unexpected Error'), findsNothing);
    expect(
      find.text('Logging enabled — errors will be saved to log file'),
      findsOneWidget,
    );
    // Pump past the toast auto-dismiss timer so the test binding does
    // not report it as "a Timer is still pending after teardown".
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('OK tap dismisses without touching the logging flag', (
    tester,
  ) async {
    AppLogger.instance.setEnabled(true);
    final ctx = await pumpAndCapture(tester);
    showGlobalErrorDialog(ctx, Exception('x'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Unexpected Error'), findsNothing);
    expect(AppLogger.instance.enabled, isTrue);
  });
}
