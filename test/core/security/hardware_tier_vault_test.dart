import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/hardware_tier_vault.dart';
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // resolveAuthValue routes through `lfs_core::security::hardware_tier_vault`
  // — bootstrap FRB so HMAC + isolation grammar works. The `isStored` /
  // `read` / `store` paths additionally reach into the pinned support
  // dir for the salt file; pin a fresh temp dir so the dispatch
  // assertions see a clean install rather than whatever a prior test
  // file left behind.
  late Directory tmp;
  setUpAll(() async {
    await requireFrbLoaded();
    tmp = Directory.systemTemp.createTempSync('lfs_hw_vault_');
    rust_config.configStoreInit(supportDir: tmp.path);
  });
  tearDownAll(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  HardwareTierVault newVault() => HardwareTierVault();

  group('HardwareTierVault', () {
    // Per-platform store/read round-trip lives in the Rust unit
    // suite — `lfs_core::security::hardware_tier_vault::linux::tests`
    // (Linux), `lfs_os_security::hardware_tier_vault::apple::tests`
    // (Apple), `lfs_os_security::android::hardware_vault::tests`
    // (Android). The Dart-side façade is just dispatch; covering it
    // again here would require either a real TPM (CI flake) or
    // a Dart-side mock seam that no longer exists post-migration
    // (the orchestrator runs `tpm2-tools` as a Rust subprocess via
    // FRB rather than a Dart `TpmClient` stub).

    test('non-Linux non-Rust-supported targets report unavailable', () async {
      // On a host that's neither Apple/Android/Linux/Windows the
      // façade falls through to the always-false branch. The
      // Linux test host this suite runs under will route to
      // `linux::is_available()` which returns true iff a TPM
      // is reachable — in unit-test CI it isn't, so the
      // expectation matches.
      if (Platform.isMacOS ||
          Platform.isIOS ||
          Platform.isAndroid ||
          Platform.isWindows) {
        return;
      }
      final available = await newVault().isAvailable();
      expect(available, isFalse);
    });

    test('isStored returns false on a fresh install — no salt file and no '
        'sealed envelope yet', () async {
      // The contract is "both halves required — a half-wiped state is a
      // reset, not an unlock". On a Linux CI host without TPM the
      // Rust-side `is_stored` returns false; on the non-Linux branch
      // the Dart code short-circuits when the salt read returns null.
      // Either way a clean install must surface as not-stored.
      expect(await newVault().isStored(), isFalse);
    });

    test(
      'read returns null when no vault is stored — wrong PIN / missing state '
      'collapse into a single "treat as cancelled" sentinel',
      () async {
        // The rate limiter that surrounds this method needs a single
        // null sentinel for both "you typed the wrong PIN" and "there's
        // nothing here yet"; a refactor that started throwing on the
        // missing-state branch would crash the unlock flow.
        final result = await newVault().read('whatever');
        expect(result, isNull);
      },
    );

    test('store returns false on a host where hardware tier is unavailable — '
        'no envelope written, no half-state left behind', () async {
      // On a Linux unit-test host the Rust `is_available` returns
      // false (no TPM); the façade gates on that and never reaches
      // the platform-vault store. The contract is "false means we
      // did not touch persistent state" so callers can surface a
      // localised "Hardware tier not supported" message.
      if (Platform.isMacOS ||
          Platform.isIOS ||
          Platform.isAndroid ||
          Platform.isWindows) {
        return;
      }
      final ok = await newVault().store(
        dbKey: Uint8List.fromList(List<int>.filled(32, 0x42)),
        pin: '1234',
      );
      expect(ok, isFalse);
    });

    test(
      'storeFromSecret returns false on a host where hardware tier is '
      'unavailable — same contract as store, just SecretRef-flavoured',
      () async {
        // The SecretRef variant must observe the same "no half-state"
        // invariant as the byte-array store; the gate is the same
        // `isAvailable` check.
        if (Platform.isMacOS ||
            Platform.isIOS ||
            Platform.isAndroid ||
            Platform.isWindows) {
          return;
        }
        final ok = await newVault().storeFromSecret(
          secretId: 'unit-test.staging.absent',
          pin: '1234',
        );
        expect(ok, isFalse);
      },
    );

    test('clear is best-effort and never throws on a fresh install — wipe '
        'path must keep going past missing files', () async {
      // Wipe / tier-switch may run when nothing is stored yet (user
      // toggles biometrics off before ever turning it on). The
      // façade swallows the Rust-side error and completes; a
      // regression that propagated would crash the tier-switch.
      await expectLater(newVault().clear(), completes);
    });

    test('isBiometricPasswordStored returns false on a fresh install — overlay '
        'is opt-in and starts absent', () async {
      // The overlay file (Linux: hardware_vault_password_overlay_linux.bin;
      // other platforms: platform-bound NCrypt / Keystore / SE slot)
      // must not exist on a clean install. False here is what tells
      // the unlock UI to fall back to typed password.
      expect(await newVault().isBiometricPasswordStored(), isFalse);
    });
  });

  group('HardwareTierVault.resolveAuthValue', () {
    final salt = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

    test(
      'password+biometric false → null (Hardware tier always password-gated)',
      () {
        final auth = HardwareTierVault.resolveAuthValue(
          password: false,
          biometric: false,
          salt: salt,
        );
        expect(auth, isNull);
      },
    );

    test('password=true without typedPassword → null', () {
      expect(
        HardwareTierVault.resolveAuthValue(
          password: true,
          biometric: false,
          salt: salt,
        ),
        isNull,
      );
    });

    test('password=true with empty typedPassword → null', () {
      expect(
        HardwareTierVault.resolveAuthValue(
          password: true,
          biometric: false,
          salt: salt,
          typedPassword: '',
        ),
        isNull,
      );
    });

    test('password path returns 32-byte HMAC stable across calls', () {
      final a = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: false,
        salt: salt,
        typedPassword: 'hunter2',
      );
      final b = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: false,
        salt: salt,
        typedPassword: 'hunter2',
      );
      expect(a, hasLength(32));
      expect(a, b, reason: 'same inputs → same HMAC');
    });

    test('biometric=true without a fprintd hash → null', () {
      expect(
        HardwareTierVault.resolveAuthValue(
          password: true,
          biometric: true,
          salt: salt,
          typedPassword: 'whatever',
        ),
        isNull,
      );
    });

    test('biometric=true wins over password when both provided', () {
      // The wizard invariant says biometric=true implies password=true,
      // and when the fprintd hash is present it is the authoritative
      // auth source. A refactor that reversed that would silently fall
      // back to typedPassword when fprintd was live.
      final fprintd = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]);
      final bioAuth = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: true,
        salt: salt,
        typedPassword: 'ignored',
        fprintdHash: fprintd,
      );
      final pwAuth = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: false,
        salt: salt,
        typedPassword: 'ignored',
      );
      expect(bioAuth, isNotNull);
      expect(bioAuth, hasLength(32));
      expect(
        bioAuth,
        isNot(equals(pwAuth)),
        reason: 'bio auth derives from the fprintd hash, not the password',
      );
    });

    test('different salts produce different auth values', () {
      final a = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: false,
        salt: Uint8List.fromList(List<int>.filled(32, 0)),
        typedPassword: 'same',
      );
      final b = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: false,
        salt: Uint8List.fromList(List<int>.filled(32, 1)),
        typedPassword: 'same',
      );
      expect(a, isNot(equals(b)));
    });
  });
}
