import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/features/key_manager/key_manager_dialog.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/key_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/toast.dart';

/// In-memory fake for [KeyStore] — no filesystem or encryption.
class FakeKeyStore extends KeyStore {
  final Map<String, SshKeyEntry> _keys;

  /// When true, [importKey] throws [FormatException].
  bool importThrows = false;

  FakeKeyStore([List<SshKeyEntry>? initial])
    : _keys = {for (final e in initial ?? []) e.id: e};

  @override
  Future<Map<String, SshKeyEntry>> loadAllSafe() async => Map.of(_keys);

  @override
  Future<void> save(SshKeyEntry entry) async => _keys[entry.id] = entry;

  @override
  Future<void> delete(String id) async => _keys.remove(id);

  @override
  SshKeyEntry importKey(String pem, String label) {
    if (importThrows) throw const FormatException('Invalid PEM');
    return SshKeyEntry(
      id: 'imported-${_keys.length}',
      label: label,
      privateKey: pem,
      publicKey: 'ssh-ed25519 AAAA...',
      keyType: 'ed25519',
      createdAt: DateTime.now(),
    );
  }
}

void main() {
  late FakeKeyStore fakeStore;

  final testKey = SshKeyEntry(
    id: 'k1',
    label: 'My Test Key',
    privateKey: 'private',
    publicKey: 'ssh-ed25519 AAAA',
    keyType: 'ed25519',
    createdAt: DateTime(2024, 1, 15),
  );

  final generatedKey = SshKeyEntry(
    id: 'k2',
    label: 'Generated Key',
    privateKey: 'gen-private',
    publicKey: 'ssh-ed25519 BBBB',
    keyType: 'ed25519',
    createdAt: DateTime(2024, 2, 20),
    isGenerated: true,
  );

  Widget buildApp() {
    return ProviderScope(
      overrides: [keyStoreProvider.overrideWithValue(fakeStore)],
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => KeyManagerDialog.show(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  tearDown(() => Toast.clearAllForTest());

  group('KeyManagerDialog', () {
    testWidgets('shows loading then transitions to content', (tester) async {
      fakeStore = FakeKeyStore();
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      // After one frame the dialog is visible with the spinner.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Let async load complete.
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows empty state when no keys', (tester) async {
      fakeStore = FakeKeyStore();
      await openDialog(tester);

      expect(find.text('No SSH keys. Import or generate one.'), findsOneWidget);
    });

    testWidgets('shows dialog title SSH Keys', (tester) async {
      fakeStore = FakeKeyStore();
      await openDialog(tester);

      expect(find.text('SSH Keys'), findsOneWidget);
    });

    testWidgets('renders key entries with label and type', (tester) async {
      fakeStore = FakeKeyStore([testKey]);
      await openDialog(tester);

      expect(find.text('My Test Key'), findsOneWidget);
      // Key type + date line
      expect(find.textContaining('ed25519'), findsOneWidget);
    });

    testWidgets('shows Generated badge for generated keys', (tester) async {
      fakeStore = FakeKeyStore([generatedKey]);
      await openDialog(tester);

      expect(find.text('Generated Key'), findsOneWidget);
      // The key row's subtitle has the "  •  Generated" suffix.
      expect(find.textContaining(RegExp(r'•\s*Generated')), findsOneWidget);
    });

    testWidgets('cancel button closes dialog', (tester) async {
      fakeStore = FakeKeyStore();
      await openDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog title should be gone.
      expect(find.text('SSH Keys'), findsNothing);
    });

    testWidgets('delete button shows confirmation dialog', (tester) async {
      fakeStore = FakeKeyStore([testKey]);
      await openDialog(tester);

      // Tap the delete icon button.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Delete Key'), findsOneWidget);
    });

    testWidgets('delete confirmation removes key', (tester) async {
      fakeStore = FakeKeyStore([testKey]);
      await openDialog(tester);

      // Open delete confirmation.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Confirm deletion.
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Key should be gone from the list and store.
      expect(find.text('My Test Key'), findsNothing);
      expect(fakeStore._keys, isEmpty);

      // Dismiss the success toast and let the overlay dispose cleanly.
      Toast.clearAllForTest();
      await tester.pump();
    });

    testWidgets('delete cancel keeps key', (tester) async {
      fakeStore = FakeKeyStore([testKey]);
      await openDialog(tester);

      // Open delete confirmation.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Cancel deletion — there are two Cancel buttons (main dialog + confirm
      // dialog). The confirmation dialog's Cancel is on top, so tap the last.
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      // Key should still be visible.
      expect(find.text('My Test Key'), findsOneWidget);
      expect(fakeStore._keys, hasLength(1));
    });

    testWidgets('generate key button opens generate dialog', (tester) async {
      fakeStore = FakeKeyStore();
      await openDialog(tester);

      await tester.tap(find.text('Generate Key'));
      await tester.pumpAndSettle();

      // Generate dialog contains a Key Label text field.
      expect(find.text('Key Label'), findsOneWidget);
      // Key type chips should be visible.
      expect(find.text('Ed25519'), findsOneWidget);
    });

    testWidgets('import key button opens import dialog', (tester) async {
      fakeStore = FakeKeyStore();
      await openDialog(tester);

      await tester.tap(find.text('Import Key'));
      await tester.pumpAndSettle();

      // Import dialog contains label and PEM fields.
      expect(find.text('Key Label'), findsOneWidget);
      expect(find.text('Paste Private Key (PEM)'), findsOneWidget);
    });

    testWidgets('import with invalid PEM shows error toast', (tester) async {
      fakeStore = FakeKeyStore();
      fakeStore.importThrows = true;
      await openDialog(tester);

      // Open import dialog.
      await tester.tap(find.text('Import Key'));
      await tester.pumpAndSettle();

      // Fill in label and PEM fields.
      await tester.enterText(
        find.widgetWithText(TextField, 'Key Label'),
        'Bad',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Paste Private Key (PEM)'),
        'not-a-pem',
      );

      // The import dialog has its own "Import Key" button — tap it.
      // There may be multiple "Import Key" texts (toolbar + dialog button).
      // The dialog's action button is the last one visible.
      await tester.tap(find.text('Import Key').last);
      await tester.pumpAndSettle();

      // Error toast should appear with the invalid PEM message.
      expect(find.text('Invalid PEM key data'), findsOneWidget);

      // Dismiss the toast and let the overlay dispose cleanly.
      Toast.clearAllForTest();
      await tester.pump();
    });
  });
}
