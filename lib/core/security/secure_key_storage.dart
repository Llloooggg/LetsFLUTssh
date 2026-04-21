import 'dart:convert';
import 'dart:io' show File, Platform, Process, ProcessException;
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';

/// Thin wrapper around OS keychain for storing the AES-256 encryption key.
///
/// Uses [FlutterSecureStorage] (Keychain on iOS/macOS, Credential Manager on
/// Windows, libsecret on Linux, EncryptedSharedPreferences on Android).
///
/// All methods catch platform exceptions and return null/false — the caller
/// must handle graceful fallback to plaintext or master-password mode.
///
/// Linux-specific: libsecret emits a non-recoverable g_warning to stderr the
/// moment it cannot talk to a running/unlocked keyring daemon. That makes a
/// cold `read` on a system where the keyring was never touched spam stderr
/// on every launch. We sidestep it with a local marker file (see
/// [_markerPath]): on Linux the storage APIs refuse to talk to libsecret
/// unless the marker says the user has previously opted into keychain
/// storage. The marker is written on a successful [writeKey] and cleared by
/// [deleteKey]. Other platforms keep the original behaviour.
class SecureKeyStorage {
  static const _keyName = 'letsflutssh_encryption_key';
  static const _biometricKeyName = 'letsflutssh_biometric_encryption_key';
  static const _probeName = 'letsflutssh_keychain_probe';
  static const _markerFile = 'keychain_enabled';

  /// Production flag flipped by [main.dart] at app startup. Widget
  /// tests running under `FakeAsync` do not set this, so the Linux-
  /// only `Process.run('gdbus', …)` path inside [probe] stays off in
  /// them — any real subprocess spawn leaks a Timer onto FakeAsync's
  /// pending-timer list and makes unrelated widget tests fail. In
  /// production the flag is true from the first frame and the
  /// classified probe runs normally.
  static bool _runtimeSubprocessProbesEnabled = false;

  /// Called from production entry points (`main.dart`) to unlock the
  /// subprocess-backed secret-service ping used by [probe] on Linux.
  /// Widget tests intentionally do not call it.
  static void enableRuntimeSubprocessProbes() {
    _runtimeSubprocessProbesEnabled = true;
  }

  final FlutterSecureStorage _storage;
  final bool _skipPlatformCheck;

  /// When [storage] is provided (tests), platform pre-checks are skipped.
  SecureKeyStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(),
      _skipPlatformCheck = storage != null;

  String? _cachedMarkerPath;

  Future<String> _markerPath() async {
    final cached = _cachedMarkerPath;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, _markerFile);
    _cachedMarkerPath = path;
    return path;
  }

  Future<bool> _markerExists() async {
    try {
      return File(await _markerPath()).exists();
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeMarker() async {
    try {
      final file = File(await _markerPath());
      await file.parent.create(recursive: true);
      await file.writeAsString('1');
      // Marker itself holds nothing sensitive (`'1'`) but lives next
      // to `credentials.kdf` and every other secret file in the app
      // support dir. Keeping it at 0600 is a consistency win — the
      // whole directory shouldn't have one file with a weaker mode
      // than the rest.
      await hardenFilePerms(file.path);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to write keychain marker: $e',
        name: 'SecureKeyStorage',
      );
    }
  }

  Future<void> _clearMarker() async {
    try {
      final file = File(await _markerPath());
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger.instance.log(
        'Failed to clear keychain marker: $e',
        name: 'SecureKeyStorage',
      );
    }
  }

  /// Gate that prevents libsecret calls on Linux until the user has at least
  /// once successfully written to the keychain. On non-Linux platforms (and
  /// in tests with an injected storage) this always lets the call through.
  Future<bool> _linuxGatePass() async {
    if (_skipPlatformCheck || !Platform.isLinux) return true;
    return _markerExists();
  }

  /// Probe whether OS keychain is available at runtime.
  ///
  /// Fast path — env-var + marker-file checks only. No subprocess
  /// spawn, no gdbus ping. Used by the startup [probeCapabilities]
  /// flow where a slow Process.run would delay first-frame render
  /// and confuse test harnesses that pump widgets under FakeAsync
  /// (the pending-timer from `.timeout()` is flagged as a leak).
  ///
  /// The classified [probe] method — called by the Settings UI to
  /// render an actionable "why" line — runs the full gdbus-ping
  /// path. There is no behavioural gap: a system where gdbus
  /// reports "no secret-service" would also fail the very first
  /// `writeKey` attempt, so the user sees the failure either from
  /// the classified Settings tier card or from a one-time write
  /// failure when enabling T1. The classified probe is the
  /// diagnostic; the fast probe is the runtime gate.
  Future<bool> isAvailable() async {
    if (!_hasKeychainSupport()) return false;
    if (Platform.isLinux && !_skipPlatformCheck && !await _markerExists()) {
      return true;
    }
    try {
      const probe = 'probe';
      await _storage.write(key: _probeName, value: probe);
      final readBack = await _storage.read(key: _probeName);
      await _storage.delete(key: _probeName);
      return readBack == probe;
    } catch (e) {
      AppLogger.instance.log(
        'Keychain not available: $e',
        name: 'SecureKeyStorage',
      );
      return false;
    }
  }

  /// Classified keyring probe — distinguishes *why* the OS keychain is
  /// unreachable so the Settings UI can surface an actionable hint
  /// instead of a generic "unavailable on this device" line.
  ///
  /// Design: *concrete probe, every step.* Early iterations pattern-
  /// matched `WSL_DISTRO_NAME` to infer "no keyring here" — a proxy
  /// that mis-classified any WSL install running `gnome-keyring-
  /// daemon` manually and missed any native Linux session with no
  /// keyring daemon. Later iterations simplified to "D-Bus address
  /// present? then assume keyring available" — which was still a
  /// guess: modern WSL2 with WSLg ships `systemd --user` plus a
  /// session bus socket at `/run/user/$UID/bus` but no secret-
  /// service daemon, so `DBUS_SESSION_BUS_ADDRESS` is set yet
  /// `libsecret` still fails.
  ///
  /// The only honest signal is an actual ping to the secret-service
  /// daemon on the session bus. We issue
  /// `gdbus call --session --dest org.freedesktop.secrets
  ///  --object-path /org/freedesktop/secrets
  ///  --method org.freedesktop.DBus.Peer.Ping` — gdbus is part of
  /// GLib and present on every desktop Linux install. Exit code 0
  /// means the service is registered and responds; any other exit
  /// code means the service name is not known on the bus (no
  /// daemon). This is the same semantics `libsecret` uses
  /// internally; probing via `gdbus` up front lets us classify
  /// without spamming stderr on a failure.
  ///
  /// Decision tree:
  ///   1. Non-Linux platforms → live write/read/delete against
  ///      `flutter_secure_storage`. Failure = `probeFailed`.
  ///   2. Linux, [DBUS_SESSION_BUS_ADDRESS] unset → no session bus
  ///      at all → `linuxNoDbusSession`.
  ///   3. Linux, D-Bus address set, gdbus Ping to secret-service
  ///      fails → `linuxNoSecretService`. This is where WSL with
  ///      WSLg lands: D-Bus works, secret-service daemon does not.
  ///   4. Linux, D-Bus set, gdbus Ping succeeds → `available`.
  ///      No live write/read/delete needed — the service is up and
  ///      the caller's first opt-in write will make it past the
  ///      Ping gate.
  Future<KeyringProbeResult> probe() async {
    if (_skipPlatformCheck || !Platform.isLinux) {
      // Windows / macOS / iOS / Android: the backing service is
      // effectively always up on a user device. A failure on these
      // platforms is a real platform-channel error, not an
      // installation gap — surface it as a generic failure.
      try {
        const marker = 'probe';
        await _storage.write(key: _probeName, value: marker);
        final back = await _storage.read(key: _probeName);
        await _storage.delete(key: _probeName);
        return back == marker
            ? KeyringProbeResult.available
            : KeyringProbeResult.probeFailed;
      } catch (e) {
        AppLogger.instance.log(
          'Keychain probe failed on ${Platform.operatingSystem}: $e',
          name: 'SecureKeyStorage',
        );
        return KeyringProbeResult.probeFailed;
      }
    }

    // ── Linux ────────────────────────────────────────────────────
    // D-Bus session bus address is the concrete bootstrap signal —
    // every Linux D-Bus client reads it to find the session bus
    // socket. Absent value = no session bus = no point probing
    // further.
    final dbus = Platform.environment['DBUS_SESSION_BUS_ADDRESS'];
    if (dbus == null || dbus.isEmpty) {
      return KeyringProbeResult.linuxNoDbusSession;
    }
    // Concrete secret-service probe via `gdbus`. WSL with WSLg
    // brings the session bus up but not the keyring daemon, so a
    // bus-address check alone marks the keyring "available" on
    // systems where libsecret will fail. Pinging the service name
    // directly is the matching signal libsecret itself uses.
    //
    // Guarded by [_runtimeSubprocessProbesEnabled]: widget tests
    // running under FakeAsync do not set the flag, so they skip
    // the subprocess entirely (any `Process.run` inside
    // FakeAsync-managed code ends up leaking a Timer onto the
    // pending-timer list and fails unrelated widget tests). In
    // production the flag is set from `main.dart` before the
    // first provider evaluates.
    if (_runtimeSubprocessProbesEnabled) {
      try {
        final result = await Process.run('gdbus', const [
          'call',
          '--session',
          '--dest',
          'org.freedesktop.secrets',
          '--object-path',
          '/org/freedesktop/secrets',
          '--method',
          'org.freedesktop.DBus.Peer.Ping',
        ], runInShell: false);
        if (result.exitCode != 0) {
          return KeyringProbeResult.linuxNoSecretService;
        }
      } on ProcessException catch (e) {
        // `gdbus` binary missing. GLib not installed → extremely
        // unusual on a desktop Linux, treat as a generic probe
        // failure. Falls through to the live probe below.
        AppLogger.instance.log(
          'gdbus binary missing — falling back to live probe: $e',
          name: 'SecureKeyStorage',
        );
      } catch (e) {
        AppLogger.instance.log(
          'gdbus secret-service ping failed: $e',
          name: 'SecureKeyStorage',
        );
        return KeyringProbeResult.linuxNoSecretService;
      }
    }
    // Fall-through: gdbus probe succeeded OR gdbus is missing
    // entirely. In both cases, optimism — return available unless
    // the user has opted in and a live probe then fails. The
    // marker-file optimisation keeps us from waking the keyring
    // unlock prompt on every fresh launch.
    if (!await _markerExists()) return KeyringProbeResult.available;
    try {
      const marker = 'probe';
      await _storage.write(key: _probeName, value: marker);
      final back = await _storage.read(key: _probeName);
      await _storage.delete(key: _probeName);
      return back == marker
          ? KeyringProbeResult.available
          : KeyringProbeResult.linuxNoSecretService;
    } catch (e) {
      AppLogger.instance.log(
        'Linux libsecret probe failed: $e',
        name: 'SecureKeyStorage',
      );
      return KeyringProbeResult.linuxNoSecretService;
    }
  }

  /// Quick pre-flight check before touching the native keychain API.
  ///
  /// On Linux, libsecret requires a running keyring daemon reachable via
  /// D-Bus. Without it, every call logs a noisy `g_warning` to stderr
  /// that we cannot suppress from Dart. The only concrete signal we can
  /// check without spawning a subprocess is the session-bus address
  /// environment variable every D-Bus client reads at startup — if it
  /// is unset, libsecret cannot even begin. Earlier revisions also
  /// pattern-matched `WSL_DISTRO_NAME` to short-circuit WSL hosts, but
  /// that was a distro guess (WSL happens to ship without a keyring
  /// daemon) that mis-classifies any WSL install with libsecret
  /// configured. The D-Bus address check catches the real signal —
  /// headless sessions and bare WSL both lack it — without pretending
  /// to know why.
  bool _hasKeychainSupport() {
    if (_skipPlatformCheck || !Platform.isLinux) return true;

    // No D-Bus session → no keyring.
    final dbus = Platform.environment['DBUS_SESSION_BUS_ADDRESS'];
    if (dbus == null || dbus.isEmpty) {
      AppLogger.instance.log(
        'No D-Bus session bus — skipping keychain probe',
        name: 'SecureKeyStorage',
      );
      return false;
    }

    return true;
  }

  /// Read the encryption key from OS keychain.
  ///
  /// Returns null if the key does not exist or keychain is unavailable.
  /// On Linux also returns null without touching libsecret when the marker
  /// file is missing — that's the path used at every app startup before the
  /// user opts into keychain storage, and it's what used to trigger the
  /// `libsecret_error: Failed to unlock the keyring` warning.
  Future<Uint8List?> readKey() async {
    if (!_hasKeychainSupport()) return null;
    if (!await _linuxGatePass()) return null;
    try {
      final value = await _storage.read(key: _keyName);
      if (value == null) return null;
      return base64Decode(value);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to read key from keychain: $e',
        name: 'SecureKeyStorage',
      );
      return null;
    }
  }

  /// Store the encryption key in OS keychain.
  ///
  /// Returns false if the write fails. On a successful write on Linux also
  /// lays down the marker file that unlocks subsequent [readKey] calls.
  Future<bool> writeKey(Uint8List key) async {
    if (!_hasKeychainSupport()) return false;
    try {
      await _storage.write(key: _keyName, value: base64Encode(key));
      if (Platform.isLinux && !_skipPlatformCheck) await _writeMarker();
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'Failed to write key to keychain: $e',
        name: 'SecureKeyStorage',
      );
      return false;
    }
  }

  /// Variant of [writeKey] that stores the key under a biometric-
  /// gated access-control policy.
  ///
  /// On Apple (iOS / macOS) the entry is written with
  /// `AccessControlFlag.biometryCurrentSet` so any biometric
  /// enrolment change (adding / removing a finger, re-enrolling Face
  /// ID) invalidates the stored key and forces re-entry of the typed
  /// password. On Android `flutter_secure_storage`'s
  /// `AndroidOptions(encryptedSharedPreferences: true)` does the
  /// best available job inside the package's current API surface;
  /// the stronger native-backed biometric-gated Keystore flow routes
  /// through the hardware-vault plugin (`storeBiometricPassword` /
  /// `readBiometricPassword`) rather than this path. On Linux and
  /// Windows `flutter_secure_storage` does not expose a biometric
  /// ACL option in this package — the write falls through to a
  /// plain entry and the caller is responsible for gating access
  /// via the platform's own biometric prompt before calling
  /// [readBiometricKey].
  ///
  /// Paired with [readBiometricKey]; the two share the alias so a
  /// biometric-written key cannot be read back via [readKey] and
  /// vice versa.
  Future<bool> writeBiometricKey(Uint8List key) async {
    if (!_hasKeychainSupport()) return false;
    try {
      await _storage.write(
        key: _biometricKeyName,
        value: base64Encode(key),
        iOptions: const IOSOptions(
          accessibility: KeychainAccessibility.passcode,
          accessControlFlags: [AccessControlFlag.biometryCurrentSet],
        ),
        mOptions: const MacOsOptions(
          accessibility: KeychainAccessibility.passcode,
          accessControlFlags: [AccessControlFlag.biometryCurrentSet],
        ),
      );
      if (Platform.isLinux && !_skipPlatformCheck) await _writeMarker();
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'Failed to write biometric key to keychain: $e',
        name: 'SecureKeyStorage',
      );
      return false;
    }
  }

  /// Pair of [writeBiometricKey]. Returns null when:
  ///   * no biometric entry exists;
  ///   * the user failed / cancelled the biometric prompt;
  ///   * enrolment changed since the write (Apple
  ///     `biometryCurrentSet` invalidation).
  Future<Uint8List?> readBiometricKey() async {
    if (!_hasKeychainSupport()) return null;
    if (!await _linuxGatePass()) return null;
    try {
      final value = await _storage.read(
        key: _biometricKeyName,
        iOptions: const IOSOptions(
          accessibility: KeychainAccessibility.passcode,
          accessControlFlags: [AccessControlFlag.biometryCurrentSet],
        ),
        mOptions: const MacOsOptions(
          accessibility: KeychainAccessibility.passcode,
          accessControlFlags: [AccessControlFlag.biometryCurrentSet],
        ),
      );
      if (value == null) return null;
      return base64Decode(value);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to read biometric key from keychain: $e',
        name: 'SecureKeyStorage',
      );
      return null;
    }
  }

  /// Drop the biometric-gated key. Always called in lockstep with
  /// [deleteKey] — the two never exist together on the same install.
  Future<void> deleteBiometricKey() async {
    if (!_hasKeychainSupport()) return;
    if (!await _linuxGatePass()) return;
    try {
      await _storage.delete(key: _biometricKeyName);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to delete biometric key from keychain: $e',
        name: 'SecureKeyStorage',
      );
    }
  }

  /// Remove the encryption key from OS keychain.
  ///
  /// On Linux: if the marker is absent we never stored a key through this
  /// install, so there is nothing to delete and no libsecret call is made.
  /// When the marker is present we delete the secret and then clear the
  /// marker so the next launch doesn't probe libsecret again.
  Future<void> deleteKey() async {
    if (!_hasKeychainSupport()) return;
    if (!await _linuxGatePass()) return;
    try {
      await _storage.delete(key: _keyName);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to delete key from keychain: $e',
        name: 'SecureKeyStorage',
      );
    }
    if (Platform.isLinux && !_skipPlatformCheck) await _clearMarker();
  }
}

/// Classified keyring probe outcome. Settings UI consumes this to
/// render an actionable line under a disabled Keychain tier card
/// instead of a generic "unavailable" note.
enum KeyringProbeResult {
  /// Keychain reachable and round-trips a probe value.
  available,

  /// Linux host has no D-Bus session bus reachable — the user is on
  /// a headless / ssh-tty-only session, or a WSL container without
  /// `dbus-daemon --session` running. Fix: start a graphical session
  /// or export `DBUS_SESSION_BUS_ADDRESS` before launching. This
  /// subsumes the earlier `linuxWsl` case — the D-Bus address check
  /// is the concrete signal; pattern-matching distro names was a
  /// guess that caught WSL by coincidence.
  linuxNoDbusSession,

  /// D-Bus is up but libsecret cannot reach the secret-service
  /// daemon (no gnome-keyring-daemon or KWallet running, or the
  /// daemon refuses to unlock). Fix: install gnome-keyring or
  /// KWalletManager and ensure it runs at login.
  linuxNoSecretService,

  /// Non-Linux host's keychain returned an error — rare, usually a
  /// locked macOS login keychain or a corrupted Windows Credential
  /// Manager. UI shows the generic fallback copy.
  probeFailed,
}
