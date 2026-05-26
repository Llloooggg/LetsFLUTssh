import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/src/rust/api/pkcs11.dart' as rust_pkcs11;
import 'package:letsflutssh/widgets/ssh_keys/pkcs11_import_dialog.dart';

/// In-memory fake backend. Each method returns the canned response
/// the test seeded; the wizard never reaches the real FRB shim.
class _FakeBackend extends Pkcs11Backend {
  _FakeBackend({
    this.modules = const [],
    this.tokens = const [],
    this.keys = const [],
  }) : super();

  final List<rust_pkcs11.DbPkcs11ModuleCandidate> modules;
  final List<rust_pkcs11.DbPkcs11TokenInfo> tokens;
  final List<rust_pkcs11.DbPkcs11KeyMeta> keys;
  rust_pkcs11.DbPkcs11ImportArgs? captured;
  String? stagedPinId;
  List<int>? stagedPinBytes;

  @override
  Future<List<rust_pkcs11.DbPkcs11ModuleCandidate>>
  scanWellKnownPaths() async => modules;

  @override
  Future<void> loadModule(String path) async {}

  @override
  Future<List<rust_pkcs11.DbPkcs11TokenInfo>> listTokens(String path) async =>
      tokens;

  @override
  Future<List<rust_pkcs11.DbPkcs11KeyMeta>> listKeys(
    String path,
    BigInt slotId, {
    String? pinSecretId,
  }) async => keys;

  @override
  Future<String> importKey(rust_pkcs11.DbPkcs11ImportArgs args) async {
    captured = args;
    return 'pkcs11-key-id';
  }

  @override
  Future<void> stagePin(String id, List<int> bytes) async {
    stagedPinId = id;
    stagedPinBytes = bytes;
  }

  @override
  Future<void> dropPin(String id) async {}

  @override
  String composeUri({
    required String tokenLabel,
    required String serial,
    required String objectLabel,
    required Uint8List objectId,
    required String modulePath,
  }) => 'pkcs11:token=$tokenLabel;serial=$serial;object=$objectLabel';
}

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: child),
);

Future<Pkcs11ImportResult?> _open(
  WidgetTester tester, {
  required _FakeBackend backend,
}) async {
  Pkcs11ImportResult? captured;
  await tester.pumpWidget(
    _wrap(
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () async {
            captured = await Pkcs11ImportDialog.show(
              ctx,
              backend: backend,
              pickModuleFile: () async => '/tmp/custom.so',
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pkcs11ImportDialog — module step', () {
    testWidgets('renders the localized step title', (tester) async {
      final backend = _FakeBackend(
        modules: [
          const rust_pkcs11.DbPkcs11ModuleCandidate(
            vendor: 'OpenSC',
            path: '/usr/lib/opensc-pkcs11.so',
          ),
        ],
      );
      await _open(tester, backend: backend);
      // Localized step title — falls back to the English ARB string in
      // the absence of a locale override.
      expect(find.text('Select PKCS#11 module'), findsOneWidget);
    });

    testWidgets('lists scanned candidates with vendor + path', (tester) async {
      final backend = _FakeBackend(
        modules: [
          const rust_pkcs11.DbPkcs11ModuleCandidate(
            vendor: 'OpenSC',
            path: '/usr/lib/opensc-pkcs11.so',
          ),
          const rust_pkcs11.DbPkcs11ModuleCandidate(
            vendor: 'JaCarta',
            path: '/usr/lib/libjcPKCS11-2.so',
          ),
        ],
      );
      await _open(tester, backend: backend);
      expect(find.text('OpenSC'), findsOneWidget);
      expect(find.text('JaCarta'), findsOneWidget);
      expect(find.text('/usr/lib/opensc-pkcs11.so'), findsOneWidget);
    });

    testWidgets('renders "no module found" when scan is empty', (tester) async {
      final backend = _FakeBackend(modules: const []);
      await _open(tester, backend: backend);
      expect(find.textContaining('No PKCS#11 module found'), findsOneWidget);
    });
  });

  group('Pkcs11ImportDialog — token step', () {
    testWidgets('"no token present" when token list is empty', (tester) async {
      final backend = _FakeBackend(
        modules: [
          const rust_pkcs11.DbPkcs11ModuleCandidate(
            vendor: 'OpenSC',
            path: '/p.so',
          ),
        ],
        tokens: const [],
      );
      await _open(tester, backend: backend);
      await tester.tap(find.text('OpenSC'));
      await tester.pumpAndSettle();
      expect(find.text('No token present in any reader.'), findsOneWidget);
    });
  });

  group('Pkcs11ImportDialog — key step', () {
    testWidgets('GOST row disabled, RSA / ECDSA / Ed25519 enabled', (
      tester,
    ) async {
      final backend = _FakeBackend(
        modules: [
          const rust_pkcs11.DbPkcs11ModuleCandidate(
            vendor: 'OpenSC',
            path: '/p.so',
          ),
        ],
        tokens: [
          rust_pkcs11.DbPkcs11TokenInfo(
            slotId: BigInt.from(1),
            label: 'TestToken',
            manufacturer: 'TestCo',
            model: 'TestModel',
            serial: 'SN-1',
            loginRequired: false,
            protectedAuthPath: true,
            userPinFinalTry: false,
            userPinLocked: false,
          ),
        ],
        keys: [
          rust_pkcs11.DbPkcs11KeyMeta(
            label: 'rsa-key',
            ckaId: Uint8List.fromList([1]),
            sshKeyType: 'rsa',
            sshPublicBlob: Uint8List.fromList([2]),
            disabledReason: '',
          ),
          rust_pkcs11.DbPkcs11KeyMeta(
            label: 'gost-key',
            ckaId: Uint8List.fromList([3]),
            sshKeyType: '',
            sshPublicBlob: Uint8List.fromList([4]),
            disabledReason: 'gost-not-supported',
          ),
          rust_pkcs11.DbPkcs11KeyMeta(
            label: 'ecdsa-key',
            ckaId: Uint8List.fromList([5]),
            sshKeyType: 'ecdsa-p256',
            sshPublicBlob: Uint8List.fromList([6]),
            disabledReason: '',
          ),
          rust_pkcs11.DbPkcs11KeyMeta(
            label: 'ed25519-key',
            ckaId: Uint8List.fromList([7]),
            sshKeyType: 'ed25519',
            sshPublicBlob: Uint8List.fromList([8]),
            disabledReason: '',
          ),
        ],
      );
      await _open(tester, backend: backend);
      await tester.tap(find.text('OpenSC'));
      await tester.pumpAndSettle();
      // PIN-pad token → wizard hops to key step directly.
      await tester.tap(find.text('TestToken'));
      await tester.pumpAndSettle();
      // GOST disabled reason rendered.
      expect(find.text('GOST keys cannot be used with SSH.'), findsOneWidget);
      // All four key rows present.
      expect(find.text('rsa-key'), findsOneWidget);
      expect(find.text('gost-key'), findsOneWidget);
      expect(find.text('ecdsa-key'), findsOneWidget);
      expect(find.text('ed25519-key'), findsOneWidget);
    });

    testWidgets('submit calls importKey with picked key + label', (
      tester,
    ) async {
      final backend = _FakeBackend(
        modules: [
          const rust_pkcs11.DbPkcs11ModuleCandidate(
            vendor: 'OpenSC',
            path: '/p.so',
          ),
        ],
        tokens: [
          rust_pkcs11.DbPkcs11TokenInfo(
            slotId: BigInt.from(1),
            label: 'TestToken',
            manufacturer: 'TestCo',
            model: 'TestModel',
            serial: 'SN-1',
            loginRequired: false,
            protectedAuthPath: true,
            userPinFinalTry: false,
            userPinLocked: false,
          ),
        ],
        keys: [
          rust_pkcs11.DbPkcs11KeyMeta(
            label: 'rsa-key',
            ckaId: Uint8List.fromList([1, 2, 3]),
            sshKeyType: 'rsa',
            sshPublicBlob: Uint8List.fromList([9, 9, 9]),
            disabledReason: '',
          ),
        ],
      );
      Pkcs11ImportResult? captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                captured = await Pkcs11ImportDialog.show(ctx, backend: backend);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OpenSC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TestToken'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('rsa-key'));
      await tester.pumpAndSettle();
      // Submit step — the "Import key" CTA fires the importKey call.
      // The literal also surfaces as the dialog title at this step,
      // so disambiguate by selecting whichever match sits inside an
      // AppButton's tappable surface (the Semantics with button: true).
      final semantics = find.byWidgetPredicate((w) {
        return w is Semantics &&
            w.properties.button == true &&
            w.properties.label == 'Import key';
      });
      expect(semantics, findsOneWidget);
      await tester.tap(semantics);
      await tester.pumpAndSettle();
      expect(backend.captured, isNotNull);
      expect(backend.captured!.ckaId, Uint8List.fromList([1, 2, 3]));
      expect(backend.captured!.sshKeyType, 'rsa');
      expect(backend.captured!.label, 'rsa-key');
      expect(captured, isNotNull);
      expect(captured!.keyId, 'pkcs11-key-id');
    });
  });

  group('Pkcs11Badge', () {
    testWidgets('renders label + tooltip', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Pkcs11Badge(
            label: 'Smart card / token',
            modulePath: '/usr/lib/p.so',
            tokenSerial: 'SN-42',
            objectLabel: 'PIV slot 9a',
          ),
        ),
      );
      expect(find.text('Smart card / token'), findsOneWidget);
    });

    testWidgets('tapping opens info popover with all three fields', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const Pkcs11Badge(
            label: 'Smart card / token',
            modulePath: '/usr/lib/p.so',
            tokenSerial: 'SN-42',
            objectLabel: 'PIV slot 9a',
          ),
        ),
      );
      await tester.tap(find.text('Smart card / token'));
      await tester.pumpAndSettle();
      // Each field surfaces via its localized template.
      expect(find.textContaining('/usr/lib/p.so'), findsOneWidget);
      expect(find.textContaining('SN-42'), findsOneWidget);
      expect(find.textContaining('PIV slot 9a'), findsOneWidget);
    });
  });
}
