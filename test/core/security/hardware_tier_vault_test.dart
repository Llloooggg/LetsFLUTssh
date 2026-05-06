import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/hardware_tier_vault.dart';

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // resolveAuthValue routes through `lfs_core::security::hardware_tier_vault`
  // — bootstrap FRB so HMAC + isolation grammar works.
  setUpAll(requireFrbLoaded);

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
  });

  group('HardwareTierVault.resolveAuthValue', () {
    final salt = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

    test('password+biometric false → empty Uint8List (isolation-only)', () {
      final auth = HardwareTierVault.resolveAuthValue(
        password: false,
        biometric: false,
        salt: salt,
      );
      expect(auth, isNotNull);
      expect(auth, isEmpty);
    });

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
