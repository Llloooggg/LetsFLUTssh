import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/crypto.dart' as rust_crypto;
import '../../src/rust/api/hardware_tier_vault.dart' as rust_vault;
import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import 'linux/tpm_client.dart';

/// Hardware-bound DB-key vault for L3 (Hardware + PIN) tier.
///
/// The DB key is sealed inside a hardware module under an auth value
/// derived from the user's PIN. The platform's hardware-enforced
/// rate limit on the auth value is what makes a short PIN
/// cryptographically meaningful — brute force against a 4-6 digit
/// PIN is infeasible when the hardware locks out after N wrong
/// attempts.
///
/// Platform dispatch:
/// - **Linux** — `TpmClient` + `tpm2-tools` shell-out (default) or
///   native `tss-esapi` backend (`LFS_TPM_BACKEND=native` env opt-in,
///   NI-1). Sealed blob lives in `hardware_vault.bin` alongside the
///   salt.
/// - **iOS / macOS** — `lfs_os_security::hardware_tier_vault::apple`
///   via FRB. Direct `security-framework` + `objc2` calls; SE-bound
///   wrap (`ECIESEncryptionCofactorVariableIVX963SHA256AESGCM`) +
///   on-disk envelope. Replaced the historical
///   `HardwareVaultPlugin.swift` MethodChannel — no Apple plugin
///   wired anymore.
/// - **Android** — `lfs_os_security::android::hardware_vault` via
///   FRB. Direct JNI to `java.security.KeyStore` provider
///   `"AndroidKeyStore"` with `setIsStrongBoxBacked(true)` (API 28+,
///   silent fallback to TEE on `StrongBoxUnavailableException`).
///   Replaced the historical `HardwareVaultPlugin.kt` MethodChannel.
/// - **Windows** — MethodChannel to `hardware_vault_plugin.cpp`;
///   CNG `NCrypt` on the Microsoft Platform Crypto Provider (TPM
///   2.0) with RSA-OAEP-SHA-256 wrap. The only remaining native
///   plugin in the L3 path — the Tier 4 Rust port for Windows
///   (native `windows` crate CNG bindings) is a follow-up arc; until
///   it lands, the C++ plugin is the canonical Windows path, not a
///   fallback.
///
/// The PIN itself cannot be the auth value on Apple/Android/Windows
/// because those APIs do not accept arbitrary secrets — they gate
/// on biometrics / Hello. The PIN is therefore an **external HMAC
/// gate**: Dart computes `HMAC(pin, salt)` and hands it to the
/// native side, which refuses to unseal unless the gate matches
/// the value saved on `store`. Wrong PIN fails locally without
/// waking the biometric prompt. Salt lives in
/// `hardware_vault_salt.bin` so two installs with the same PIN
/// produce different gates.
class HardwareTierVault {
  HardwareTierVault({
    TpmClient? tpmClient,
    MethodChannel? channel,
    Future<File> Function()? stateFileFactory,
    Future<File> Function()? saltFileFactory,
    Random? random,
  }) : _tpm = tpmClient ?? TpmClient(),
       _channel = channel ?? const MethodChannel(_channelName),
       _stateFile = stateFileFactory ?? _defaultStateFile,
       _saltFile = saltFileFactory ?? _defaultSaltFile,
       _random = random ?? Random.secure();

  static const _channelName = 'com.letsflutssh/hardware_vault';
  static const _fileName = 'hardware_vault.bin';
  static const _saltFileName = 'hardware_vault_salt.bin';
  static const _saltLength = 32;

  final TpmClient _tpm;
  final MethodChannel _channel;
  final Future<File> Function() _stateFile;
  final Future<File> Function() _saltFile;
  final Random _random;

  static Future<File> _defaultStateFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  static Future<File> _defaultSaltFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _saltFileName));
  }

  /// True when the current platform is wired through Rust FRB (Apple
  /// + Android). Linux uses `TpmClient` directly; Windows uses the
  /// `com.letsflutssh/hardware_vault` MethodChannel until Win Tier 4
  /// lands.
  bool get _usesRust =>
      Platform.isMacOS || Platform.isIOS || Platform.isAndroid;

  /// Sole remaining MethodChannel path: Windows Tier 4 (CNG/NCrypt
  /// hardware_vault). Will retire when the Win Tier 4 Rust port lands.
  bool get _usesWindowsMethodChannel => Platform.isWindows;

  /// True when the current platform can host the Hardware tier
  /// *today*. Linux returns true iff `/dev/tpmrm0` is accessible
  /// and `tpm2-tools` is installed; Apple + Android route through
  /// the unified Rust dispatch in
  /// `lfs_os_security::hardware_tier_vault`; Windows asks the native
  /// CNG plugin.
  Future<bool> isAvailable() async {
    if (Platform.isLinux) return _tpm.isAvailable();
    if (_usesRust) {
      return rust_vault.hardwareTierVaultIsAvailable();
    }
    if (_usesWindowsMethodChannel) {
      try {
        final result = await _channel.invokeMethod<bool>('isAvailable');
        return result ?? false;
      } catch (e) {
        AppLogger.instance.log(
          'HardwareTierVault.isAvailable channel error: $e',
          name: 'HardwareTierVault',
        );
        return false;
      }
    }
    return false;
  }

  /// Classified hardware-unavailable reason. Returns an opaque
  /// platform-specific string code (`windowsSoftwareOnly`,
  /// `macosNoSecureEnclave`, `androidBiometricNotEnrolled`, …) or
  /// `available` when the tier is reachable. `unknown` on platforms
  /// that do not implement the native `probeDetail` method yet, or
  /// when the channel call fails. The Dart-side provider maps this
  /// to the `HardwareProbeDetail` enum and the localised hint copy.
  ///
  /// Linux is handled by `TpmClient.probe()` at the provider layer
  /// and never enters this method.
  Future<String> probeDetail() async {
    if (_usesRust) {
      return rust_vault.hardwareTierVaultProbeDetail();
    }
    if (_usesWindowsMethodChannel) {
      try {
        final result = await _channel.invokeMethod<String>('probeDetail');
        return result ?? 'unknown';
      } catch (e) {
        AppLogger.instance.log(
          'HardwareTierVault.probeDetail channel error: $e',
          name: 'HardwareTierVault',
        );
        return 'unknown';
      }
    }
    return 'unknown';
  }

  /// True when a sealed blob is on disk. Linux inspects
  /// `hardware_vault.bin`; other platforms ask the native side plus
  /// verify that the Dart-side salt file is present (both halves
  /// required — a half-wiped state is a reset, not an unlock).
  Future<bool> isStored() async {
    try {
      if (Platform.isLinux) {
        final file = await _stateFile();
        return file.exists();
      }
      if (_usesRust) {
        // Salt file is the Dart-owned half of the unseal contract,
        // same as the Windows MethodChannel branch — both halves
        // required.
        final saltFile = await _saltFile();
        if (!await saltFile.exists()) return false;
        final dir = await getApplicationSupportDirectory();
        return rust_vault.hardwareTierVaultIsStored(supportDir: dir.path);
      }
      if (_usesWindowsMethodChannel) {
        final saltFile = await _saltFile();
        if (!await saltFile.exists()) return false;
        final result = await _channel.invokeMethod<bool>('isStored');
        return result ?? false;
      }
      return false;
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault.isStored failed: $e',
        name: 'HardwareTierVault',
      );
      return false;
    }
  }

  /// Seal [dbKey] under `HMAC(pin, salt)`. Generates a fresh salt,
  /// writes `{salt, sealedBlob}` to disk, returns true on success.
  ///
  /// When [pin] is null or empty the auth value is a fixed empty
  /// byte string — the "passwordless T2" path from the bank-style
  /// modifier model. An attacker still needs TPM / Secure Enclave
  /// access to unseal (cold-disk-theft is still mitigated); there
  /// is simply no user-typed gate on top. The [read] path mirrors
  /// this: passing null there unseals without prompting.
  Future<bool> store({required Uint8List dbKey, String? pin}) async {
    try {
      if (!await isAvailable()) return false;
      final salt = _randomBytes(_saltLength);
      final authValue = _deriveAuth(pin, salt);
      if (Platform.isLinux) {
        final sealed = await _tpm.seal(dbKey, authValue: authValue);
        if (sealed == null) return false;

        final file = await _stateFile();
        await file.parent.create(recursive: true);
        final blob = rust_vault.hardwareTierVaultEncodeLinuxBlob(
          salt: salt,
          sealed: sealed,
        );
        // Atomic write — a crash mid-flush on direct `writeAsBytes`
        // could leave `hardware_vault.bin` half-written, bricking the
        // tier (unseal path reads the JSON and throws on malformed
        // input; user sees "unlock failed" with no recoverable state).
        // `writeBytesAtomic` writes to `<path>.tmp` first, chmods it,
        // then renames — either the previous sealed blob survives or
        // the new one does, never a torn file.
        await writeBytesAtomic(file.path, utf8.encode(blob));
        return true;
      }
      if (_usesRust) {
        try {
          final dir = await getApplicationSupportDirectory();
          await rust_vault.hardwareTierVaultStore(
            supportDir: dir.path,
            dbKey: dbKey,
            pinHmac: authValue,
          );
          // Rust side persisted the wrapped key; Dart keeps the salt
          // so the unseal path can re-derive the HMAC gate.
          await _writeSaltFile(salt);
          return true;
        } catch (e) {
          AppLogger.instance.log(
            'HardwareTierVault.store (Rust): $e',
            name: 'HardwareTierVault',
          );
          return false;
        }
      }
      if (_usesWindowsMethodChannel) {
        final ok =
            await _channel.invokeMethod<bool>('store', <String, Object>{
              'dbKey': dbKey,
              'pinHmac': authValue,
            }) ??
            false;
        if (!ok) return false;
        // Native side persisted the wrapped key; Dart keeps the salt
        // so the unseal path can re-derive the HMAC gate.
        await _writeSaltFile(salt);
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault.store failed: $e',
        name: 'HardwareTierVault',
      );
      return false;
    }
  }

  /// Unseal the DB key using [pin]. Returns null on wrong PIN,
  /// missing state, unsupported platform, or any other failure —
  /// the rate limiter layered on top is responsible for backoff.
  ///
  /// When [pin] is null or empty the derivation mirrors [store]'s
  /// passwordless branch (empty auth value), so a vault sealed
  /// without a PIN unseals without a PIN.
  Future<Uint8List?> read(String? pin) async {
    try {
      if (!await isAvailable()) return null;
      if (Platform.isLinux) {
        final file = await _stateFile();
        if (!await file.exists()) return null;

        final raw = await file.readAsBytes();
        final rust_vault.DbHardwareTierLinuxBlob decoded;
        try {
          decoded = rust_vault.hardwareTierVaultDecodeLinuxBlob(
            blob: utf8.decode(raw),
          );
        } catch (_) {
          // Disk blob unparseable / corrupt — caller routes back to
          // password unlock.
          return null;
        }

        final authValue = _deriveAuth(pin, decoded.salt);
        return _tpm.unseal(decoded.sealed, authValue: authValue);
      }
      if (_usesRust) {
        try {
          final salt = await _readSaltFile();
          if (salt == null) return null;
          final authValue = _deriveAuth(pin, salt);
          final dir = await getApplicationSupportDirectory();
          return await rust_vault.hardwareTierVaultRead(
            supportDir: dir.path,
            pinHmac: authValue,
          );
        } catch (e) {
          AppLogger.instance.log(
            'HardwareTierVault.read (Rust): $e',
            name: 'HardwareTierVault',
          );
          return null;
        }
      }
      if (_usesWindowsMethodChannel) {
        final salt = await _readSaltFile();
        if (salt == null) return null;
        final authValue = _deriveAuth(pin, salt);
        final dbKey = await _channel.invokeMethod<Uint8List>(
          'read',
          <String, Object>{'pinHmac': authValue},
        );
        return dbKey;
      }
      return null;
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault.read failed: $e',
        name: 'HardwareTierVault',
      );
      return null;
    }
  }

  /// Drop the sealed blob. Called on tier switch away from L3 and
  /// on PIN change (before a new [store]).
  Future<void> clear() async {
    try {
      if (Platform.isLinux) {
        final file = await _stateFile();
        if (await file.exists()) await file.delete();
        return;
      }
      if (_usesRust) {
        try {
          final dir = await getApplicationSupportDirectory();
          await rust_vault.hardwareTierVaultClear(supportDir: dir.path);
        } catch (e) {
          // Best-effort — the salt file is authoritative for "is
          // stored", so failing the Rust-side clear still degrades
          // safely into "locked out". Log so a support trace points
          // at a stale native-side blob the next tier-switch has to
          // tolerate.
          AppLogger.instance.log(
            'HardwareTierVault.clear (Rust) failed (salt delete continues): $e',
            name: 'HardwareTierVault',
          );
        }
        final saltFile = await _saltFile();
        if (await saltFile.exists()) await saltFile.delete();
        return;
      }
      if (_usesWindowsMethodChannel) {
        try {
          await _channel.invokeMethod<bool>('clear');
        } catch (e) {
          // Best-effort — the salt file is authoritative for "is
          // stored", so failing to tell the native side about a
          // clear still degrades safely into "locked out". Log the
          // native miss anyway so a support trace points at a stale
          // native-side blob the next tier-switch has to tolerate.
          AppLogger.instance.log(
            'HardwareTierVault native clear failed (salt delete continues): $e',
            name: 'HardwareTierVault',
          );
        }
        final saltFile = await _saltFile();
        if (await saltFile.exists()) await saltFile.delete();
      }
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault.clear failed: $e',
        name: 'HardwareTierVault',
      );
    }
  }

  Future<void> _writeSaltFile(Uint8List salt) async {
    final file = await _saltFile();
    await file.parent.create(recursive: true);
    // Salt is half of the unseal contract on every non-Linux platform
    // (the other half lives inside the Rust vault file or the
    // Windows native hw-vault); a torn salt file from a mid-write
    // crash would fail HMAC derivation and permanently lock the
    // user out. Atomic write rules out that tear — the previous
    // salt survives on failure.
    await writeBytesAtomic(file.path, salt);
  }

  Future<Uint8List?> _readSaltFile() async {
    try {
      final file = await _saltFile();
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length != _saltLength) return null;
      return bytes;
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault._readSaltFile failed: $e',
        name: 'HardwareTierVault',
      );
      return null;
    }
  }

  /// Derive a 32-byte auth value from the user's PIN + the
  /// per-install salt. HMAC-SHA256 rather than Argon2id because the
  /// hardware lockout is the rate limiter; slowing this derivation
  /// would only slow the legitimate user. Salting still matters —
  /// it keeps the sealed blob device-specific even when two users
  /// pick the same PIN.
  ///
  /// HMAC the typed pin under the per-install [salt], or return an
  /// empty auth value when the caller passed null / empty — the
  /// "passwordless T2" path. The empty value is a stable choice:
  /// every store / read pair derived this way agrees byte-for-byte,
  /// so a vault sealed passwordless always unseals passwordless.
  Uint8List _deriveAuth(String? pin, Uint8List salt) {
    if (pin == null || pin.isEmpty) return Uint8List(0);
    return rust_crypto.cryptoHmacSha256(
      key: salt,
      message: Uint8List.fromList(utf8.encode(pin)),
    );
  }

  /// Resolve the TPM / hw-vault auth value for a (password, biometric)
  /// modifier combo — shared across platforms, not just Linux/TPM2.
  /// Matches the "universal bank-style" model documented in the
  /// 3-tier plan:
  ///
  /// * password=false, biometric=false → empty `Uint8List(0)`
  ///   (isolation-only; wrong callers still need TPM / Secure Enclave
  ///   access, but there is no user-typed gate).
  /// * password=true, biometric=false → `HMAC(typedPassword, salt)`.
  /// * biometric=true → `HMAC(fprintdHash, salt)`. The `password`
  ///   flag must also be true by wizard invariant (biometric is a
  ///   shortcut for entering the password, never its replacement),
  ///   but the resolver itself treats biometric as the authoritative
  ///   auth source when both are requested.
  ///
  /// Returns null for an inconsistent request (password=true without
  /// a typed password bound, biometric=true without an fprintd hash).
  /// Callers surface null as "modifier resolution failed — treat as a
  /// cancelled unlock" so we never silently fall back to an empty auth.
  ///
  /// Routes through `lfs_core::security::hardware_tier_vault::
  /// resolve_auth_value` (FRB sync) so the (password, biometric) →
  /// auth-bytes contract lives one place across the Linux TPM
  /// path + the per-platform Rust / method-channel vault paths.
  @visibleForTesting
  static Uint8List? resolveAuthValue({
    required bool password,
    required bool biometric,
    required Uint8List salt,
    String? typedPassword,
    Uint8List? fprintdHash,
  }) {
    final v = rust_vault.hardwareTierVaultResolveAuthValue(
      password: password,
      biometric: biometric,
      salt: salt,
      typedPassword: typedPassword,
      fprintdHash: fprintdHash,
    );
    return v == null ? null : Uint8List.fromList(v);
  }

  Uint8List _randomBytes(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }
}
