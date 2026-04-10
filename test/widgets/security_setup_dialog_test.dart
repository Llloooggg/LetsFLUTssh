import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/security_setup_dialog.dart';
import 'package:letsflutssh/widgets/toast.dart';

/// In-memory fake that mirrors FlutterSecureStorage API.
/// [shouldThrow] controls whether the keychain is "available".
class _FakeStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};
  bool shouldThrow;

  _FakeStorage({this.shouldThrow = false});

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) throw Exception('Keychain unavailable');
    if (value != null) {
      _store[key] = value;
    } else {
      _store.remove(key);
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) throw Exception('Keychain unavailable');
    return _store[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) throw Exception('Keychain unavailable');
    _store.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _store.containsKey(key);
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return Map.of(_store);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(() => Toast.clearAllForTest());

  Widget buildApp({
    required SecureKeyStorage keyStorage,
    required void Function(BuildContext) onPressed,
  }) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => onPressed(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(
    WidgetTester tester, {
    required SecureKeyStorage keyStorage,
  }) async {
    await tester.pumpWidget(
      buildApp(
        keyStorage: keyStorage,
        onPressed: (ctx) {
          SecuritySetupDialog.show(ctx, keyStorage: keyStorage);
        },
      ),
    );
    await tester.tap(find.text('Open'));
    // Let the probe future complete.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  group('SecuritySetupDialog — keychain available', () {
    late SecureKeyStorage keyStorage;

    setUp(() {
      keyStorage = SecureKeyStorage(storage: _FakeStorage());
    });

    testWidgets('shows title and keychain detected message', (tester) async {
      await openDialog(tester, keyStorage: keyStorage);

      expect(find.text('Security Setup'), findsOneWidget);
      expect(find.text('Continue with Keychain'), findsOneWidget);
      expect(find.text('Set Master Password'), findsOneWidget);
    });

    testWidgets('continue with keychain returns result', (tester) async {
      SecuritySetupResult? result;
      await tester.pumpWidget(
        buildApp(
          keyStorage: keyStorage,
          onPressed: (ctx) async {
            result = await SecuritySetupDialog.show(
              ctx,
              keyStorage: keyStorage,
            );
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue with Keychain'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.keychainAvailable, isTrue);
      expect(result!.masterPassword, isNull);
    });

    testWidgets('set master password shows form', (tester) async {
      await openDialog(tester, keyStorage: keyStorage);

      await tester.tap(find.text('Set Master Password'));
      await tester.pumpAndSettle();

      // Password form should be visible.
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('master password too short shows toast', (tester) async {
      await openDialog(tester, keyStorage: keyStorage);

      await tester.tap(find.text('Set Master Password'));
      await tester.pumpAndSettle();

      // Enter short password.
      await tester.enterText(find.byType(TextField).first, 'short');
      await tester.enterText(find.byType(TextField).last, 'short');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Dialog should still be open (password form visible).
      expect(find.byType(TextField), findsNWidgets(2));

      // Flush the toast auto-dismiss timer and removal animation.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('mismatched passwords shows toast', (tester) async {
      await openDialog(tester, keyStorage: keyStorage);

      await tester.tap(find.text('Set Master Password'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'password123');
      await tester.enterText(find.byType(TextField).last, 'different1');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Dialog should still be open.
      expect(find.byType(TextField), findsNWidgets(2));

      // Flush the toast auto-dismiss timer and removal animation.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('valid master password returns result', (tester) async {
      SecuritySetupResult? result;
      await tester.pumpWidget(
        buildApp(
          keyStorage: keyStorage,
          onPressed: (ctx) async {
            result = await SecuritySetupDialog.show(
              ctx,
              keyStorage: keyStorage,
            );
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set Master Password'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'mypassword123');
      await tester.enterText(find.byType(TextField).last, 'mypassword123');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.masterPassword, 'mypassword123');
      expect(result!.keychainAvailable, isTrue);
    });

    testWidgets('cancel from password form goes back to choice', (
      tester,
    ) async {
      await openDialog(tester, keyStorage: keyStorage);

      await tester.tap(find.text('Set Master Password'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Back to the choice screen.
      expect(find.text('Continue with Keychain'), findsOneWidget);
    });
  });

  group('SecuritySetupDialog — keychain NOT available', () {
    late SecureKeyStorage keyStorage;

    setUp(() {
      keyStorage = SecureKeyStorage(storage: _FakeStorage(shouldThrow: true));
    });

    testWidgets('shows no keychain message and warning', (tester) async {
      await openDialog(tester, keyStorage: keyStorage);

      expect(find.text('Security Setup'), findsOneWidget);
      expect(find.text('Continue without Encryption'), findsOneWidget);
      expect(find.text('Set Master Password'), findsOneWidget);
      // "Continue with Keychain" should NOT be visible.
      expect(find.text('Continue with Keychain'), findsNothing);
    });

    testWidgets('continue without encryption returns result', (tester) async {
      SecuritySetupResult? result;
      await tester.pumpWidget(
        buildApp(
          keyStorage: keyStorage,
          onPressed: (ctx) async {
            result = await SecuritySetupDialog.show(
              ctx,
              keyStorage: keyStorage,
            );
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue without Encryption'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.keychainAvailable, isFalse);
      expect(result!.masterPassword, isNull);
    });
  });
}
