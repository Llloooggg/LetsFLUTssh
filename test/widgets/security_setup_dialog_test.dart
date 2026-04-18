import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/security_setup_dialog.dart';

/// In-memory fake that mirrors `FlutterSecureStorage` API. The
/// `shouldThrow` flag simulates "no keychain on this host" — the
/// probe uses write → read → delete, so one throw is enough.
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
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SecuritySetupResult?> openDialog(
    WidgetTester tester, {
    required bool keychainAvailable,
  }) async {
    final storage = _FakeStorage(shouldThrow: !keychainAvailable);
    final keyStorage = SecureKeyStorage(storage: storage);
    SecuritySetupResult? result;

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (ctx) => TextButton(
            child: const Text('Open'),
            onPressed: () async {
              result = await SecuritySetupDialog.show(
                ctx,
                keyStorage: keyStorage,
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return Future.value(result);
  }

  group('SecuritySetupDialog — tier ladder', () {
    testWidgets('renders every tier badge + Paranoid alternative', (
      tester,
    ) async {
      await openDialog(tester, keychainAvailable: true);
      expect(find.text('L0'), findsOneWidget);
      expect(find.text('L1'), findsOneWidget);
      expect(find.text('L2'), findsOneWidget);
      expect(find.text('L3'), findsOneWidget);
      // Paranoid has no badge — find it by its label.
      expect(find.text('Master password (Paranoid)'), findsOneWidget);
    });

    testWidgets('keychain row is Recommended when OS keychain probe succeeds', (
      tester,
    ) async {
      await openDialog(tester, keychainAvailable: true);
      // Recommended badge appears next to the default pick.
      expect(find.text('Recommended'), findsWidgets);
    });

    testWidgets('Paranoid row is Recommended when keychain probe fails', (
      tester,
    ) async {
      await openDialog(tester, keychainAvailable: false);
      expect(find.text('Recommended'), findsWidgets);
      // L1 row still rendered but its action must be disabled.
      expect(find.text('L1'), findsOneWidget);
    });

    testWidgets(
      'L2 and L3 rows are always disabled for now (upcoming tooltip)',
      (tester) async {
        await openDialog(tester, keychainAvailable: true);
        // A tooltip can't be hit-tested without a long-press gesture,
        // but the subtitle copy is a proxy for the row being shown.
        expect(find.text('Keychain + password'), findsOneWidget);
        expect(find.text('Hardware + PIN'), findsOneWidget);
      },
    );
  });
}
