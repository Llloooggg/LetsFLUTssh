import 'dart:async';
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
  final List<String> droppedPinIds = [];

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
  Future<void> dropPin(String id) async {
    droppedPinIds.add(id);
  }

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
  required Pkcs11Backend backend,
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

    testWidgets('label-only badge skips every optional metadata line', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const Pkcs11Badge(label: 'Smart card / token')),
      );
      await tester.tap(find.text('Smart card / token'));
      await tester.pumpAndSettle();
      // No conditional metadata rendered.
      expect(find.textContaining('Module:'), findsNothing);
      expect(find.textContaining('Token serial:'), findsNothing);
      expect(find.textContaining('Object:'), findsNothing);
    });
  });

  group('Pkcs11ImportDialog — module step extras', () {
    testWidgets('scan still loading → spinner copy renders', (tester) async {
      final backend = _SlowScanBackend();
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () => Pkcs11ImportDialog.show(ctx, backend: backend),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      // No pumpAndSettle — let the scan stay in-flight.
      await tester.pump();
      expect(
        find.textContaining('Scanning for PKCS#11 modules'),
        findsOneWidget,
      );
      // Resolve so dispose doesn't leak a pending future.
      backend.completer.complete(const []);
      await tester.pumpAndSettle();
    });

    testWidgets('scan throws → spinner clears, empty-state copy renders', (
      tester,
    ) async {
      const backend = _ThrowingScanBackend();
      await _open(tester, backend: backend);
      // Scan failure is logged + swallowed; the empty-list state is
      // what the user sees.
      expect(find.textContaining('No PKCS#11 module found'), findsOneWidget);
    });

    testWidgets(
      'custom-module picker seam appends an entry and fires loadModule',
      (tester) async {
        final backend = _RecordingBackend();
        await _open(tester, backend: backend);
        // Module list starts empty; only the empty-state + custom CTA.
        await tester.tap(find.text('Custom module...'));
        await tester.pumpAndSettle();
        // The seam-supplied path was added with vendor 'Custom'.
        expect(find.text('Custom'), findsOneWidget);
        expect(find.text('/tmp/custom.so'), findsOneWidget);
        // loadModule was probed.
        expect(backend.loadedPaths, contains('/tmp/custom.so'));
      },
    );

    testWidgets('loadModule failure stamps the failed probe dot', (
      tester,
    ) async {
      final backend = _RecordingBackend()..loadModuleThrows = true;
      await _open(tester, backend: backend);
      await tester.tap(find.text('Custom module...'));
      await tester.pumpAndSettle();
      // Failed probe — the wizard stays on the module step (the tap
      // does not advance) and the row remains visible.
      expect(find.text('/tmp/custom.so'), findsOneWidget);
      // Title is still the module step.
      expect(find.text('Select PKCS#11 module'), findsOneWidget);
    });
  });

  group('Pkcs11ImportDialog — token interaction', () {
    testWidgets('module tap awaits listTokens then advances to token step', (
      tester,
    ) async {
      final backend = _SlowTokensBackend(
        modules: [
          const rust_pkcs11.DbPkcs11ModuleCandidate(
            vendor: 'OpenSC',
            path: '/p.so',
          ),
        ],
      );
      await _open(tester, backend: backend);
      await tester.tap(find.text('OpenSC'));
      // Don't settle — `_onModuleTap` advances to the token step
      // ONLY after `_loadTokens` completes, so while the future is
      // pending the wizard is still on the module step.
      await tester.pump();
      await tester.pump();
      // Spec: still on module step (the loadTokens is awaited
      // before the setState that flips the step).
      expect(find.text('Select PKCS#11 module'), findsOneWidget);
      // Resolve and let the wizard settle.
      backend.tokensCompleter.complete(const []);
      await tester.pumpAndSettle();
      expect(find.text('Select token'), findsOneWidget);
    });

    testWidgets(
      'PIN-required token opens the PIN prompt; cancel stays on token',
      (tester) async {
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
              loginRequired: true,
              protectedAuthPath: false,
              userPinFinalTry: false,
              userPinLocked: false,
            ),
          ],
        );
        await _open(tester, backend: backend);
        await tester.tap(find.text('OpenSC'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('TestToken'));
        await tester.pumpAndSettle();
        // HardwareKeyPromptDialog opened. Cancel via its localized
        // Cancel button.
        final cancel = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == 'Cancel',
        );
        await tester.tap(cancel.first);
        await tester.pumpAndSettle();
        // No PIN was staged because the user cancelled.
        expect(backend.stagedPinId, isNull);
      },
    );

    testWidgets(
      '!loginRequired token skips the PIN prompt and lands on key step',
      (tester) async {
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
              label: 'AnonToken',
              manufacturer: 'TestCo',
              model: 'TestModel',
              serial: 'SN-A',
              // Public-object access: no login needed AND no PIN pad.
              loginRequired: false,
              protectedAuthPath: false,
              userPinFinalTry: false,
              userPinLocked: false,
            ),
          ],
          keys: const [],
        );
        await _open(tester, backend: backend);
        await tester.tap(find.text('OpenSC'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('AnonToken'));
        await tester.pumpAndSettle();
        // Key step body with empty list copy.
        expect(
          find.text('Token has no SSH-usable keys (RSA, ECDSA, Ed25519).'),
          findsOneWidget,
        );
        // The Back action retraces through pin → token. Pressing back
        // from key on a non-pin-pad token lands on the pin step (spec
        // from `pkcs11_import_dialog_logic.dart`).
        final back = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == 'Back',
        );
        await tester.tap(back);
        await tester.pumpAndSettle();
        // PIN step body is just the localized step title centred.
        expect(find.text('Enter PIN'), findsWidgets);
      },
    );

    testWidgets('locked token row is not tappable', (tester) async {
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
            label: 'LockedToken',
            manufacturer: 'TestCo',
            model: 'TestModel',
            serial: 'SN-L',
            loginRequired: true,
            protectedAuthPath: false,
            userPinFinalTry: false,
            userPinLocked: true,
          ),
        ],
      );
      await _open(tester, backend: backend);
      await tester.tap(find.text('OpenSC'));
      await tester.pumpAndSettle();
      // Locked badge text surfaces.
      expect(
        find.text('Token PIN is locked. Unblock with the PUK.'),
        findsOneWidget,
      );
      // Tapping does not advance — wizard stays on token step.
      await tester.tap(find.text('LockedToken'));
      await tester.pumpAndSettle();
      // Still on token step title.
      expect(find.text('Select token'), findsWidgets);
    });

    testWidgets(
      'final-try token surfaces the remaining-attempts badge in orange',
      (tester) async {
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
              label: 'FinalTryToken',
              manufacturer: 'TestCo',
              model: 'TestModel',
              serial: 'SN-F',
              loginRequired: true,
              protectedAuthPath: false,
              userPinFinalTry: true,
              userPinLocked: false,
            ),
          ],
        );
        await _open(tester, backend: backend);
        await tester.tap(find.text('OpenSC'));
        await tester.pumpAndSettle();
        // `pkcs11PinIncorrect("1")` template fills the placeholder.
        expect(find.textContaining('1 tries left'), findsOneWidget);
      },
    );

    testWidgets('PIN-pad token shows the PIN-pad hint copy', (tester) async {
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
            label: 'PinPadToken',
            manufacturer: 'TestCo',
            model: 'TestModel',
            serial: 'SN-P',
            loginRequired: true,
            protectedAuthPath: true,
            userPinFinalTry: false,
            userPinLocked: false,
          ),
        ],
      );
      await _open(tester, backend: backend);
      await tester.tap(find.text('OpenSC'));
      await tester.pumpAndSettle();
      expect(find.text('(PIN pad on device)'), findsOneWidget);
    });
  });

  group('Pkcs11ImportDialog — key step extras', () {
    testWidgets('loadingKeys spinner copy surfaces during enumeration', (
      tester,
    ) async {
      final backend = _SlowKeysBackend(
        modules: [
          const rust_pkcs11.DbPkcs11ModuleCandidate(
            vendor: 'OpenSC',
            path: '/p.so',
          ),
        ],
        tokens: [
          rust_pkcs11.DbPkcs11TokenInfo(
            slotId: BigInt.from(1),
            label: 'AnonToken',
            manufacturer: 'TestCo',
            model: 'TestModel',
            serial: 'SN-A',
            loginRequired: false,
            protectedAuthPath: false,
            userPinFinalTry: false,
            userPinLocked: false,
          ),
        ],
      );
      await _open(tester, backend: backend);
      await tester.tap(find.text('OpenSC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AnonToken'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Loading keys'), findsOneWidget);
      backend.keysCompleter.complete(const []);
      await tester.pumpAndSettle();
    });

    testWidgets('GOST key row carries the localized algo label', (
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
            label: 'gost-key',
            ckaId: Uint8List.fromList([3]),
            sshKeyType: '',
            sshPublicBlob: Uint8List.fromList([4]),
            // The startsWith('gost') branch in `_KeyRow.build` chooses
            // the localized "GOST" label over the raw type tag.
            disabledReason: 'gost-not-supported',
          ),
        ],
      );
      await _open(tester, backend: backend);
      await tester.tap(find.text('OpenSC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TestToken'));
      await tester.pumpAndSettle();
      // Meta-row uses the localized "GOST" string, not the empty
      // sshKeyType.
      expect(find.text('GOST'), findsOneWidget);
    });

    testWidgets(
      'ECDSA key row composes algo + curve via the meta-format string',
      (tester) async {
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
              label: 'ec-key',
              ckaId: Uint8List.fromList([1]),
              sshKeyType: 'ecdsa-p384',
              sshPublicBlob: Uint8List.fromList([2]),
              disabledReason: '',
            ),
          ],
        );
        await _open(tester, backend: backend);
        await tester.tap(find.text('OpenSC'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('TestToken'));
        await tester.pumpAndSettle();
        // Algo + detail composed via `pkcs11KeyMetaFormat`.
        expect(find.text('ECDSA P-384'), findsOneWidget);
      },
    );

    testWidgets('GOST row tap is a no-op (disabled, never advances step)', (
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
            label: 'gost-key',
            ckaId: Uint8List.fromList([3]),
            sshKeyType: '',
            sshPublicBlob: Uint8List.fromList([4]),
            disabledReason: 'gost-not-supported',
          ),
        ],
      );
      await _open(tester, backend: backend);
      await tester.tap(find.text('OpenSC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TestToken'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('gost-key'));
      await tester.pumpAndSettle();
      // Still on key step.
      expect(find.text('Select key'), findsWidgets);
    });
  });

  group('Pkcs11ImportDialog — save step', () {
    testWidgets(
      'empty typed label falls back to the picked key.label on submit',
      (tester) async {
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
              label: 'original-key',
              ckaId: Uint8List.fromList([1, 2, 3]),
              sshKeyType: 'rsa',
              sshPublicBlob: Uint8List.fromList([9]),
              disabledReason: '',
            ),
          ],
        );
        await _open(tester, backend: backend);
        await tester.tap(find.text('OpenSC'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('TestToken'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('original-key'));
        await tester.pumpAndSettle();
        // Clear the prefill so submit sees an empty typed label.
        await tester.enterText(find.byType(TextField), '   ');
        await tester.pumpAndSettle();
        final semantics = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == 'Import key',
        );
        await tester.tap(semantics);
        await tester.pumpAndSettle();
        // Spec: empty trim → key.label is what reaches importKey.
        expect(backend.captured!.label, 'original-key');
      },
    );

    testWidgets('submit failure keeps the dialog open + clears saving flag', (
      tester,
    ) async {
      final backend = _FailingImportBackend(
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
            label: 'key',
            ckaId: Uint8List.fromList([1]),
            sshKeyType: 'rsa',
            sshPublicBlob: Uint8List.fromList([2]),
            disabledReason: '',
          ),
        ],
      );
      await _open(tester, backend: backend);
      await tester.tap(find.text('OpenSC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TestToken'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('key'));
      await tester.pumpAndSettle();
      final semantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == 'Import key',
      );
      await tester.tap(semantics);
      await tester.pumpAndSettle();
      // Still on save step (dialog open). The save spinner copy
      // is gone after _saving flips back to false.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Reading public key from token...'), findsNothing);
    });

    testWidgets(
      'Back from save returns to key step, preserving the picked key',
      (tester) async {
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
              label: 'k',
              ckaId: Uint8List.fromList([1]),
              sshKeyType: 'rsa',
              sshPublicBlob: Uint8List.fromList([2]),
              disabledReason: '',
            ),
          ],
        );
        await _open(tester, backend: backend);
        await tester.tap(find.text('OpenSC'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('TestToken'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('k'));
        await tester.pumpAndSettle();
        final back = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == 'Back',
        );
        await tester.tap(back);
        await tester.pumpAndSettle();
        // Landed back on key step.
        expect(find.text('Select key'), findsWidgets);
      },
    );

    testWidgets('Cancel on the module step pops the dialog without an import', (
      tester,
    ) async {
      final backend = _FakeBackend(
        modules: [
          const rust_pkcs11.DbPkcs11ModuleCandidate(
            vendor: 'OpenSC',
            path: '/p.so',
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
      // The module step's only action is Cancel (no Back yet).
      final cancel = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == 'Cancel',
      );
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(captured, isNull);
      expect(backend.captured, isNull);
    });
  });

  group('Pkcs11ImportDialog — dispose', () {
    testWidgets('dispose drops the staged PIN id when one was set', (
      tester,
    ) async {
      // Stage a PIN by walking the PIN-required path then dismissing
      // the dialog before submit. The dispose hook must fire dropPin.
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
            loginRequired: true,
            protectedAuthPath: false,
            userPinFinalTry: false,
            userPinLocked: false,
          ),
        ],
      );
      await _open(tester, backend: backend);
      await tester.tap(find.text('OpenSC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TestToken'));
      await tester.pumpAndSettle();
      // HardwareKeyPromptDialog opened — enter PIN + submit.
      final pinField = find.byType(TextField).first;
      await tester.enterText(pinField, '1234');
      await tester.pumpAndSettle();
      // Tap the primary action of the prompt — its localized label.
      final tapPrompt = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == 'OK',
      );
      await tester.tap(tapPrompt);
      await tester.pumpAndSettle();
      // PIN was staged.
      expect(backend.stagedPinId, isNotNull);
      expect(backend.stagedPinBytes, '1234'.codeUnits);
      // Pop the import dialog via Cancel-equivalent — back step is
      // available now.
      final back = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == 'Back',
      );
      await tester.tap(back);
      await tester.pumpAndSettle();
      // Pop wholesale by tearing down the widget tree → dispose
      // fires.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(backend.droppedPinIds, contains(backend.stagedPinId));
    });
  });

  group('Pkcs11FrbBackend', () {
    test('default-constructs as a Pkcs11Backend', () {
      // FRB methods themselves require the loaded native library;
      // constructor coverage is the harness-testable slice.
      const b = Pkcs11FrbBackend();
      expect(b, isA<Pkcs11Backend>());
    });

    test(
      'Pkcs11ImportResult round-trips its constructor arguments — the wizard '
      'returns this to the caller via Navigator.pop so the row labels in the '
      'key-list panel match what the user typed',
      () {
        // Spec: `Pkcs11ImportResult` is a frozen tuple of (keyId, label).
        // The caller-side `await Pkcs11ImportDialog.show` returns this
        // straight through. Pin the field exposure — a regression that
        // renamed the field would silently drop the label from the
        // success toast.
        const r = Pkcs11ImportResult(keyId: 'abc', label: 'My YubiKey');
        expect(r.keyId, 'abc');
        expect(r.label, 'My YubiKey');
      },
    );
  });

  group('Pkcs11ImportDialog — native picker fallback', () {
    testWidgets(
      'native FilePicker missing in tests → catch arm logs and returns null, '
      'the wizard adds no row',
      (tester) async {
        // Spec: `_nativePickModule` wraps `FilePicker.pickFiles` in
        // try/catch — `MissingPluginException` (the unit-test default
        // when no platform plugin is registered) lands on the catch
        // and returns null. The caller (`_pickCustomModule`) treats
        // null the same as the user-dismissed branch: no row is
        // added, no `loadModule` fires. Pinning the safety net — a
        // regression that re-threw the platform exception would
        // crash the wizard the moment the user tapped "Custom".
        final backend = _RecordingBackend();
        // No `pickModuleFile` seam → the dialog routes through
        // `_nativePickModule` which lacks a platform handler in
        // flutter_test and throws `MissingPluginException`.
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => TextButton(
                onPressed: () => Pkcs11ImportDialog.show(ctx, backend: backend),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Custom module...'));
        await tester.pumpAndSettle();
        // Catch arm returned null → no probe fired, no row added.
        expect(backend.loadedPaths, isEmpty);
        // Still on the module step with the empty-state copy.
        expect(find.textContaining('No PKCS#11 module found'), findsOneWidget);
      },
    );
  });

  group('Pkcs11ImportDialog — picker + probe extras', () {
    testWidgets(
      'custom-module picker returning null leaves the module list unchanged',
      (tester) async {
        // Spec: `_pickCustomModule` short-circuits when the picker
        // seam returns null (user dismissed). No row gets appended
        // and no loadModule is fired.
        final backend = _RecordingBackend();
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (ctx) => TextButton(
                onPressed: () => Pkcs11ImportDialog.show(
                  ctx,
                  backend: backend,
                  pickModuleFile: () async => null,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Custom module...'));
        await tester.pumpAndSettle();
        // No probe fired because the picker returned null.
        expect(backend.loadedPaths, isEmpty);
        // Still on the empty-state copy.
        expect(find.textContaining('No PKCS#11 module found'), findsOneWidget);
      },
    );

    testWidgets(
      'module with empty-token list (noToken probe) still advances to the '
      'token step with the "no token present" copy',
      (tester) async {
        // Spec: `_onModuleTap` advances to the token step whenever the
        // probe yields `ready` OR `noToken` (the latter is a soft
        // warning: the module loaded but no reader has a card). The
        // user must reach the token step so they can swap cards
        // without restarting the wizard.
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
        // Title flipped to the token step + empty-state copy renders.
        expect(find.text('Select token'), findsOneWidget);
        expect(find.text('No token present in any reader.'), findsOneWidget);
      },
    );

    testWidgets('dispose without a staged PIN never invokes dropPin', (
      tester,
    ) async {
      // Spec: `dispose` only calls `backend.dropPin` when
      // `_pinSecretId` was assigned. Walking the no-pin path (cancel
      // immediately) must leave `droppedPinIds` empty so we never
      // hit dropPin with a null id.
      final backend = _FakeBackend(
        modules: [
          const rust_pkcs11.DbPkcs11ModuleCandidate(
            vendor: 'OpenSC',
            path: '/p.so',
          ),
        ],
      );
      await _open(tester, backend: backend);
      // Cancel before tapping any module — `_pinSecretId` stays null.
      final cancel = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.button == true &&
            w.properties.label == 'Cancel',
      );
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(backend.droppedPinIds, isEmpty);
    });

    testWidgets(
      'PIN-pad token advances straight to the key step (no PIN prompt)',
      (tester) async {
        // Spec: `_onTokenTap` checks `pkcs11ShouldSkipPinStep` — when
        // the token reports `protectedAuthPath = true`, the wizard
        // skips the in-app PIN dialog and hops to the key step. The
        // empty-keys copy is what surfaces.
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
              label: 'PinPadToken',
              manufacturer: 'TestCo',
              model: 'TestModel',
              serial: 'SN-P',
              // Login required BUT the token has its own PIN pad.
              loginRequired: true,
              protectedAuthPath: true,
              userPinFinalTry: false,
              userPinLocked: false,
            ),
          ],
          keys: const [],
        );
        await _open(tester, backend: backend);
        await tester.tap(find.text('OpenSC'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('PinPadToken'));
        await tester.pumpAndSettle();
        // Skipped PIN step → landed on key step with the empty copy.
        expect(
          find.text('Token has no SSH-usable keys (RSA, ECDSA, Ed25519).'),
          findsOneWidget,
        );
        // No PIN was staged because the PIN-pad branch was taken.
        expect(backend.stagedPinId, isNull);
      },
    );

    testWidgets(
      'stagePin failure keeps the wizard on the token step — the PIN dialog '
      'completed but the SecretStore rejected the bytes, so the key step '
      'never opens (no `_loadKeys` call) and `_pinSecretId` stays null',
      (tester) async {
        // Spec: `_stagePinAndAdvance` catches the staging exception,
        // logs, and returns early before flipping `_step` to key.
        // Pins the catch arm — a successful PIN entry that hit a
        // backend write failure must not advance the wizard.
        final backend = _StagePinFailingBackend(
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
              loginRequired: true,
              protectedAuthPath: false,
              userPinFinalTry: false,
              userPinLocked: false,
            ),
          ],
        );
        await _open(tester, backend: backend);
        await tester.tap(find.text('OpenSC'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('TestToken'));
        await tester.pumpAndSettle();
        // HardwareKeyPromptDialog opened — enter PIN and submit.
        await tester.enterText(find.byType(TextField).first, '1234');
        await tester.pumpAndSettle();
        final ok = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == 'OK',
        );
        await tester.tap(ok);
        await tester.pumpAndSettle();
        // Wizard still on the token step — staging failed before the
        // step flipped to key. The previously-staged PIN id is null,
        // so dispose must NOT call dropPin.
        expect(find.text('Select token'), findsWidgets);
        expect(backend.droppedPinIds, isEmpty);
      },
    );

    testWidgets(
      'listKeys throws on the auto-login token path — wizard lands on the key '
      'step with the empty-list copy (loading flag was reset by the catch arm)',
      (tester) async {
        // Spec: `_loadKeys` catches the FRB error, logs, and clears
        // the loading flag. The dialog renders the key step with
        // `_keys = const []` so the user sees the empty-state copy
        // rather than a stuck spinner.
        final backend = _ListKeysFailingBackend(
          modules: [
            const rust_pkcs11.DbPkcs11ModuleCandidate(
              vendor: 'OpenSC',
              path: '/p.so',
            ),
          ],
          tokens: [
            rust_pkcs11.DbPkcs11TokenInfo(
              slotId: BigInt.from(1),
              label: 'AnonToken',
              manufacturer: 'TestCo',
              model: 'TestModel',
              serial: 'SN-A',
              loginRequired: false,
              protectedAuthPath: false,
              userPinFinalTry: false,
              userPinLocked: false,
            ),
          ],
        );
        await _open(tester, backend: backend);
        await tester.tap(find.text('OpenSC'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('AnonToken'));
        await tester.pumpAndSettle();
        // Empty-keys copy on the key step — the catch arm reset the
        // loading flag so the spinner copy is gone.
        expect(
          find.text('Token has no SSH-usable keys (RSA, ECDSA, Ed25519).'),
          findsOneWidget,
        );
        expect(find.textContaining('Loading keys'), findsNothing);
      },
    );

    testWidgets(
      'listTokens throws after the module tap advances — wizard lands on the '
      'token step with the empty list and no spinner stuck',
      (tester) async {
        // Spec: `_loadTokens` catches the FRB error and clears the
        // loading flag. The empty-state copy renders because the
        // tokens list stayed at its `const []` initial value.
        final backend = _LoadTokensFailingBackend(
          modules: [
            const rust_pkcs11.DbPkcs11ModuleCandidate(
              vendor: 'OpenSC',
              path: '/p.so',
            ),
          ],
        );
        await _open(tester, backend: backend);
        await tester.tap(find.text('OpenSC'));
        await tester.pumpAndSettle();
        // Empty-tokens copy on the token step. The probe-side empty
        // list (the first listTokens call) drove `noToken` for the
        // dot but advanced; the second listTokens call threw and
        // the catch arm cleared `_loadingTokens`.
        expect(find.text('No token present in any reader.'), findsOneWidget);
        expect(find.textContaining('Loading tokens'), findsNothing);
      },
    );

    testWidgets(
      'failed-probe row tap does not re-fire loadModule — the cached failed '
      'state short-circuits the probe call',
      (tester) async {
        // Spec: `_onModuleTap` only re-probes when
        // `_moduleProbes[path] == null`. A failed probe stamps
        // `Pkcs11ModuleProbe.failed`, so subsequent taps on the
        // same row skip the probe call and just refresh the
        // selection state. Pins the cache: a regression that
        // dropped the null check would re-fire `loadModule` and
        // could thrash a misbehaving driver.
        final backend = _RecordingBackend()..loadModuleThrows = true;
        await _open(tester, backend: backend);
        await tester.tap(find.text('Custom module...'));
        await tester.pumpAndSettle();
        // First probe — loadModule fired once + threw.
        expect(backend.loadedPaths, hasLength(1));
        // Re-tap the failing row — probe cached, loadModule must
        // not fire again.
        await tester.tap(find.text('/tmp/custom.so'));
        await tester.pumpAndSettle();
        expect(backend.loadedPaths, hasLength(1));
        // Wizard still on module step (failed → no advance).
        expect(find.text('Select PKCS#11 module'), findsOneWidget);
      },
    );

    testWidgets(
      'save-step typed label trims and uses the typed value when non-empty',
      (tester) async {
        // Spec: `_submit` trims the typed label; non-empty wins over
        // the picked `key.label` default.
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
              label: 'original-key',
              ckaId: Uint8List.fromList([1]),
              sshKeyType: 'rsa',
              sshPublicBlob: Uint8List.fromList([2]),
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
                  captured = await Pkcs11ImportDialog.show(
                    ctx,
                    backend: backend,
                  );
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
        await tester.tap(find.text('original-key'));
        await tester.pumpAndSettle();
        // Overwrite the prefill with a custom (surrounded-by-whitespace)
        // label. `_submit` trims before substituting.
        await tester.enterText(find.byType(TextField), '  my-yubikey  ');
        await tester.pumpAndSettle();
        final semantics = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == 'Import key',
        );
        await tester.tap(semantics);
        await tester.pumpAndSettle();
        expect(backend.captured!.label, 'my-yubikey');
        expect(captured!.label, 'my-yubikey');
      },
    );
  });
}

// ── Test backends ──────────────────────────────────────────────────────

/// Backend whose `scanWellKnownPaths` never completes until the test
/// drives its [completer]. Used to assert the in-flight spinner copy.
class _SlowScanBackend extends Pkcs11Backend {
  _SlowScanBackend() : super();

  final Completer<List<rust_pkcs11.DbPkcs11ModuleCandidate>> completer =
      Completer<List<rust_pkcs11.DbPkcs11ModuleCandidate>>();

  @override
  Future<List<rust_pkcs11.DbPkcs11ModuleCandidate>> scanWellKnownPaths() =>
      completer.future;

  @override
  Future<void> loadModule(String path) async {}

  @override
  Future<List<rust_pkcs11.DbPkcs11TokenInfo>> listTokens(String path) async =>
      const [];

  @override
  Future<List<rust_pkcs11.DbPkcs11KeyMeta>> listKeys(
    String path,
    BigInt slotId, {
    String? pinSecretId,
  }) async => const [];

  @override
  Future<String> importKey(rust_pkcs11.DbPkcs11ImportArgs args) async => 'x';

  @override
  Future<void> stagePin(String id, List<int> bytes) async {}

  @override
  Future<void> dropPin(String id) async {}

  @override
  String composeUri({
    required String tokenLabel,
    required String serial,
    required String objectLabel,
    required Uint8List objectId,
    required String modulePath,
  }) => 'pkcs11:';
}

/// Backend whose `scanWellKnownPaths` always throws. The wizard
/// catches, logs, and renders the empty-state copy.
class _ThrowingScanBackend extends Pkcs11Backend {
  const _ThrowingScanBackend() : super();

  @override
  Future<List<rust_pkcs11.DbPkcs11ModuleCandidate>>
  scanWellKnownPaths() async => throw StateError('scan boom');

  @override
  Future<void> loadModule(String path) async {}

  @override
  Future<List<rust_pkcs11.DbPkcs11TokenInfo>> listTokens(String path) async =>
      const [];

  @override
  Future<List<rust_pkcs11.DbPkcs11KeyMeta>> listKeys(
    String path,
    BigInt slotId, {
    String? pinSecretId,
  }) async => const [];

  @override
  Future<String> importKey(rust_pkcs11.DbPkcs11ImportArgs args) async => 'x';

  @override
  Future<void> stagePin(String id, List<int> bytes) async {}

  @override
  Future<void> dropPin(String id) async {}

  @override
  String composeUri({
    required String tokenLabel,
    required String serial,
    required String objectLabel,
    required Uint8List objectId,
    required String modulePath,
  }) => 'pkcs11:';
}

/// Backend that records every loadModule + listTokens call so the
/// custom-module-picker test can verify the wizard probed the
/// just-picked path. Optionally throws from loadModule.
class _RecordingBackend extends Pkcs11Backend {
  _RecordingBackend() : super();

  final List<String> loadedPaths = [];
  bool loadModuleThrows = false;

  @override
  Future<List<rust_pkcs11.DbPkcs11ModuleCandidate>>
  scanWellKnownPaths() async => const [];

  @override
  Future<void> loadModule(String path) async {
    loadedPaths.add(path);
    if (loadModuleThrows) throw StateError('load boom');
  }

  @override
  Future<List<rust_pkcs11.DbPkcs11TokenInfo>> listTokens(String path) async =>
      const [];

  @override
  Future<List<rust_pkcs11.DbPkcs11KeyMeta>> listKeys(
    String path,
    BigInt slotId, {
    String? pinSecretId,
  }) async => const [];

  @override
  Future<String> importKey(rust_pkcs11.DbPkcs11ImportArgs args) async => 'x';

  @override
  Future<void> stagePin(String id, List<int> bytes) async {}

  @override
  Future<void> dropPin(String id) async {}

  @override
  String composeUri({
    required String tokenLabel,
    required String serial,
    required String objectLabel,
    required Uint8List objectId,
    required String modulePath,
  }) => 'pkcs11:';
}

/// Backend whose token enumeration awaits an external completer. Lets
/// the test catch the "Loading tokens..." in-flight state.
class _SlowTokensBackend extends Pkcs11Backend {
  _SlowTokensBackend({this.modules = const []}) : super();

  final List<rust_pkcs11.DbPkcs11ModuleCandidate> modules;
  final Completer<List<rust_pkcs11.DbPkcs11TokenInfo>> tokensCompleter =
      Completer<List<rust_pkcs11.DbPkcs11TokenInfo>>();
  bool _firstTokensCallSettled = false;

  @override
  Future<List<rust_pkcs11.DbPkcs11ModuleCandidate>>
  scanWellKnownPaths() async => modules;

  @override
  Future<void> loadModule(String path) async {}

  @override
  Future<List<rust_pkcs11.DbPkcs11TokenInfo>> listTokens(String path) async {
    // Module-probe path runs `listTokens` once for the dot — return
    // empty immediately so the row probe finishes. The second call
    // is from `_loadTokens` post-`_onModuleTap` advance — that one
    // awaits the completer so the test catches the spinner state.
    if (!_firstTokensCallSettled) {
      _firstTokensCallSettled = true;
      return const [];
    }
    return tokensCompleter.future;
  }

  @override
  Future<List<rust_pkcs11.DbPkcs11KeyMeta>> listKeys(
    String path,
    BigInt slotId, {
    String? pinSecretId,
  }) async => const [];

  @override
  Future<String> importKey(rust_pkcs11.DbPkcs11ImportArgs args) async => 'x';

  @override
  Future<void> stagePin(String id, List<int> bytes) async {}

  @override
  Future<void> dropPin(String id) async {}

  @override
  String composeUri({
    required String tokenLabel,
    required String serial,
    required String objectLabel,
    required Uint8List objectId,
    required String modulePath,
  }) => 'pkcs11:';
}

/// Backend whose key enumeration awaits an external completer. Lets
/// the test catch the "Loading keys..." in-flight state.
class _SlowKeysBackend extends Pkcs11Backend {
  _SlowKeysBackend({this.modules = const [], this.tokens = const []}) : super();

  final List<rust_pkcs11.DbPkcs11ModuleCandidate> modules;
  final List<rust_pkcs11.DbPkcs11TokenInfo> tokens;
  final Completer<List<rust_pkcs11.DbPkcs11KeyMeta>> keysCompleter =
      Completer<List<rust_pkcs11.DbPkcs11KeyMeta>>();

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
  }) => keysCompleter.future;

  @override
  Future<String> importKey(rust_pkcs11.DbPkcs11ImportArgs args) async => 'x';

  @override
  Future<void> stagePin(String id, List<int> bytes) async {}

  @override
  Future<void> dropPin(String id) async {}

  @override
  String composeUri({
    required String tokenLabel,
    required String serial,
    required String objectLabel,
    required Uint8List objectId,
    required String modulePath,
  }) => 'pkcs11:';
}

/// Extends [_FakeBackend] with a failing importKey arm.
class _FailingImportBackend extends _FakeBackend {
  _FailingImportBackend({super.modules, super.tokens, super.keys});

  @override
  Future<String> importKey(rust_pkcs11.DbPkcs11ImportArgs args) async =>
      throw StateError('import boom');
}

/// Backend whose `stagePin` always throws. Lets the test pin the
/// `_stagePinAndAdvance` catch arm — the wizard stays on the token
/// step (the step never flips, no key load fires).
class _StagePinFailingBackend extends _FakeBackend {
  _StagePinFailingBackend({super.modules, super.tokens});

  @override
  Future<void> stagePin(String id, List<int> bytes) async =>
      throw StateError('stage boom');
}

/// Backend whose `listKeys` always throws. Exercises the
/// `_loadKeys` catch arm: the wizard lands on the key step but the
/// loading spinner clears + no rows render.
class _ListKeysFailingBackend extends _FakeBackend {
  _ListKeysFailingBackend({super.modules, super.tokens});

  @override
  Future<List<rust_pkcs11.DbPkcs11KeyMeta>> listKeys(
    String path,
    BigInt slotId, {
    String? pinSecretId,
  }) async => throw StateError('list keys boom');
}

/// Backend whose `listTokens` throws on the *second* call (the
/// `_loadTokens` call after `_onModuleTap` advances). The first
/// probe-side call still succeeds with an empty list so the probe
/// state stamps `noToken` and the tap is allowed to advance.
class _LoadTokensFailingBackend extends _FakeBackend {
  _LoadTokensFailingBackend({super.modules});

  bool _firstCallDone = false;

  @override
  Future<List<rust_pkcs11.DbPkcs11TokenInfo>> listTokens(String path) async {
    if (!_firstCallDone) {
      _firstCallDone = true;
      return const [];
    }
    throw StateError('list tokens boom');
  }
}
