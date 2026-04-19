import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
/// - **Linux** — `TpmClient` + `tpm2-tools` shell-out. Sealed blob
///   lives in `hardware_vault.bin` alongside the salt.
/// - **iOS / macOS** — MethodChannel to `HardwareVaultPlugin.swift`
///   which wraps the DB key under a Secure Enclave P-256 key bound
///   by `.biometryCurrentSet`.
/// - **Android** — MethodChannel to `HardwareVaultPlugin.kt`; AES-
///   GCM wrap under a Keystore key with StrongBox preferred,
///   `setUserAuthenticationRequired(true)` + `setInvalidatedBy
///   BiometricEnrollment(true)`.
/// - **Windows** — MethodChannel to `hardware_vault_plugin.cpp`;
///   KeyCredentialManager (Windows Hello) with RequestSignAsync.
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

  bool get _usesMethodChannel =>
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isAndroid ||
      Platform.isWindows;

  /// True when the current platform can host the Hardware tier
  /// *today*. Linux returns true iff `/dev/tpmrm0` is accessible
  /// and `tpm2-tools` is installed; other platforms ask their
  /// native plugin.
  Future<bool> isAvailable() async {
    if (Platform.isLinux) return _tpm.isAvailable();
    if (_usesMethodChannel) {
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
      if (_usesMethodChannel) {
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
  Future<bool> store({required Uint8List dbKey, required String pin}) async {
    try {
      if (!await isAvailable()) return false;
      final salt = _randomBytes(_saltLength);
      final authValue = _deriveAuth(pin, salt);
      if (Platform.isLinux) {
        final sealed = await _tpm.seal(dbKey, authValue: authValue);
        if (sealed == null) return false;

        final file = await _stateFile();
        await file.parent.create(recursive: true);
        final blob = jsonEncode({
          'salt': base64.encode(salt),
          'sealed': base64.encode(sealed),
        });
        await file.writeAsBytes(utf8.encode(blob), flush: true);
        await hardenFilePerms(file.path);
        return true;
      }
      if (_usesMethodChannel) {
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
  Future<Uint8List?> read(String pin) async {
    try {
      if (!await isAvailable()) return null;
      if (Platform.isLinux) {
        final file = await _stateFile();
        if (!await file.exists()) return null;

        final raw = await file.readAsBytes();
        final decoded = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
        final saltB64 = decoded['salt'];
        final sealedB64 = decoded['sealed'];
        if (saltB64 is! String || sealedB64 is! String) return null;

        final salt = base64.decode(saltB64);
        final sealed = base64.decode(sealedB64);
        final authValue = _deriveAuth(pin, salt);
        return _tpm.unseal(sealed, authValue: authValue);
      }
      if (_usesMethodChannel) {
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
      if (_usesMethodChannel) {
        try {
          await _channel.invokeMethod<bool>('clear');
        } catch (_) {
          // Best-effort — the salt file is authoritative for "is
          // stored", so failing to tell the native side about a
          // clear still degrades safely into "locked out".
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
    await file.writeAsBytes(salt, flush: true);
    await hardenFilePerms(file.path);
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
  Uint8List _deriveAuth(String pin, Uint8List salt) {
    final mac = Hmac(sha256, salt);
    return Uint8List.fromList(mac.convert(utf8.encode(pin)).bytes);
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
  /// Pure helper today; callers plumb it into `store` / `read` once
  /// the `SecurityTierModifiers` shape is fully consumed at the rekey
  /// / switcher layer.
  @visibleForTesting
  static Uint8List? resolveAuthValue({
    required bool password,
    required bool biometric,
    required Uint8List salt,
    String? typedPassword,
    Uint8List? fprintdHash,
  }) {
    if (biometric) {
      if (fprintdHash == null || fprintdHash.isEmpty) return null;
      final mac = Hmac(sha256, salt);
      return Uint8List.fromList(mac.convert(fprintdHash).bytes);
    }
    if (password) {
      if (typedPassword == null || typedPassword.isEmpty) return null;
      final mac = Hmac(sha256, salt);
      return Uint8List.fromList(mac.convert(utf8.encode(typedPassword)).bytes);
    }
    return Uint8List(0);
  }

  Uint8List _randomBytes(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }
}
