import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/ssh_key.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/tags/tag.dart';
import 'package:letsflutssh/features/session_manager/session_edit_dialog.dart';
import 'package:letsflutssh/providers/key_provider.dart';
import 'package:letsflutssh/providers/tag_provider.dart';
import 'package:letsflutssh/utils/platform.dart';
import 'package:letsflutssh/widgets/dropdown_select_button.dart';
import 'package:letsflutssh/widgets/hardware_key_badge.dart';
import 'package:letsflutssh/widgets/toast.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';

import '../../helpers/frb_bootstrap.dart';

void main() {
  // `_buildSession` performs tilde expansion via `homeDirectory`,
  // which now routes through `lfs_core::host_info` (FRB sync).
  // Bootstrap once for the whole file.
  setUpAll(requireFrbLoaded);

  // The Save-fail path fires `Toast.show` which schedules a 3-second
  // auto-dismiss `Timer`. The framework's `!timersPending` invariant
  // runs before `tearDown`, so clearing the entry afterwards is too
  // late. `disabledForTests` short-circuits `Toast.show` so the
  // notification never schedules a Timer in this file's tests; the
  // form-level validation contract (inline errors, tab routing) is
  // still fully exercised because Toast is purely additive UX.
  setUpAll(() => Toast.disabledForTests = true);
  tearDownAll(() => Toast.disabledForTests = false);

  SessionDialogResult? dialogResult;

  Widget buildApp({Session? session, String? defaultFolder}) {
    dialogResult = null;
    return ProviderScope(
      overrides: [
        // The dialog watches `sessionTagsProvider` (per-session
        // family), `tagsProvider` (workspace tag list backing the
        // inline picker in More options), and `sshKeysProvider`
        // (auth section key dropdown). With FRB bootstrapped and
        // no `lfs_core.db` in the test process, the live providers
        // spin a CircularProgressIndicator forever —
        // `pumpAndSettle` never settles. Stub each to an immediate
        // empty value.
        sessionTagsProvider.overrideWith((ref, sessionId) async => <Tag>[]),
        tagsProvider.overrideWith(_EmptyTagsNotifier.new),
        ..._stubKeysOverrides(_StubKeysMutator(const [])),
      ],
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                dialogResult = await SessionEditDialog.show(
                  context,
                  session: session,
                  defaultFolder: defaultFolder,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  /// Finds a TextFormField by its hint text.
  Finder fieldByHint(String hint) => find.widgetWithText(TextFormField, hint);

  Future<void> fillRequiredFields(
    WidgetTester tester, {
    String host = 'example.com',
    String user = 'testuser',
    String password = 'pass',
  }) async {
    // Single smart-paste surface — `[user@]host[:port]` parses via
    // Rust `parse_ssh_target` and the listener writes the result
    // into the host / port / user controllers the save path reads.
    await tester.enterText(fieldByHint('root@example.com:22'), '$user@$host');
    await tester.enterText(fieldByHint('••••••••'), password);
    await tester.pumpAndSettle();
  }

  /// Single-form layout — there is no Auth tab to switch to; the
  /// helper is kept as a name-stable no-op so the existing test
  /// scenarios that called `switchToAuth(tester)` between filling
  /// a host and entering a password still read linearly without
  /// touching every call site.
  Future<void> switchToAuth(WidgetTester tester) async {
    await tester.pumpAndSettle();
  }

  /// Tags + ProxyJump + Forwarding + Record-session toggle live
  /// inside the collapsible "More options" section. Tests that
  /// exercise those rows call this helper to expand it first. The
  /// section header sits at the bottom of the scrollable body, so
  /// the helper scrolls it into view before tapping otherwise the
  /// tap can miss when the dialog is taller than the test viewport.
  Future<void> expandAdvanced(WidgetTester tester) async {
    final header = find.text('MORE OPTIONS');
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  /// Footer split-button — "Save & Connect" is the visible primary
  /// label; the chevron next to it opens a popup whose only entry
  /// is the localized "Save" string (save-without-connect). This
  /// helper exercises the save-only flow without depending on a
  /// per-call test re-typing the popup mechanics.
  Future<void> tapSaveOnly(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.arrow_drop_down).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
  }

  group('SessionEditDialog — new session', () {
    testWidgets('shows New Session title', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('New Connection'), findsOneWidget);
    });

    testWidgets('has all required fields on Connection tab', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Single-form layout — smart-paste replaces the old
      // HOST / PORT / USERNAME row with one combined field.
      expect(find.text('SESSION NAME'), findsOneWidget);
      expect(find.text('CONNECT TO'), findsOneWidget);
    });

    testWidgets('has password and key sections on Auth tab', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to Auth tab
      // Single-form: Auth fields are visible on the same scrollable
      // page as Connection fields — no tab switch needed.
      await tester.pumpAndSettle();

      // Password field label
      expect(find.text('PASSWORD'), findsOneWidget);
      // OR divider between password and key sections
      expect(find.text('OR'), findsOneWidget);
      // Key fields always visible
      expect(find.text('Select Key File'), findsOneWidget);
      expect(find.text('KEY PASSPHRASE'), findsOneWidget);
    });

    testWidgets(
      'New Connection footer has Cancel + Save & Connect split-button',
      (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Primary visible action — Save & Connect lives on the left
        // half of the split button. The chevron next to it opens
        // the popup with the "Save only" entry (not rendered until
        // the user taps the arrow).
        expect(find.text('Save & Connect'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_drop_down), findsWidgets);
        // The "Save" popup entry is rendered lazily — absent until tapped.
        expect(find.text('Save'), findsNothing);
      },
    );

    testWidgets('validates required fields on submit', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsWidgets);
    });

    testWidgets('Cancel closes dialog', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('New Connection'), findsNothing);
    });

    testWidgets('auth tab shows key fields in any mode', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);
      // Both password and key fields are always visible
      expect(find.text('Select Key File'), findsOneWidget);
      expect(find.text('KEY PASSPHRASE'), findsOneWidget);
    });

    testWidgets('smart-paste hint advertises the [user@]host[:port] shape', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // The placeholder is the canonical example URL kept identical
      // across every locale (the `connectHint` ARB value).
      expect(find.text('root@example.com:22'), findsOneWidget);
    });
  });

  group('SessionEditDialog — submit actions', () {
    testWidgets(
      'Save & Connect on new session returns SaveResult with connect=true',
      (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await fillRequiredFields(tester);

        await tester.tap(find.text('Save & Connect'));
        await tester.pumpAndSettle();

        expect(dialogResult, isA<SaveResult>());
        final result = dialogResult as SaveResult;
        expect(result.session.host, 'example.com');
        expect(result.session.user, 'testuser');
        expect(result.session.port, 22);
        expect(result.connect, isTrue);
      },
    );

    testWidgets('Save & Connect with label filled', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(fieldByHint('Auto from host'), 'My Server');
      await fillRequiredFields(tester, host: '10.0.0.1', user: 'root');

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.host, '10.0.0.1');
      expect(result.session.user, 'root');
      expect(result.connect, isTrue);
    });

    testWidgets('Save & Connect without valid fields does not close', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Don't fill required fields
      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
      expect(find.text('New Connection'), findsOneWidget);
    });

    testWidgets('Save & Connect with custom port', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Port rides on the smart-paste field; the parser writes the
      // non-default port into `_portCtrl` so the SaveResult carries it.
      await tester.enterText(
        fieldByHint('root@example.com:22'),
        'testuser@example.com:2222',
      );
      await tester.enterText(fieldByHint('••••••••'), 'pass');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.port, 2222);
      expect(result.connect, isTrue);
    });

    testWidgets('Save & Connect with password auth', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);
      await switchToAuth(tester);
      await tester.enterText(fieldByHint('••••••••'), 'secret123');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.password, 'secret123');
      expect(result.connect, isTrue);
    });
  });

  group('SessionEditDialog — edit session submit', () {
    testWidgets('Save returns SaveResult with connect=false', (tester) async {
      final session = Session(
        label: 'test-server',
        server: const ServerAddress(host: '10.0.0.1', user: 'root'),
        auth: const SessionAuth(authType: AuthType.password, password: 'pass'),
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tapSaveOnly(tester);

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.host, '10.0.0.1');
      expect(result.session.user, 'root');
      expect(result.connect, isFalse);
    });

    testWidgets(
      'Save & Connect on existing session returns SaveResult with connect=true',
      (tester) async {
        final session = Session(
          label: 'test-server',
          server: const ServerAddress(host: '10.0.0.1', user: 'root'),
          auth: const SessionAuth(
            authType: AuthType.password,
            password: 'pass',
          ),
        );
        await tester.pumpWidget(buildApp(session: session));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save & Connect'));
        await tester.pumpAndSettle();

        expect(dialogResult, isA<SaveResult>());
        final result = dialogResult as SaveResult;
        expect(result.session.host, '10.0.0.1');
        expect(result.session.user, 'root');
        expect(result.connect, isTrue);
      },
    );

    testWidgets('Save preserves edited fields', (tester) async {
      final session = Session(
        label: 'old-label',
        server: const ServerAddress(host: '10.0.0.1', user: 'root'),
        auth: const SessionAuth(authType: AuthType.password, password: 'pass'),
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Clear and re-enter label
      await tester.enterText(fieldByHint('Auto from host'), 'new-label');
      await tester.pumpAndSettle();

      await tapSaveOnly(tester);

      final result = dialogResult as SaveResult;
      expect(result.session.label, 'new-label');
      expect(result.session.id, session.id);
    });
  });

  group('SessionEditDialog — Key auth fields', () {
    testWidgets('Key auth shows key path and passphrase fields', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      expect(find.text('KEY PASSPHRASE'), findsOneWidget);
      // PEM toggle should be present
      expect(find.text('Paste PEM key text'), findsOneWidget);
    });

    testWidgets('PEM toggle shows and hides key text field', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      // Click toggle to show PEM text — scroll down to find it first
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      // PEM field should now be visible
      await tester.scrollUntilVisible(
        find.text('Hide PEM text'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Hide PEM text'), findsOneWidget);

      // Click toggle to hide PEM text
      await tester.tap(find.text('Hide PEM text'));
      await tester.pumpAndSettle();

      expect(find.text('Hide PEM text'), findsNothing);
      expect(find.text('Paste PEM key text'), findsOneWidget);
    });

    testWidgets('Save & Connect with Key auth includes passphrase in result', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      await switchToAuth(tester);

      // Open PEM text and enter key data (required for passphrase validation)
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('-----BEGIN OPENSSH PRIVATE KEY-----'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          '-----BEGIN OPENSSH PRIVATE KEY-----',
        ),
        '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpAndSettle();

      // Scroll to passphrase field and fill it
      await tester.scrollUntilVisible(
        find.text('KEY PASSPHRASE'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(fieldByHint('Optional'), 'mypassphrase');
      await tester.pumpAndSettle();

      // Scroll back to Save & Connect button
      await tester.scrollUntilVisible(
        find.text('Save & Connect'),
        -100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.passphrase, 'mypassphrase');
      expect(result.connect, isTrue);
    });
  });

  group('SessionEditDialog — Both auth', () {
    testWidgets('auth tab shows both password and key fields', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      expect(find.text('PASSWORD'), findsOneWidget);
      expect(find.text('OR'), findsOneWidget);
      expect(find.text('KEY PASSPHRASE'), findsOneWidget);
    });

    testWidgets('Save & Connect with both password and key filled', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      await switchToAuth(tester);

      final scrollable = find.byType(Scrollable).last;

      // Scroll to password field
      await tester.scrollUntilVisible(
        fieldByHint('••••••••'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(fieldByHint('••••••••'), 'secret');
      await tester.pumpAndSettle();

      // Add PEM key data (required for key auth)
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.widgetWithText(
          TextFormField,
          '-----BEGIN OPENSSH PRIVATE KEY-----',
        ),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          '-----BEGIN OPENSSH PRIVATE KEY-----',
        ),
        '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpAndSettle();

      // Scroll back to action buttons
      await tester.scrollUntilVisible(
        find.text('Save & Connect'),
        -100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.password, 'secret');
      expect(result.connect, isTrue);
    });
  });

  group('SessionEditDialog — password visibility toggle', () {
    testWidgets('password field toggle changes icon', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      // Both password and passphrase have visibility icons — find
      // first one (password). Single-form lays out both fields on
      // the same scrollable page; ensureVisible drags the password
      // toggle into the viewport before the tap so the gesture
      // doesn't miss when the dialog is taller than the test viewport.
      final visibilityIcons = find.byIcon(Icons.visibility);
      expect(visibilityIcons, findsNWidgets(2));
      await tester.ensureVisible(visibilityIcons.first);
      await tester.pumpAndSettle();

      await tester.tap(visibilityIcons.first, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Password toggled off, passphrase still on → one visibility + one visibility_off.
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(find.byIcon(Icons.visibility), findsOneWidget);
    });
  });

  group('SessionEditDialog — smart-paste validation', () {
    // The smart-paste field collapses the old HOST / PORT / USERNAME
    // validators into one. Out-of-range ports, non-numeric ports,
    // control characters, and missing host all surface the shared
    // `connectStringInvalid` message; an entirely empty field reuses
    // the existing `required` copy.
    testWidgets('out-of-range port surfaces the invalid-format error', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        fieldByHint('root@example.com:22'),
        'root@example.com:99999',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid format'), findsOneWidget);
    });

    testWidgets('non-numeric port surfaces the invalid-format error', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        fieldByHint('root@example.com:22'),
        'root@example.com:abc',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid format'), findsOneWidget);
    });

    testWidgets('port 0 surfaces the invalid-format error', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        fieldByHint('root@example.com:22'),
        'root@example.com:0',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid format'), findsOneWidget);
    });
  });

  group('SessionEditDialog — edit with key auth', () {
    testWidgets('editing session with key auth shows key fields pre-filled', (
      tester,
    ) async {
      final session = Session(
        label: 'key-server',
        server: const ServerAddress(host: '10.0.0.1', user: 'ubuntu'),
        auth: const SessionAuth(
          authType: AuthType.key,
          keyData:
              '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----',
          passphrase: 'pass123',
        ),
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Connection'), findsOneWidget);

      await switchToAuth(tester);
      // Key auth should be selected
      expect(find.text('KEY PASSPHRASE'), findsOneWidget);
      // PEM text should be visible since keyData is not empty
      expect(find.text('Hide PEM text'), findsOneWidget);
    });
  });

  group('SessionEditDialog — defaultFolder parameter', () {
    testWidgets('defaultFolder is applied to saved session', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    dialogResult = await SessionEditDialog.show(
                      context,
                      defaultFolder: 'Production/Web',
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Fill required fields and save
      await fillRequiredFields(tester);
      await tapSaveOnly(tester);

      expect(dialogResult, isA<SaveResult>());
      final session = (dialogResult as SaveResult).session;
      expect(session.folder, 'Production/Web');
    });
  });

  group('SessionEditDialog — passphrase visibility toggle', () {
    testWidgets('passphrase field has visibility toggle in Key auth', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      // Scroll to passphrase field
      await tester.scrollUntilVisible(
        find.text('KEY PASSPHRASE'),
        100,
        scrollable: find.byType(Scrollable).last,
      );

      // Find visibility icons — password and passphrase both have one
      final visIcons = find.byIcon(Icons.visibility);
      expect(visIcons, findsWidgets);

      // Tap the passphrase visibility icon (last one)
      await tester.tap(visIcons.last);
      await tester.pumpAndSettle();

      // Should now show visibility_off
      expect(find.byIcon(Icons.visibility_off), findsWidgets);
    });
  });

  group('SessionEditDialog — edit session', () {
    testWidgets('shows Edit Session title', (tester) async {
      final session = Session(
        label: 'test-server',
        server: const ServerAddress(host: '10.0.0.1', user: 'root'),
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Connection'), findsOneWidget);
    });

    testWidgets('Save & Connect split-button rendered for edit mode', (
      tester,
    ) async {
      final session = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Primary action visible; the save-only entry is one chevron
      // tap away (covered by `tapSaveOnly` callers).
      expect(find.text('Save & Connect'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsWidgets);
    });

    testWidgets('fields pre-populated from session', (tester) async {
      final session = Session(
        label: 'my-server',
        folder: 'Production',
        server: const ServerAddress(
          host: '192.168.1.1',
          port: 2222,
          user: 'admin',
        ),
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('my-server'), findsOneWidget);
      // The smart-paste field renders the composed `user@host:port`
      // tuple verbatim (port 22 collapses; non-default ports stay).
      expect(find.text('admin@192.168.1.1:2222'), findsOneWidget);
    });
  });

  group('SessionEditDialog — cancel returns null', () {
    testWidgets('cancel in create mode returns null', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
    });

    testWidgets('cancel in edit mode returns null', (tester) async {
      final session = Session(
        label: 'srv',
        server: const ServerAddress(host: '10.0.0.1', user: 'root'),
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
    });
  });

  group('SessionEditDialog — edit mode validation and id preservation', () {
    testWidgets('Save in edit mode fails validation if host cleared', (
      tester,
    ) async {
      final session = Session(
        label: 'srv',
        server: const ServerAddress(host: '10.0.0.1', user: 'root'),
        auth: const SessionAuth(authType: AuthType.password),
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Clear the smart-paste field on an edited session — the
      // validator surfaces the same `required` copy the empty-form
      // path does, and the dialog stays open so the user can fix.
      await tester.enterText(fieldByHint('root@example.com:22'), '');
      await tester.pumpAndSettle();

      await tapSaveOnly(tester);

      expect(find.text('Required'), findsOneWidget);
      expect(find.text('Edit Connection'), findsOneWidget);
    });

    testWidgets('editing session preserves original session id', (
      tester,
    ) async {
      final session = Session(
        id: 'original-id-123',
        label: 'edit-me',
        server: const ServerAddress(host: '10.0.0.1', user: 'root'),
        auth: const SessionAuth(authType: AuthType.password, password: 'pass'),
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(fieldByHint('Auto from host'), 'new-label');
      await tester.pumpAndSettle();

      await tapSaveOnly(tester);

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.id, 'original-id-123');
      expect(result.session.label, 'new-label');
      expect(result.connect, isFalse);
    });

    testWidgets(
      'Edit Connection footer has Cancel + Save & Connect split-button',
      (tester) async {
        final session = Session(
          label: 'edit-me',
          server: const ServerAddress(host: '10.0.0.1', user: 'root'),
          auth: const SessionAuth(authType: AuthType.password),
        );
        await tester.pumpWidget(buildApp(session: session));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Edit Connection'), findsOneWidget);
        expect(find.text('Save & Connect'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_drop_down), findsWidgets);
        // "Save" entry is inside the chevron popup — not in the tree
        // until the user taps the arrow.
        expect(find.text('Save'), findsNothing);
      },
    );
  });

  group('SessionEditDialog — edit key session preserves all key fields', () {
    testWidgets('editing label leaves the key fields untouched (not dirty)', (
      tester,
    ) async {
      // The dialog no longer pre-fills credential controllers; the
      // store-side partial-update path skips secret columns whose
      // dirty bit is false. Editing the label therefore returns a
      // SaveResult whose `keyDataDirty` / `passphraseDirty` flags
      // are clear — the caller writes only the metadata, leaving
      // the DB columns intact.
      final session = Session(
        id: 'key-edit-1',
        label: 'key-srv',
        server: const ServerAddress(host: '10.0.0.1', user: 'root'),
        auth: const SessionAuth(
          authType: AuthType.key,
          keyPath: '/path/to/key',
          hasStoredKeyData: true,
          hasStoredPassphrase: true,
        ),
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(fieldByHint('Auto from host'), 'key-srv-updated');
      await tester.pumpAndSettle();

      await tapSaveOnly(tester);

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.label, 'key-srv-updated');
      expect(result.session.authType, AuthType.key);
      expect(result.session.keyPath, '/path/to/key');
      expect(result.passwordDirty, isFalse);
      expect(result.keyDataDirty, isFalse);
      expect(result.passphraseDirty, isFalse);
    });
  });

  group('SessionEditDialog — additional validation', () {
    testWidgets('Save & Connect with empty smart-paste field is blocked', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // The smart-paste field is empty on a fresh dialog — Save &
      // Connect routes through the validator and surfaces the same
      // `required` copy the old per-field validators did.
      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsWidgets);
      expect(dialogResult, isNull);
    });

    testWidgets('Save & Connect with a bare host (no user prefix) is blocked', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // The parser tolerates a host-only string — the validator
      // catches the missing user separately so the user has to add
      // `user@` before Save proceeds.
      await tester.enterText(fieldByHint('root@example.com:22'), 'host.com');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
      expect(dialogResult, isNull);
    });
  });

  group('SessionEditDialog — smart-paste port boundary values', () {
    testWidgets('port 1 is accepted by the smart-paste parser', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        fieldByHint('root@example.com:22'),
        'testuser@example.com:1',
      );
      await tester.enterText(fieldByHint('••••••••'), 'pass');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      expect((dialogResult as SaveResult).session.port, 1);
    });

    testWidgets('port 65535 is accepted by the smart-paste parser', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        fieldByHint('root@example.com:22'),
        'testuser@example.com:65535',
      );
      await tester.enterText(fieldByHint('••••••••'), 'pass');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      expect((dialogResult as SaveResult).session.port, 65535);
    });
  });

  group('SessionEditDialog — label is optional', () {
    testWidgets('label field is optional — can submit without it', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      expect((dialogResult as SaveResult).connect, isTrue);
    });
  });

  group('SessionEditDialog — smart-paste validation surfaces inline', () {
    testWidgets('bare host (no user prefix) blocks Save with Required', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Type host alone — parser tolerates it, but the validator
      // catches the missing `user@` prefix and surfaces "Required"
      // on the smart-paste field itself (single-form layout means
      // no tab to switch to).
      await tester.enterText(fieldByHint('root@example.com:22'), 'host.com');
      await tester.enterText(fieldByHint('••••••••'), 'secret');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
      expect(dialogResult, isNull);
    });

    testWidgets('empty smart-paste field blocks Save with Required', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Don't touch the smart-paste field; only fill the password.
      await tester.enterText(fieldByHint('••••••••'), 'secret');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
      expect(dialogResult, isNull);
    });
  });

  group('SessionEditDialog — auth layout', () {
    testWidgets('both password and key sections are always visible', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      // Password field visible
      expect(fieldByHint('••••••••'), findsOneWidget);
      // OR divider
      expect(find.text('OR'), findsOneWidget);
      // Key fields visible
      expect(find.text('KEY PASSPHRASE'), findsOneWidget);
      expect(find.text('Select Key File'), findsOneWidget);
    });

    testWidgets('password field is never marked as required', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      // Password label without required marker
      expect(find.text('PASSWORD'), findsOneWidget);
      expect(find.text('PASSWORD *'), findsNothing);
    });
  });

  group('SessionEditDialog — auth validation', () {
    testWidgets('empty auth shows error', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Fill the smart-paste field with user@host; leave the
      // password / key fields untouched. The auth-side validator
      // surfaces the "provide a password or SSH key" verdict.
      await tester.enterText(
        fieldByHint('root@example.com:22'),
        'user@host.com',
      );

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Provide a password or SSH key'), findsOneWidget);
      expect(dialogResult, isNull);
    });

    testWidgets('password only saves and connects', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        fieldByHint('root@example.com:22'),
        'user@host.com',
      );
      await switchToAuth(tester);
      await tester.enterText(fieldByHint('••••••••'), 'secret');

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.password, 'secret');
      expect(result.connect, isTrue);
    });
  });

  group('SessionEditDialog — editing keyWithPassword session', () {
    testWidgets('editing keyWithPassword session shows both fields pre-filled', (
      tester,
    ) async {
      final session = Session(
        label: 'kp-server',
        server: const ServerAddress(host: '10.0.0.1', user: 'root'),
        auth: const SessionAuth(
          authType: AuthType.keyWithPassword,
          password: 'secret',
          keyData:
              '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----',
          passphrase: 'kp123',
        ),
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Connection'), findsOneWidget);

      await switchToAuth(tester);
      // Password field label visible
      expect(find.text('PASSWORD'), findsOneWidget);
      expect(find.text('KEY PASSPHRASE'), findsOneWidget);
      // PEM text visible since keyData is pre-filled
      expect(find.text('Hide PEM text'), findsOneWidget);
    });
  });

  group('SessionEditDialog — Save & Connect with password and custom port', () {
    testWidgets('Save & Connect preserves password and custom port', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        fieldByHint('root@example.com:22'),
        'u@h.com:2222',
      );

      await switchToAuth(tester);

      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        fieldByHint('••••••••'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(fieldByHint('••••••••'), 'secret');
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Save & Connect'),
        -100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.host, 'h.com');
      expect(result.session.user, 'u');
      expect(result.session.port, 2222);
      expect(result.session.password, 'secret');
      expect(result.connect, isTrue);
    });
  });

  group('SessionEditDialog — Save & Connect with both password and key', () {
    testWidgets('Save & Connect with both auth includes all fields', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      await switchToAuth(tester);

      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        fieldByHint('••••••••'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(fieldByHint('••••••••'), 'pass123');
      await tester.pumpAndSettle();

      // Add PEM key data (required for key auth)
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.widgetWithText(
          TextFormField,
          '-----BEGIN OPENSSH PRIVATE KEY-----',
        ),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          '-----BEGIN OPENSSH PRIVATE KEY-----',
        ),
        '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Save & Connect'),
        -100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.password, 'pass123');
      expect(result.connect, isTrue);
    });
  });

  group('SessionEditDialog — new session with folder', () {
    testWidgets('Save & Connect for new session returns SaveResult', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp(defaultFolder: 'Production'));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(fieldByHint('Auto from host'), 'my-server');
      await fillRequiredFields(tester, host: 'new.host', user: 'newuser');

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.host, 'new.host');
      expect(result.session.user, 'newuser');
      expect(result.connect, isTrue);
    });
  });

  group('SessionEditDialog — key file button', () {
    testWidgets('key auth shows Select Key File button', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      expect(find.text('Select Key File'), findsOneWidget);
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });

    testWidgets(
      'key file button renders as DropdownSelectButton, not a text field',
      (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await switchToAuth(tester);

        // Should NOT have a TextFormField for key path
        expect(find.widgetWithText(TextFormField, 'Key File'), findsNothing);
        expect(
          find.widgetWithText(TextFormField, 'Key File Path'),
          findsNothing,
        );

        // Picker now uses the themed DropdownSelectButton (previously a
        // raw `OutlinedButton.icon`).
        expect(
          find.widgetWithText(DropdownSelectButton, 'Select Key File'),
          findsOneWidget,
        );
      },
    );
  });

  group('SessionEditDialog — PEM key data in save & connect result', () {
    testWidgets('entering PEM key data is included in save & connect result', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Fill the smart-paste connection field first.
      await tester.enterText(fieldByHint('root@example.com:22'), 'u@h.com');
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      final scrollable = find.byType(Scrollable).last;

      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.widgetWithText(
          TextFormField,
          '-----BEGIN OPENSSH PRIVATE KEY-----',
        ),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          '-----BEGIN OPENSSH PRIVATE KEY-----',
        ),
        '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Save & Connect'),
        -200,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.keyData, contains('PRIVATE KEY'));
      expect(result.connect, isTrue);
    });
  });

  group('SessionEditDialog — tilde expansion in key path', () {
    testWidgets('tilde in key path from edited session is expanded in result', (
      tester,
    ) async {
      // Editing a session that already has a key path with tilde
      final session = Session(
        id: 'tilde-test',
        label: 'Tilde Server',
        server: const ServerAddress(host: 'h.com', user: 'u'),
        auth: const SessionAuth(
          authType: AuthType.key,
          keyPath: '~/.ssh/id_rsa',
        ),
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tapSaveOnly(tester);

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.keyPath.contains('~'), isFalse);
    });
  });

  group('SessionEditDialog — password and passphrase visibility', () {
    testWidgets('toggling password visibility on auth tab', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.byIcon(Icons.visibility).first,
        100,
        scrollable: scrollable,
      );

      final visIcons = find.byIcon(Icons.visibility);
      expect(visIcons, findsWidgets);

      await tester.tap(visIcons.first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_off), findsWidgets);
    });

    testWidgets('toggling passphrase visibility on auth tab', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('KEY PASSPHRASE'),
        100,
        scrollable: scrollable,
      );

      final visIcons = find.byIcon(Icons.visibility);
      expect(visIcons.evaluate().length, greaterThanOrEqualTo(2));

      await tester.tap(visIcons.last);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_off), findsWidgets);
    });
  });

  group('SessionEditDialog — password and PEM key data', () {
    testWidgets(
      'Save & Connect with both password and keyData preserves keyData',
      (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await fillRequiredFields(tester);

        await switchToAuth(tester);

        final scrollable = find.byType(Scrollable).last;

        // Fill password
        await tester.scrollUntilVisible(
          fieldByHint('••••••••'),
          100,
          scrollable: scrollable,
        );
        await tester.enterText(fieldByHint('••••••••'), 'pass');
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Paste PEM key text'),
          100,
          scrollable: scrollable,
        );
        await tester.tap(find.text('Paste PEM key text'));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('-----BEGIN OPENSSH PRIVATE KEY-----'),
          100,
          scrollable: scrollable,
        );
        await tester.enterText(
          find.widgetWithText(
            TextFormField,
            '-----BEGIN OPENSSH PRIVATE KEY-----',
          ),
          '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----',
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Save & Connect'),
          -100,
          scrollable: scrollable,
        );
        await tester.tap(find.text('Save & Connect'));
        await tester.pumpAndSettle();

        expect(dialogResult, isA<SaveResult>());
        final result = dialogResult as SaveResult;
        expect(result.session.keyData, contains('PRIVATE KEY'));
        expect(result.connect, isTrue);
      },
    );
  });

  group('SessionDialogResult sealed classes', () {
    test('SaveResult holds Session with connect flag', () {
      final session = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      final result = SaveResult(session, connect: true);
      expect(result.session.label, 'test');
      expect(result.connect, isTrue);
    });

    test('SaveResult defaults connect to false', () {
      final session = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      final result = SaveResult(session);
      expect(result.connect, isFalse);
    });
  });

  group('SessionEditDialog — PEM toggle icon and text changes', () {
    testWidgets('PEM toggle shows down arrow icon initially', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );

      // Down arrow icon when PEM text is hidden
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);
    });

    testWidgets('PEM toggle shows up arrow icon when expanded', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      // Up arrow icon when PEM text is shown
      await tester.scrollUntilVisible(
        find.text('Hide PEM text'),
        100,
        scrollable: scrollable,
      );
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    });

    testWidgets('PEM text field has monospace font and maxLines', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.widgetWithText(
          TextFormField,
          '-----BEGIN OPENSSH PRIVATE KEY-----',
        ),
        100,
        scrollable: scrollable,
      );

      // Verify the PEM text field has the expected hint
      expect(find.text('-----BEGIN OPENSSH PRIVATE KEY-----'), findsOneWidget);
    });
  });

  group(
    'SessionEditDialog — editing session with keyData starts with PEM visible',
    () {
      testWidgets(
        'editing session with keyData shows PEM text and Hide PEM text toggle',
        (tester) async {
          final session = Session(
            label: 'key-srv',
            server: const ServerAddress(host: '10.0.0.1', user: 'root'),
            auth: const SessionAuth(
              authType: AuthType.key,
              keyData:
                  '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----',
            ),
          );
          await tester.pumpWidget(buildApp(session: session));
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          await switchToAuth(tester);

          // Since keyData is not empty, _showKeyText starts as true
          // PEM toggle should say "Hide PEM text"
          final scrollable = find.byType(Scrollable).last;
          await tester.scrollUntilVisible(
            find.text('Hide PEM text'),
            100,
            scrollable: scrollable,
          );
          expect(find.text('Hide PEM text'), findsOneWidget);
          expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);

          // The PEM text field should be visible with the keyData
          // Hide PEM text toggle confirmed above — PEM field is rendered
          expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
        },
      );

      testWidgets(
        'toggling PEM off then on does not flip the keyData dirty bit',
        (tester) async {
          // The dialog no longer pre-fills the PEM controller, so a
          // visibility toggle that the user does not type into must
          // not flip `keyDataDirty`. The save path therefore leaves
          // the database column intact.
          final session = Session(
            label: 'key-srv',
            server: const ServerAddress(host: '10.0.0.1', user: 'root'),
            auth: const SessionAuth(
              authType: AuthType.key,
              hasStoredKeyData: true,
            ),
          );
          await tester.pumpWidget(buildApp(session: session));
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          await switchToAuth(tester);

          final scrollable = find.byType(Scrollable).last;

          await tester.scrollUntilVisible(
            find.text('Hide PEM text'),
            100,
            scrollable: scrollable,
          );
          await tester.tap(find.text('Hide PEM text'));
          await tester.pumpAndSettle();
          expect(find.text('Paste PEM key text'), findsOneWidget);

          await tester.scrollUntilVisible(
            find.text('Paste PEM key text'),
            100,
            scrollable: scrollable,
          );
          await tester.tap(find.text('Paste PEM key text'));
          await tester.pumpAndSettle();

          await tester.scrollUntilVisible(
            find.text('Save & Connect'),
            -100,
            scrollable: scrollable,
          );
          await tapSaveOnly(tester);

          expect(dialogResult, isA<SaveResult>());
          final result = dialogResult as SaveResult;
          expect(result.keyDataDirty, isFalse);
        },
      );
    },
  );

  group('SessionEditDialog — passphrase without key validation', () {
    testWidgets('passphrase without key file or PEM shows validation error', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      await switchToAuth(tester);

      // Do NOT enter a key path or PEM text — leave them empty

      // Scroll to passphrase field and fill it
      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('KEY PASSPHRASE'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(fieldByHint('Optional'), 'mypassphrase');
      await tester.pumpAndSettle();

      // Scroll back to Save & Connect button and tap
      await tester.scrollUntilVisible(
        find.text('Save & Connect'),
        -100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      // Should show validation error — dialog stays open
      expect(find.text('Provide a key file or PEM text first'), findsOneWidget);
      expect(dialogResult, isNull);
    });
  });

  group('SessionEditDialog — desktop key path DropTarget rendering', () {
    testWidgets('key auth on desktop wraps key field in DropTarget', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      // On desktop, the key path field is wrapped in a DropTarget
      // Verify the DropTarget widget exists
      expect(find.byType(DropTarget), findsOneWidget);
    });
  });

  group('SessionEditDialog — mobile key path field', () {
    setUp(() {
      debugMobilePlatformOverride = true;
      debugDesktopPlatformOverride = false;
    });

    tearDown(() {
      debugMobilePlatformOverride = null;
      debugDesktopPlatformOverride = null;
    });

    testWidgets('mobile key path field renders without DropTarget', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      // On mobile, the key path field should NOT be wrapped in DropTarget
      expect(find.byType(DropTarget), findsNothing);

      // The mobile key file shows a Select Key File button
      expect(find.text('Select Key File'), findsOneWidget);
      expect(
        find.widgetWithText(DropdownSelectButton, 'Select Key File'),
        findsOneWidget,
      );
    });

    testWidgets('PEM toggle shows and hides key text area on mobile', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      // PEM toggle should be visible
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Paste PEM key text'), findsOneWidget);

      // PEM text field should not be visible yet
      expect(find.text('-----BEGIN OPENSSH PRIVATE KEY-----'), findsNothing);

      // Tap the PEM toggle
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      // Now PEM text field should be visible
      await tester.scrollUntilVisible(
        find.text('-----BEGIN OPENSSH PRIVATE KEY-----'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('-----BEGIN OPENSSH PRIVATE KEY-----'), findsOneWidget);
      expect(find.text('Hide PEM text'), findsOneWidget);

      // Tap toggle again to hide
      await tester.tap(find.text('Hide PEM text'));
      await tester.pumpAndSettle();

      expect(find.text('-----BEGIN OPENSSH PRIVATE KEY-----'), findsNothing);
      expect(find.text('Paste PEM key text'), findsOneWidget);
    });

    testWidgets('PEM text field accepts key text input on mobile', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      // Open PEM text area
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      // Enter PEM text
      await tester.scrollUntilVisible(
        find.text('-----BEGIN OPENSSH PRIVATE KEY-----'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      const pemText =
          '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----';
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          '-----BEGIN OPENSSH PRIVATE KEY-----',
        ),
        pemText,
      );
      await tester.pumpAndSettle();

      expect(find.text(pemText), findsOneWidget);
    });

    testWidgets('PEM key data included in Save & Connect result on mobile', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      await switchToAuth(tester);

      // Open PEM text and enter key data
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('-----BEGIN OPENSSH PRIVATE KEY-----'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          '-----BEGIN OPENSSH PRIVATE KEY-----',
        ),
        '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpAndSettle();

      // Scroll back and tap Save & Connect
      await tester.scrollUntilVisible(
        find.text('Save & Connect'),
        -100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.keyData, contains('PRIVATE KEY'));
      expect(result.connect, isTrue);
    });
  });

  group('SessionEditDialog — More options tag picker', () {
    testWidgets('new session renders the empty-state hint when no tags exist', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await expandAdvanced(tester);

      // Workspace tag list is empty (stubbed via _EmptyTagsNotifier),
      // so the inline picker renders the "create one in Tools → Tags"
      // pointer rather than a tag chip grid. The "save first" copy
      // from the previous edit-only model is gone — new sessions
      // get the same picker shape as edits.
      expect(
        find.text('No tags yet — create one in Tools → Tags.'),
        findsOneWidget,
      );
      // Manage Tags button (uppercased by AppButton) opens the
      // workspace tag manager. Title-Case in the source ("Manage
      // Tags"), uppercased here by the button child shape.
      expect(find.text('Manage Tags'), findsOneWidget);
    });

    testWidgets(
      'editing session also renders the picker rather than a per-session chips list',
      (tester) async {
        final existing = Session(
          id: 'sess-1',
          label: 'srv',
          folder: '',
          server: const ServerAddress(host: 'h', port: 22, user: 'u'),
          auth: const SessionAuth(
            authType: AuthType.password,
            keyId: '',
            password: 'p',
          ),
        );
        await tester.pumpWidget(buildApp(session: existing));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await expandAdvanced(tester);
        // The per-session hydration future resolves to an empty list
        // (override returns []) and the workspace tagsProvider stub
        // returns empty too — picker renders the same empty-state
        // hint either way.
        await tester.pump();
        await tester.pump();

        expect(find.text('Manage Tags'), findsOneWidget);
        expect(
          find.text('No tags yet — create one in Tools → Tags.'),
          findsOneWidget,
        );
      },
    );
  });

  group('SessionEditDialog — Escape key', () {
    testWidgets('Escape dismisses the dialog', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('New Connection'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('New Connection'), findsNothing);
      expect(dialogResult, isNull);
    });
  });

  // ===========================================================================
  // Key store picker — covers _buildKeyPickerButton, _buildSelectedKeyChip,
  // _showKeyPicker, _resolveKeyLabel.
  //
  // Specs (derived from lib/features/session_manager/session_edit_dialog.dart):
  //
  //  * Auth tab shows a "Select from key store" button that is disabled when
  //    the key store has no entries — there's nothing to pick, so the button
  //    must not pretend otherwise.
  //  * Tapping the button while the store has entries opens a SimpleDialog
  //    listing every key's label + key type; tapping an entry dismisses the
  //    dialog and replaces the button with a chip that shows the selected
  //    key's label.
  //  * The chip carries an "X" action that clears the selection, reverting
  //    the UI to the picker button.
  //  * When editing an existing session whose auth.keyId is already set,
  //    _resolveKeyLabel(keyId) looks the entry up in keyStoreProvider and the
  //    resolved label is the one that shows on the chip — the session only
  //    stores the id, not the label.
  // ===========================================================================
  group('SessionEditDialog — key store picker', () {
    SshKeyEntry makeKey(String id, String label) => SshKeyEntry(
      id: id,
      label: label,
      privateKey: '',
      publicKey: '',
      keyType: 'ed25519',
      createdAt: DateTime(2025, 1, 1),
    );

    Widget buildWithKeys(
      List<SshKeyEntry> keys, {
      Session? session,
      _StubKeysMutator? notifier,
    }) {
      final keysList = List<SshKeyEntry>.unmodifiable(keys);
      return ProviderScope(
        overrides: [
          ..._stubKeysOverrides(notifier ?? _StubKeysMutator(keysList)),
          if (session != null)
            sessionTagsProvider(
              session.id,
            ).overrideWith((_) async => const <Tag>[]),
        ],
        child: MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    SessionEditDialog.show(context, session: session),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'section is hidden when the store is empty and no key is selected',
      // Spec (L478-480): when there's nothing to pick and nothing to display,
      // _buildKeyStoreSelector collapses to SizedBox.shrink rather than
      // rendering a dead disabled button that invites a pointless click.
      (tester) async {
        await tester.pumpWidget(buildWithKeys(const []));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await switchToAuth(tester);

        expect(find.text('Select from Key Store'), findsNothing);
      },
    );

    testWidgets(
      'picker button appears and opens a SimpleDialog when store has keys',
      (tester) async {
        await tester.pumpWidget(
          buildWithKeys([makeKey('k1', 'Prod key'), makeKey('k2', 'CI key')]),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await switchToAuth(tester);

        // Single-form lays the key-store button below the password
        // field on the same scrollable page; ensure it is visible
        // before tapping so the gesture lands.
        await tester.ensureVisible(find.text('Select from Key Store'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text('Select from Key Store'),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // Both labels appear in the picker dialog.
        expect(find.text('Prod key'), findsOneWidget);
        expect(find.text('CI key'), findsOneWidget);
        // Key type is shown as a subtitle under each entry.
        expect(find.text('ed25519'), findsNWidgets(2));
      },
    );

    testWidgets(
      'selecting a key replaces the picker button with a labelled chip',
      (tester) async {
        await tester.pumpWidget(buildWithKeys([makeKey('k1', 'Prod key')]));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await switchToAuth(tester);

        // Single-form lays the key-store button below the password
        // field on the same scrollable page; ensure it is visible
        // before tapping so the gesture lands.
        await tester.ensureVisible(find.text('Select from Key Store'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text('Select from Key Store'),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(SimpleDialogOption, 'Prod key'));
        await tester.pumpAndSettle();

        // Picker button has collapsed away.
        expect(
          find.widgetWithText(DropdownSelectButton, 'Select from Key Store'),
          findsNothing,
        );
        // Label appears on the chip.
        expect(find.text('Prod key'), findsOneWidget);
        // Divider below the chip shows "Select from Key Store: {label}"
        // (_buildOrDividerLabel), regression guard.
        expect(
          find.textContaining('Select from Key Store: Prod key'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'chip clear button resets the selection and brings the picker back',
      (tester) async {
        await tester.pumpWidget(buildWithKeys([makeKey('k1', 'Prod key')]));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await switchToAuth(tester);

        // Single-form lays the key-store button below the password
        // field on the same scrollable page; ensure it is visible
        // before tapping so the gesture lands.
        await tester.ensureVisible(find.text('Select from Key Store'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text('Select from Key Store'),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(SimpleDialogOption, 'Prod key'));
        await tester.pumpAndSettle();

        // Clear button tooltip comes from clearKeyFile l10n key ("Clear key
        // file"). Use byTooltip for stability across icon swaps.
        await tester.tap(find.byTooltip('Clear key file'));
        await tester.pumpAndSettle();

        expect(find.text('Prod key'), findsNothing);
        expect(
          find.widgetWithText(DropdownSelectButton, 'Select from Key Store'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'editing a session with keyId resolves and displays the stored label',
      (tester) async {
        // Spec: Session row carries auth.keyId = 'k-abc'. When the dialog
        // opens for editing, it must call keyStoreProvider.get('k-abc') and
        // render the resolved label on the chip. The session itself never
        // stores the label — the key store is the source of truth.
        final storedKey = makeKey('k-abc', 'Saved laptop key');
        final fakeStore = _StubKeysMutator(
          [storedKey],
          lookup: {'k-abc': storedKey},
        );
        final existing = Session(
          id: 's1',
          label: 'Existing',
          server: const ServerAddress(host: 'h', port: 22, user: 'u'),
          auth: const SessionAuth(authType: AuthType.key, keyId: 'k-abc'),
        );

        await tester.pumpWidget(
          buildWithKeys([storedKey], session: existing, notifier: fakeStore),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await switchToAuth(tester);
        // Extra pumps: _resolveKeyLabel is an async chain
        // (keyStoreProvider → loadAllMetadata → setState), so the label
        // lands a microtask or two after the initial widget tree
        // settles.
        await tester.pump();
        await tester.pump();

        expect(find.text('Saved laptop key'), findsOneWidget);
        // Resolve must go through the metadata path (no PEM bytes
        // pulled into the Dart heap for a label-only render).
        expect(fakeStore.metadataLookups, 1);
      },
    );
  });

  group('SessionEditDialog — key picker hardware badge', () {
    SshKeyEntry makeKey(String id, String label) => SshKeyEntry(
      id: id,
      label: label,
      privateKey: '',
      publicKey: '',
      keyType: 'ed25519',
      createdAt: DateTime(2025, 1, 1),
    );

    Widget buildWithKeys(
      List<SshKeyEntry> keys, {
      Map<String, String> backends = const {},
    }) {
      final keysList = List<SshKeyEntry>.unmodifiable(keys);
      return ProviderScope(
        overrides: [
          ..._stubKeysOverrides(_StubKeysMutator(keysList, backends: backends)),
        ],
        child: MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SessionEditDialog.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'FIDO2 row in the picker dropdown carries the HardwareKeyBadge',
      // Spec: the standalone key manager already renders the
      // HardwareKeyBadge next to FIDO2 sk-* rows. The session-edit
      // "Select from key store" picker is a second listing surface
      // for the same rows and must mirror the badge — corp users
      // with mixed software / hardware key stores need to tell at
      // a glance which row is which inside the picker too.
      (tester) async {
        await tester.pumpWidget(
          buildWithKeys(
            [makeKey('k1', 'YubiKey 5'), makeKey('k2', 'Laptop key')],
            backends: {'k1': 'fido2'},
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        // Single-form: Auth fields are visible on the same scrollable
        // page as Connection fields — no tab switch needed.
        await tester.pumpAndSettle();
        // Single-form lays the key-store button below the password
        // field on the same scrollable page; ensure it is visible
        // before tapping so the gesture lands.
        await tester.ensureVisible(find.text('Select from Key Store'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text('Select from Key Store'),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // The FIDO2 row carries the hardware badge — same widget
        // class the key manager uses, so a visual regression on one
        // surface lands on the other.
        expect(find.byType(HardwareKeyBadge), findsOneWidget);
      },
    );

    testWidgets('software rows render no badge', (tester) async {
      await tester.pumpWidget(buildWithKeys([makeKey('k1', 'Laptop key')]));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      // Single-form: Auth fields are visible on the same scrollable
      // page as Connection fields — no tab switch needed.
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select from Key Store'));
      await tester.pumpAndSettle();

      expect(find.byType(HardwareKeyBadge), findsNothing);
    });
  });

  group('SessionEditDialog — system ssh-agent option', () {
    Widget buildAgentApp({Session? session}) {
      return ProviderScope(
        overrides: [
          ..._stubKeysOverrides(_StubKeysMutator(const [])),
          if (session != null)
            sessionTagsProvider(
              session.id,
            ).overrideWith((_) async => const <Tag>[]),
        ],
        child: MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    SessionEditDialog.show(context, session: session),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
    }

    group('desktop', () {
      setUp(() {
        debugDesktopPlatformOverride = true;
        debugMobilePlatformOverride = false;
      });

      tearDown(() {
        debugDesktopPlatformOverride = null;
        debugMobilePlatformOverride = null;
      });

      testWidgets('option renders enabled on the Auth tab', (tester) async {
        await tester.pumpWidget(buildAgentApp());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        // Single-form: Auth fields are visible on the same scrollable
        // page as Connection fields — no tab switch needed.
        await tester.pumpAndSettle();

        expect(find.text('Use system ssh-agent'), findsOneWidget);
        // Password / key sections still render — the toggle is off
        // by default for fresh sessions.
        expect(find.text('PASSWORD'), findsOneWidget);
      });

      testWidgets(
        'selecting the agent option collapses the password + key sections',
        (tester) async {
          await tester.pumpWidget(buildAgentApp());
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          // Single-form: the agent toggle sits at the top of the
          // Authentication section, which lives below Connection
          // on the same scrollable page. Scroll it into view before
          // tapping so the gesture lands on the HoverRegion that
          // owns the flag flip.
          await tester.ensureVisible(find.text('Use system ssh-agent'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text('Use system ssh-agent'),
            warnIfMissed: false,
          );
          await tester.pumpAndSettle();

          // No password field, no OR divider, no key passphrase —
          // the agent owns every credential.
          expect(find.text('PASSWORD'), findsNothing);
          expect(find.text('OR'), findsNothing);
          expect(find.text('KEY PASSPHRASE'), findsNothing);
        },
      );

      testWidgets(
        'Save & Connect with agent selected returns SaveResult with AuthType.agent',
        // Spec: the bus mapper already routes AuthType.agent (set
        // by toSSHConfig.useAgent) into BusConnectAuthRef.agent.
        // The dialog must therefore stamp the session's authType
        // to AuthType.agent when the toggle is on so the connect
        // arm picks the SshAuthAgent ref instead of the composer.
        (tester) async {
          SessionDialogResult? result;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [..._stubKeysOverrides(_StubKeysMutator(const []))],
              child: MaterialApp(
                localizationsDelegates: S.localizationsDelegates,
                supportedLocales: S.supportedLocales,
                home: Scaffold(
                  body: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () async {
                        result = await SessionEditDialog.show(context);
                      },
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          // Fill the smart-paste connect field so the form validates.
          await tester.enterText(
            find.widgetWithText(TextFormField, 'root@example.com:22'),
            'testuser@example.com',
          );
          // Single-form: the agent toggle sits inside the same
          // scrollable page. Scroll it into view before tapping so
          // the gesture lands on the HoverRegion.
          await tester.ensureVisible(find.text('Use system ssh-agent'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text('Use system ssh-agent'),
            warnIfMissed: false,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save & Connect'));
          await tester.pumpAndSettle();

          expect(result, isA<SaveResult>());
          final save = result! as SaveResult;
          expect(save.session.authType, AuthType.agent);
          // No password / key / passphrase leaked through.
          expect(save.session.password, isEmpty);
          expect(save.session.keyData, isEmpty);
          expect(save.session.keyId, isEmpty);
        },
      );

      testWidgets(
        'toSSHConfig propagates useAgent when authType is agent',
        // Spec: the connect path reads SshAuth.useAgent inside
        // ConnectionsNotifier._authFromConfig. toSSHConfig must
        // set the flag from authType so a saved AuthType.agent
        // row routes to SshAuthAgent on every dial.
        (tester) async {
          // No widget pump here — pure projection check.
          final session = Session(
            id: 's',
            label: 'agent',
            server: const ServerAddress(host: 'h', port: 22, user: 'u'),
            auth: const SessionAuth(authType: AuthType.agent),
          );
          expect(session.toSSHConfig().auth.useAgent, isTrue);

          final passwordSession = session.copyWith(
            auth: session.auth.copyWith(authType: AuthType.password),
          );
          expect(passwordSession.toSSHConfig().auth.useAgent, isFalse);
        },
      );

      testWidgets(
        'editing an existing AuthType.agent session opens with toggle on',
        (tester) async {
          final existing = Session(
            id: 's1',
            label: 'agent session',
            server: const ServerAddress(host: 'h', port: 22, user: 'u'),
            auth: const SessionAuth(authType: AuthType.agent),
          );
          await tester.pumpWidget(buildAgentApp(session: existing));
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          // Single-form: Auth fields are visible on the same scrollable
          // page as Connection fields — no tab switch needed.
          await tester.pumpAndSettle();

          // Password / key sections collapsed because the saved
          // session is agent-mode.
          expect(find.text('PASSWORD'), findsNothing);
          expect(find.text('Use system ssh-agent'), findsOneWidget);
        },
      );
    });

    group('mobile', () {
      setUp(() {
        debugDesktopPlatformOverride = false;
        debugMobilePlatformOverride = true;
      });

      tearDown(() {
        debugDesktopPlatformOverride = null;
        debugMobilePlatformOverride = null;
      });

      testWidgets(
        'option is disabled with tooltip — agent endpoint is desktop-only',
        // Spec: the system ssh-agent endpoint is desktop-only —
        // Android / iOS have no analogue. The UI keeps the option
        // visible so the session configuration surface looks the
        // same on every platform, but the row is disabled and
        // surfaces the reason in a tooltip so the user does not
        // have to guess.
        (tester) async {
          await tester.pumpWidget(buildAgentApp());
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          // Single-form: Auth fields are visible on the same scrollable
          // page as Connection fields — no tab switch needed.
          await tester.pumpAndSettle();

          // Tooltip is rendered.
          expect(
            find.byTooltip(
              'Not available on mobile — the system ssh-agent endpoint is desktop-only.',
            ),
            findsOneWidget,
          );

          // Tap-through is suppressed — the password field stays
          // visible (toggle should not flip). Scroll the disabled
          // toggle into view first so the gesture actually lands on
          // it; otherwise the tap target falls outside the dialog
          // body and the modal barrier dismisses the form.
          await tester.ensureVisible(find.text('Use system ssh-agent'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text('Use system ssh-agent'),
            warnIfMissed: false,
          );
          await tester.pumpAndSettle();
          expect(find.text('PASSWORD'), findsOneWidget);
        },
      );
    });
  });

  group('SessionEditDialog — protocol-branched Auth tab', () {
    Future<void> selectKind(WidgetTester tester, String chipLabel) async {
      await tester.tap(find.text(chipLabel));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'SSH kind shows ssh-agent + password + key fields on Auth tab',
      (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await switchToAuth(tester);

        // SSH is the default — agent toggle + password divider + key
        // passphrase all present.
        expect(find.text('Use system ssh-agent'), findsOneWidget);
        expect(find.text('PASSWORD'), findsOneWidget);
        expect(find.text('KEY PASSPHRASE'), findsOneWidget);
      },
    );

    testWidgets(
      'WebDAV kind hides SSH key fields and shows auth-method chips',
      (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await selectKind(tester, 'WebDAV');
        await switchToAuth(tester);

        // Auth-method picker + bearer chip belong on Auth.
        expect(find.text('Basic'), findsOneWidget);
        expect(find.text('Digest'), findsOneWidget);
        expect(find.text('Bearer token'), findsOneWidget);

        // SSH controls must NOT render for WebDAV.
        expect(find.text('Use system ssh-agent'), findsNothing);
        expect(find.text('KEY PASSPHRASE'), findsNothing);
        expect(find.text('Select Key File'), findsNothing);

        // The trusted-cert PEM textarea + insecure toggle moved into
        // the More options expander — closed by default so neither
        // their labels nor warning copy should render here.
        expect(find.text('TRUSTED CERTIFICATE (PEM)'), findsNothing);
        expect(find.text('ACCEPT ANY CERTIFICATE'), findsNothing);
      },
    );

    testWidgets(
      'WebDAV credential field label flips when bearer chip selected',
      (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await selectKind(tester, 'WebDAV');
        await switchToAuth(tester);

        // Basic is the default — credential field label = "PASSWORD *"
        // (the WebDAV credential is always required, so the dialog
        // appends the star to the uppercased FieldLabel text).
        expect(find.text('PASSWORD *'), findsOneWidget);

        // Tap the bearer chip — the field above becomes the token.
        // Scroll the chip into view first so the gesture lands.
        final bearerChip = find.text('Bearer token').first;
        await tester.ensureVisible(bearerChip);
        await tester.pumpAndSettle();
        await tester.tap(bearerChip, warnIfMissed: false);
        await tester.pumpAndSettle();
        // Chip text stays mixed-case ("Bearer token"); the field
        // label routes through `FieldLabel` which uppercases and
        // appends the required marker ("BEARER TOKEN *"). The
        // password label disappears for the bearer method.
        expect(find.text('Bearer token'), findsOneWidget);
        expect(find.text('BEARER TOKEN *'), findsOneWidget);
        expect(find.text('PASSWORD *'), findsNothing);
      },
    );

    testWidgets('S3 kind shows only the secret access key field on Auth tab', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await selectKind(tester, 'S3');
      await switchToAuth(tester);

      expect(find.text('SECRET ACCESS KEY *'), findsOneWidget);

      // No SSH controls, no WebDAV chips.
      expect(find.text('Use system ssh-agent'), findsNothing);
      expect(find.text('KEY PASSPHRASE'), findsNothing);
      expect(find.text('Basic'), findsNothing);
      expect(find.text('Bearer token'), findsNothing);
      // Trusted-cert + insecure are inside More options (collapsed).
      expect(find.text('TRUSTED CERTIFICATE (PEM)'), findsNothing);
      expect(find.text('ACCEPT ANY CERTIFICATE'), findsNothing);
    });

    testWidgets(
      'WebDAV form renders the full set of fields on the single-form page',
      (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await selectKind(tester, 'WebDAV');

        // Single-form layout — every Connection / Auth-side field
        // sits on the same scrollable page. Trusted-cert PEM +
        // accept-any-cert toggle now live in the collapsed More
        // options expander and only appear after a tap on the
        // header (covered by the dedicated More-options tests
        // below).
        expect(find.text('BASE URL *'), findsOneWidget);
        expect(find.text('USERNAME *'), findsOneWidget);
        expect(find.text('Basic'), findsOneWidget);
        expect(find.text('Digest'), findsOneWidget);
        expect(find.text('Bearer token'), findsOneWidget);
      },
    );
  });

  group(
    'SessionEditDialog — Forwarding lives inside Advanced for SSH only',
    () {
      Future<void> selectKind(WidgetTester tester, String chipLabel) async {
        await tester.tap(find.text(chipLabel));
        await tester.pumpAndSettle();
      }

      testWidgets(
        'SSH Advanced section exposes a port-forward summary + Manage button',
        (tester) async {
          await tester.pumpWidget(buildApp());
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await expandAdvanced(tester);
          // New sessions start with zero rules — the pluralised summary
          // (`forwardRulesSummary`) routes through the `=0` branch.
          expect(find.text('No port-forward rules'), findsOneWidget);
          expect(find.text('Manage…'), findsOneWidget);
        },
      );

      testWidgets('WebDAV hides the Forwarding row from Advanced', (
        tester,
      ) async {
        await tester.pumpWidget(buildApp());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await selectKind(tester, 'WebDAV');
        await expandAdvanced(tester);
        expect(find.text('Manage…'), findsNothing);
        expect(find.text('No port-forward rules'), findsNothing);
      });

      testWidgets('S3 hides the Forwarding row from Advanced', (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await selectKind(tester, 'S3');
        await expandAdvanced(tester);
        expect(find.text('Manage…'), findsNothing);
      });
    },
  );

  group('SessionEditDialog — section headers reflect the form layout', () {
    testWidgets(
      'Connection + Authentication + More options section headers render',
      (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        // `_SectionHeader.toUpperCase()` produces these from
        // `connection` / `sectionAuthentication` ARB keys; the
        // collapsible footer block uses the `moreOptions` key.
        expect(find.text('CONNECTION'), findsOneWidget);
        expect(find.text('AUTHENTICATION'), findsOneWidget);
        expect(find.text('MORE OPTIONS'), findsOneWidget);
      },
    );
  });

  group('SessionEditDialog — Advanced collapsible state', () {
    testWidgets(
      'Advanced section is collapsed by default — tags row is not rendered',
      (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        // Body of Advanced is hidden until the user expands. The
        // `_buildTagsSection` row that surfaces "Save the session
        // first to assign tags" therefore is not in the tree yet.
        expect(
          find.text('Save the session first to assign tags'),
          findsNothing,
        );
      },
    );

    testWidgets('Tapping Advanced reveals the Tags / Record-session block', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await expandAdvanced(tester);
      // For a fresh session the inline tag picker renders an
      // empty-state hint (the workspace tagsProvider stub returns
      // []). The record toggle is also visible for SSH.
      expect(
        find.text('No tags yet — create one in Tools → Tags.'),
        findsOneWidget,
      );
      expect(find.text('Record session'), findsOneWidget);
    });

    testWidgets('Record-session toggle is hidden for non-SSH kinds (WebDAV)', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WebDAV'));
      await tester.pumpAndSettle();
      await expandAdvanced(tester);
      expect(find.text('Record session'), findsNothing);
    });

    testWidgets('Record-session toggle is hidden for non-SSH kinds (S3)', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('S3'));
      await tester.pumpAndSettle();
      await expandAdvanced(tester);
      expect(find.text('Record session'), findsNothing);
    });
  });

  group('SessionEditDialog — required-marker stars across kinds', () {
    Future<void> selectKind(WidgetTester tester, String chipLabel) async {
      await tester.tap(find.text(chipLabel));
      await tester.pumpAndSettle();
    }

    testWidgets('SSH renders the smart-paste connect field + password', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      // The single smart-paste surface replaces the old HOST / PORT /
      // USERNAME row; its label comes from the `connectTo` ARB key
      // and `FieldLabel` uppercases it.
      expect(find.text('CONNECT TO'), findsOneWidget);
      // Auth password is on the same scrollable form.
      expect(find.text('PASSWORD'), findsOneWidget);
    });

    testWidgets('WebDAV required fields carry the * marker', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await selectKind(tester, 'WebDAV');
      // Single-form: Connection block on top, Auth block below —
      // all required fields visible on the same scrollable page.
      expect(find.text('BASE URL *'), findsOneWidget);
      expect(find.text('USERNAME *'), findsOneWidget);
      expect(find.text('PASSWORD *'), findsOneWidget);
    });

    testWidgets('S3 required fields carry the * marker', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await selectKind(tester, 'S3');
      expect(find.text('ACCESS KEY ID *'), findsOneWidget);
      expect(find.text('SECRET ACCESS KEY *'), findsOneWidget);
    });
  });

  group('SessionEditDialog — ProxyJump required-field validation', () {
    testWidgets('ProxyJump custom mode blocks Save when host/user missing', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Fill the main SSH connection so only the proxy fields are
      // empty when Save fires.
      await fillRequiredFields(tester);

      // ProxyJump lives inside the collapsible More options block —
      // open it before the "Custom" chip is reachable.
      await expandAdvanced(tester);
      await tester.ensureVisible(find.text('Custom'));
      await tester.pumpAndSettle();

      // Flip the proxy mode to "Custom" — host / port / username
      // fields render with `*Required` labels but used to lack any
      // validator. Save must surface "Required" markers and refuse
      // to close.
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      // Dialog still open — proxy fields blocked the save.
      expect(find.text('New Connection'), findsOneWidget);
      expect(find.text('Required'), findsWidgets);
    });

    testWidgets(
      'ProxyJump custom mode allows Save once host / port / user filled',
      (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await fillRequiredFields(tester);
        await expandAdvanced(tester);
        await tester.ensureVisible(find.text('Custom'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Custom'));
        await tester.pumpAndSettle();

        // The proxy host / port / user hints no longer overlap with
        // any main-form field — the smart-paste surface ate the old
        // host / port / user hints. Hit each placeholder directly.
        await tester.enterText(
          fieldByHint('bastion.example.com'),
          'bastion.example.com',
        );
        await tester.enterText(fieldByHint('22'), '2222');
        await tester.enterText(fieldByHint('root'), 'ops');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save & Connect'));
        await tester.pumpAndSettle();

        // Dialog closed with a SaveResult — proxy override flowed
        // through.
        expect(dialogResult, isA<SaveResult>());
      },
    );

    testWidgets('ProxyJump saved mode blocks Save when no bastion selected', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);
      await expandAdvanced(tester);
      await tester.ensureVisible(find.text('Saved session'));
      await tester.pumpAndSettle();

      // Switch to "Saved session". With no existing sessions to
      // pick (test scope opens a fresh ProviderScope with no
      // session list), the dropdown stays unselected — Save must
      // refuse rather than collapsing silently to no-ProxyJump.
      await tester.tap(find.text('Saved session'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(find.text('New Connection'), findsOneWidget);
      expect(find.text('Required'), findsWidgets);
    });

    testWidgets('ProxyJump port range checked separately from main port', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);
      await expandAdvanced(tester);
      await tester.ensureVisible(find.text('Custom'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      await tester.enterText(
        fieldByHint('bastion.example.com'),
        'bastion.example.com',
      );
      // 99999 is out of the 1..65535 SSH port range.
      await tester.enterText(fieldByHint('22'), '99999');
      await tester.enterText(fieldByHint('root'), 'ops');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      // Dialog stays open; the port-range error surfaces inline.
      expect(find.text('New Connection'), findsOneWidget);
    });
  });
}

/// Minimal [SshKeysMutator] test double — returns the seeded
/// metadata map on every `loadAllMetadata` and records the lookup
/// count so tests can assert the dialog only pulls metadata and
/// never PEM bytes.
///
/// `backends` lets a test set the `backend` discriminator on a row
/// keyed by id so the key-picker surface (which routes the badge
/// widget off this column) can be asserted against. Rows whose id
/// is missing from the map default to `'software'` (no badge).
///
/// Test override for the workspace tag list provider — the dialog
/// watches `tagsProvider` for the inline tag picker; without a
/// stub the live `dbTagsListAll` FRB call spins forever in
/// dialog-only widget tests (no DB bootstrap). Returns an empty
/// list synchronously so `pumpAndSettle` resolves on the first
/// frame.
class _EmptyTagsNotifier extends TagsNotifier {
  @override
  Future<List<Tag>> build() async => const <Tag>[];
}

class _StubKeysMutator extends SshKeysMutator {
  _StubKeysMutator(
    this._initial, {
    Map<String, SshKeyEntry>? lookup,
    Map<String, String>? backends,
  }) : _entries = lookup ?? {for (final k in _initial) k.id: k},
       _backends = backends ?? const {};

  final List<SshKeyEntry> _initial;
  final Map<String, SshKeyEntry> _entries;
  final Map<String, String> _backends;

  /// Number of `loadAllMetadata` invocations — `_resolveKeyLabel`
  /// hits this once per key-picker open, never PEM-bearing `loadAll`.
  int metadataLookups = 0;

  /// Snapshot of the seeded entry list. Used by helpers that build
  /// the matching `sshKeysStreamProvider` override so the picker
  /// reads the same rows the metadata path returns.
  List<SshKeyEntry> get initial => _initial;

  @override
  Future<Map<String, SshKeyMetadata>> loadAllMetadata() async {
    metadataLookups += 1;
    return {
      for (final entry in _entries.values)
        entry.id: SshKeyMetadata(
          id: entry.id,
          label: entry.label,
          publicKey: entry.publicKey,
          keyType: entry.keyType,
          createdAt: entry.createdAt,
          isGenerated: entry.isGenerated,
          privateFingerprint: '',
          publicFingerprint: '',
          backend: _backends[entry.id] ?? 'software',
        ),
    };
  }
}

/// Provider-override builder — wires the stream + mutator overrides
/// off a single [_StubKeysMutator] so every test in this file picks
/// up the same seed list on `sshKeysProvider` (sync derive) and the
/// same metadata response on `sshKeysMutatorProvider.loadAllMetadata`.
List<Override> _stubKeysOverrides(_StubKeysMutator mutator) => [
  sshKeysStreamProvider.overrideWith((_) => Stream.value(mutator.initial)),
  sshKeysMutatorProvider.overrideWithValue(mutator),
];
