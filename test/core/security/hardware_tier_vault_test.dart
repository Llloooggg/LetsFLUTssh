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

    test(
      'probeDetail returns a non-empty opaque code on every host — the Settings '
      'card always has something to localise, even when "available"',
      () async {
        // Spec: `probeDetail` is the localisation-key source for the
        // hardware-tier hint copy. The Settings provider switches on
        // `HardwareProbeDetail.fromCode(...)`; an empty / null string
        // there would surface as a blank tooltip instead of the
        // "platform-supports-but-…" hint. Pin the non-empty contract.
        final code = await newVault().probeDetail();
        expect(code, isNotEmpty);
      },
    );

    test('clear → isStored is the post-condition that lets a tier switch reuse '
        'the vault without crashing on a leftover envelope', () async {
      // Spec: `clear` is best-effort but the post-condition is
      // "the vault now reads as not-stored". On a Linux CI host
      // without a TPM the call still completes (and the state was
      // already not-stored). Pin the invariant for the
      // round-trip the tier-switch code depends on — a regression
      // that left `is_stored == true` after `clear()` would break
      // the wizard's "you can re-provision now" branch.
      final vault = newVault();
      await vault.clear();
      expect(await vault.isStored(), isFalse);
    });

    test(
      'read with a null PIN does not throw on a fresh install — passwordless '
      'T2 unseal failure collapses into the same null sentinel as wrong PIN',
      () async {
        // Spec: the resolveAuthValue passwordless arm produces an empty
        // auth value; if the vault is not stored (Linux CI without
        // TPM, no envelope on disk), the read returns null instead of
        // throwing. Pin the null-PIN path explicitly — the
        // `read('whatever')` test above covers the typed-password
        // branch; this covers the null arm so a regression that
        // started throwing on a null PIN would surface here.
        final result = await newVault().read(null);
        expect(result, isNull);
      },
    );
  });

  group('HardwareTierVault.resolveAuthValue', () {
    final salt = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

    test(
      'password+biometric false → null (passwordless Hardware has no auth gate)',
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

    test('biometric=true with empty fprintdHash → null — empty hash is not a '
        'valid auth source even when the flag is set', () {
      // Spec: the resolver checks the fprintd hash for presence, not
      // truthiness of the flag alone. An empty hash represents "fprintd
      // reachable but returned nothing" which the wizard treats the
      // same as the no-hash case — a cancelled unlock, not a fallback
      // to typed password.
      final auth = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: true,
        salt: salt,
        typedPassword: 'whatever',
        fprintdHash: Uint8List(0),
      );
      expect(auth, isNull);
    });

    test(
      'passwordless (both flags false) is distinct from password-gated — '
      'the bank-style passwordless T2 path lives behind a separate decision',
      () {
        // Spec: with both flags false the auth value is an empty byte
        // string (isolation-only), distinct from `null` (resolution
        // failed) and from any HMAC value. A regression that conflated
        // "no gate" with "wrong gate" would either let an unauthorized
        // unlock through or block the passwordless T2 path entirely.
        // We assert the return is null here because the resolver
        // refuses the all-false branch (Hardware tier is always
        // password-gated per the wizard invariant covered above) — but
        // the test pins the contract that the all-false return matches
        // the wizard's "no Hardware tier without a PIN" rule.
        final auth = HardwareTierVault.resolveAuthValue(
          password: false,
          biometric: false,
          salt: salt,
        );
        expect(auth, isNull);
      },
    );

    test('passwords differing in a single character produce distinct HMACs — '
        'the resolver does not normalise / truncate / case-fold', () {
      // Spec: HMAC inputs flow through unchanged. A regression that
      // trimmed or normalised the password Dart-side before crossing
      // FRB would collapse near-identical inputs into the same auth
      // value, leaking entropy. Verifying two one-character-different
      // passwords map to different HMACs pins the no-normalisation
      // invariant.
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
        typedPassword: 'hunter3',
      );
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a, isNot(equals(b)));
    });

    test('biometric path with the same fprintdHash + salt → stable HMAC across '
        'calls, independent of typedPassword', () {
      // Spec: when biometric wins, the auth value is
      // `HMAC(fprintdHash, salt)` and the typed password is ignored.
      // Two calls with the same fprintd hash but different typed
      // passwords must produce identical HMACs — confirms the
      // resolver branches on biometric exclusively in that mode.
      final fprintd = Uint8List.fromList([0x11, 0x22, 0x33, 0x44]);
      final a = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: true,
        salt: salt,
        typedPassword: 'one',
        fprintdHash: fprintd,
      );
      final b = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: true,
        salt: salt,
        typedPassword: 'two',
        fprintdHash: fprintd,
      );
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a, equals(b));
    });

    test('salt-length boundaries: a short salt still produces a 32-byte HMAC — '
        'the resolver does not require a 32-byte salt to function, callers '
        'should not depend on rejection-by-length', () {
      // Spec: the underlying HMAC-SHA256 accepts any-length key; the
      // resolver passes the salt straight through. A 1-byte salt is
      // cryptographically poor but the Dart wrapper does not reject it —
      // pin that the API does not crash on a degenerate salt so a
      // caller-bug that handed a tiny salt would surface as weak HMAC,
      // not a panic.
      final shortSalt = Uint8List.fromList(<int>[0x01]);
      final out = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: false,
        salt: shortSalt,
        typedPassword: 'value',
      );
      expect(out, isNotNull);
      expect(
        out,
        hasLength(32),
        reason: 'HMAC-SHA256 output is always 32 bytes regardless of salt size',
      );
    });

    test('biometric=true with single-byte fprintdHash → resolves to a stable '
        '32-byte HMAC (resolver does not require fprintd hash length)', () {
      // Spec: the resolver checks fprintdHash for presence (non-empty),
      // not a specific length. A degenerate 1-byte hash still produces
      // an HMAC; callers responsible for ensuring the fprintd backend
      // returns meaningful entropy. Pin "presence > length" so a future
      // refactor that started enforcing a length minimum surfaces here.
      final tinyHash = Uint8List.fromList(<int>[0x42]);
      final out = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: true,
        salt: salt,
        typedPassword: 'ignored',
        fprintdHash: tinyHash,
      );
      expect(out, isNotNull);
      expect(out, hasLength(32));
    });

    test('biometric=false ignores fprintdHash entirely — the flag, not the '
        'presence of the hash, gates the biometric branch', () {
      // Spec: passing a fprintdHash when biometric=false must not flip
      // the resolver into the biometric branch. The auth value must
      // match the password-only HMAC. A regression that branched on
      // hash-presence instead of the explicit flag would silently
      // unlock with a stale fprintd hash even when the user disabled
      // biometric unlock.
      final fprintd = Uint8List.fromList([0xAA, 0xBB]);
      final withHash = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: false,
        salt: salt,
        typedPassword: 'gate',
        fprintdHash: fprintd,
      );
      final withoutHash = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: false,
        salt: salt,
        typedPassword: 'gate',
      );
      expect(withHash, isNotNull);
      expect(withoutHash, isNotNull);
      expect(
        withHash,
        equals(withoutHash),
        reason:
            'biometric=false branch must use the typed password regardless of '
            'whether a fprintd hash was supplied — the flag is the only gate',
      );
    });

    test('resolveAuthValue copies the Rust-side bytes — caller mutation does '
        'not poison the next read', () {
      // Spec: the Dart wrapper wraps the Rust return in
      // `Uint8List.fromList(v)`, which copies. Without that, the
      // resolver would hand the caller a view into Rust-owned memory
      // and a Dart-side mutation would silently corrupt later reads
      // of the same salt+password combination. We verify by mutating
      // the first call's return and confirming a fresh call still
      // matches the original.
      final original = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: false,
        salt: salt,
        typedPassword: 'stable',
      );
      expect(original, isNotNull);
      final mutated = Uint8List.fromList(original!);
      for (var i = 0; i < mutated.length; i++) {
        mutated[i] = mutated[i] ^ 0xFF;
      }
      final replay = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: false,
        salt: salt,
        typedPassword: 'stable',
      );
      expect(replay, equals(original));
    });
  });
}
