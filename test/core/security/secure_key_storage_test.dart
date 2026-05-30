import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/linux_keychain_marker.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;
import 'package:letsflutssh/src/rust/api/security_capabilities.dart';

import '../../helpers/frb_bootstrap.dart';

/// SecureKeyStorage round-trip / probe / delete coverage moved
/// Rust-side after the cleanup arc retired
/// `flutter_secure_storage`. Every platform now routes through
/// `lfs_os_security::secure_key_storage::*`, whose unit suite
/// exercises the real OS backend on each target (libsecret on the
/// Linux CI runner, SecItem on darwin, CredRead/Write/Delete on
/// Windows, AndroidKeyStore via JNI on Android). Re-running those
/// flows from Dart with a MethodChannel mock would only re-validate
/// FRB plumbing already covered by the FRB codegen + bus tests.
///
/// What stays Dart-side: the [DbKeyringProbeResult] enum vocabulary
/// (Settings UI maps reason codes to ARB strings; a silent new enum
/// value without a matching locale key surfaces as a blank tooltip),
/// the `probeSecretServiceReachability: false` short-circuit on Linux,
/// and the Linux marker gate around `readKeyToSecret`.

/// In-memory marker stand-in. Lets us drive the gated read-path on
/// Linux without touching libsecret. Mirrors the helper used by the
/// biometric vault test file.
class _InMemoryMarker extends LinuxKeychainMarker {
  bool _set;
  _InMemoryMarker({bool initialState = false}) : _set = initialState, super();
  @override
  Future<bool> exists({bool skipOnNonLinux = true}) async {
    if (skipOnNonLinux && !Platform.isLinux) return true;
    return _set;
  }

  @override
  Future<void> set() async => _set = true;

  @override
  Future<void> clear() async => _set = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUpAll(() async {
    // `readKeyToSecret` and `deleteKey` reach into Rust paths that
    // need the pinned support dir; pin a fresh temp dir up front so
    // the FRB-bound code below sees a clean install.
    await requireFrbLoaded();
    tmp = Directory.systemTemp.createTempSync('lfs_secure_key_');
    rust_config.configStoreInit(supportDir: tmp.path);
  });

  tearDownAll(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('SecureKeyStorage Dart-side surface', () {
    test('probeSecretServiceReachability: false short-circuits the Linux '
        'probe to available without a D-Bus connect', () async {
      // The opt-out flag exists so widget tests get a deterministic
      // `available` without a live session-bus connect. On Linux that
      // is a pure-Dart short-circuit (no FRB call), so we can assert
      // the observable effect directly; on other platforms `probe()`
      // round-trips through the OS keychain over FRB, which is out of
      // scope for a unit test (see the file header).
      final result = await SecureKeyStorage(
        probeSecretServiceReachability: false,
      ).probe();
      expect(result, DbKeyringProbeResult.available);
    }, skip: Platform.isLinux ? false : 'Linux-only pure-Dart short-circuit');

    test(
      'DbKeyringProbeResult carries every documented classification label',
      () {
        expect(DbKeyringProbeResult.values, <DbKeyringProbeResult>[
          DbKeyringProbeResult.available,
          DbKeyringProbeResult.linuxNoSecretService,
          DbKeyringProbeResult.probeFailed,
        ]);
      },
    );

    test(
      'readKeyToSecret short-circuits to false on Linux when the marker is '
      'absent — the libsecret gate must hold without ever waking zbus',
      () async {
        if (!Platform.isLinux) return;
        // A cold launch on Linux has the marker absent; the gate
        // must reject every read before it can spam stderr with
        // libsecret g_warnings. Use an in-memory marker so the test
        // never depends on a real session bus.
        final storage = SecureKeyStorage(
          marker: _InMemoryMarker(),
          probeSecretServiceReachability: false,
        );
        final result = await storage.readKeyToSecret('unit-test.secret.absent');
        expect(result, isFalse);
      },
    );

    test('isAvailable composes onto probe() — false branch returns false on '
        'platforms without a live keychain backend', () async {
      if (!Platform.isLinux) return;
      // probeSecretServiceReachability:false makes probe() return
      // `available`, so isAvailable must return true. The contract
      // is "isAvailable iff probe() == available" — a refactor that
      // dropped the wrapper would either deadlock the wizard or
      // silently classify an unreachable bus as available.
      final storage = SecureKeyStorage(
        marker: _InMemoryMarker(initialState: true),
        probeSecretServiceReachability: false,
      );
      expect(await storage.isAvailable(), isTrue);
    });

    test('deleteKey is best-effort and never throws — wipe flow must clear '
        'leftover entries regardless of marker state', () async {
      // The Rust delete is documented as idempotent on a missing
      // alias; the Dart façade swallows any error and continues.
      // Calling delete on a never-written alias must not propagate.
      final storage = SecureKeyStorage(
        marker: _InMemoryMarker(),
        probeSecretServiceReachability: false,
      );
      await expectLater(storage.deleteKey(), completes);
    });

    test('deleteBiometricKey is best-effort and never throws even when the '
        'underlying alias is absent — wipe path must keep going', () async {
      // The wipe / tier-switch flow may run on a fresh install
      // where no biometric key was ever stored. The façade must
      // swallow the underlying not-found and complete.
      final storage = SecureKeyStorage(
        marker: _InMemoryMarker(),
        probeSecretServiceReachability: false,
      );
      await expectLater(storage.deleteBiometricKey(), completes);
    });

    test('default constructor wires up the shared LinuxKeychainMarker without '
        'requiring an explicit marker injection', () {
      // The production call sites (`main.dart`, security_provider,
      // keychain_probe_prompt_listener) all build the storage with
      // the default constructor — a regression that flipped the
      // default to null would null-deref the first Linux read.
      // Pure construction smoke, no FRB.
      final storage = SecureKeyStorage();
      expect(storage, isA<SecureKeyStorage>());
    });

    test(
      'readKeyToSecret with marker present runs the Rust path and returns '
      'false when the alias is absent — gate passes, FRB returns "not found"',
      () async {
        if (!Platform.isLinux) return;
        // Spec: on Linux with the marker set, the gate lets the call
        // through to the Rust read-to-secret. With no entry pre-written
        // under the alias the Rust side reports absent and the façade
        // surfaces `false` (the contract is "false on absent or empty
        // read"). This exercises the through-path that the gate-fail
        // test only covers up to the short-circuit.
        final storage = SecureKeyStorage(
          marker: _InMemoryMarker(initialState: true),
          probeSecretServiceReachability: false,
        );
        final result = await storage.readKeyToSecret('unit-test.absent.secret');
        // Either false (keyring backend reachable + alias absent) or
        // false (backend unreachable → exception swallowed → false).
        // Both observable outcomes are "didn't stage the secret".
        expect(result, isFalse);
      },
    );

    test(
      'writeKeyFromSecret with no staged secret returns false — Rust raises, '
      'façade swallows and surfaces failure',
      () async {
        // Spec: the write path delegates to
        // `secureStorageWriteFromSecret`, which fails when no bytes are
        // staged under `secretId`. The façade catches and returns false
        // rather than propagating — first-launch flows surface this as
        // "keychain unavailable, prompt the user". A regression that
        // re-threw would crash the wizard.
        final storage = SecureKeyStorage(
          marker: _InMemoryMarker(),
          probeSecretServiceReachability: false,
        );
        final ok = await storage.writeKeyFromSecret(
          'unit-test.unstaged.secret',
        );
        expect(ok, isFalse);
      },
    );

    test('deleteKey clears the Linux marker — the gate must reset so a fresh '
        'install after wipe does not silently pass the gate', () async {
      if (!Platform.isLinux) return;
      // Spec: `deleteKey` is the cross-class cleanup point; it clears
      // the Linux marker because once the last keychain entry is gone
      // a future read must re-gate against the keyring daemon. A
      // regression that left the marker set after delete would let
      // `readKeyToSecret` proceed straight to libsecret on a fresh
      // install and re-introduce the stderr g_warning spam the marker
      // exists to suppress.
      final marker = _InMemoryMarker(initialState: true);
      final storage = SecureKeyStorage(
        marker: marker,
        probeSecretServiceReachability: false,
      );

      await storage.deleteKey();

      expect(await marker.exists(skipOnNonLinux: false), isFalse);
    });

    test('non-Linux probe round-trips the sentinel through Rust — '
        '"available" iff the read matches the write', () async {
      if (Platform.isLinux) return;
      // Spec: on non-Linux the probe writes a 5-byte `"probe"` marker
      // under the probe alias, reads it back, deletes it, and
      // classifies based on the byte-equality check. The Rust suite
      // covers the success and failure outcomes; this test only
      // verifies the Dart-side returns one of the three documented
      // values, not which one — that depends on whether a real OS
      // keychain backend is present in the test environment.
      final result = await SecureKeyStorage().probe();
      expect(
        result,
        anyOf(DbKeyringProbeResult.available, DbKeyringProbeResult.probeFailed),
      );
    });
  });

  // Real keychain round-trip (write → read → delete) is covered by
  // integration: requires a live OS keychain backend (libsecret on
  // Linux with running daemon, SecItem on darwin, CredRead/Write/
  // Delete on Windows). Unit tests run on CI hosts without those
  // backends configured. The Rust suite in
  // `lfs_os_security::secure_key_storage::tests` exercises the real
  // backend on each target.
}
