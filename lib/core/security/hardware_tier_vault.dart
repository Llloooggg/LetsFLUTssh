import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import 'linux/tpm_client.dart';

/// Hardware-bound DB-key vault for L3 (Hardware + PIN) tier.
///
/// The DB key is sealed inside a hardware module (TPM2 on Linux,
/// Secure Enclave / StrongBox / Windows Hello on other platforms)
/// under an auth value derived from the user's PIN. The platform's
/// hardware-enforced rate limit on the auth value is what makes a
/// short PIN cryptographically meaningful — brute force against a
/// 4-6 digit PIN is infeasible when the hardware locks out after N
/// wrong attempts.
///
/// **Current scope: Linux TPM2 via `TpmClient`.** Apple/Android/
/// Windows paths share the same contract and fill in once the
/// dedicated plugins land in their own sessions; the class holds
/// [isAvailable] returning false on every other platform so callers
/// can render the Hardware tier row as disabled with a tooltip.
///
/// Storage: sealed blob + random salt in `hardware_vault.bin` under
/// the app-support dir, hardened to 0600. Salt is per-install
/// (randomised on `store`), so two devices with the same PIN never
/// end up with the same sealed blob.
class HardwareTierVault {
  HardwareTierVault({
    TpmClient? tpmClient,
    Future<File> Function()? stateFileFactory,
    Random? random,
  }) : _tpm = tpmClient ?? TpmClient(),
       _stateFile = stateFileFactory ?? _defaultStateFile,
       _random = random ?? Random.secure();

  static const _fileName = 'hardware_vault.bin';
  static const _saltLength = 32;

  final TpmClient _tpm;
  final Future<File> Function() _stateFile;
  final Random _random;

  static Future<File> _defaultStateFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// True when the current platform can host the Hardware tier
  /// *today*. Linux returns true iff `/dev/tpmrm0` is accessible
  /// and `tpm2-tools` is installed; everything else returns false
  /// until the platform-specific plugin ships.
  Future<bool> isAvailable() async {
    if (Platform.isLinux) return _tpm.isAvailable();
    // iOS/macOS/Android/Windows paths defer — wizard row stays
    // disabled with a tooltip reason until their implementations
    // land. Returning false keeps the rest of the unlock flow
    // honest about what this tier does not currently cover.
    return false;
  }

  /// True when a sealed blob is on disk. Caller uses this to
  /// decide between the "set PIN" first-launch flow and the
  /// "enter PIN to unlock" path.
  Future<bool> isStored() async {
    try {
      final file = await _stateFile();
      return file.exists();
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
      final file = await _stateFile();
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault.clear failed: $e',
        name: 'HardwareTierVault',
      );
    }
  }

  /// Derive a 32-byte auth value from the user's PIN + the
  /// per-install salt. HMAC-SHA256 rather than Argon2id because the
  /// TPM's hardware lockout is the rate limiter; slowing this
  /// derivation would only slow the legitimate user. Salting still
  /// matters — it keeps the sealed blob device-specific even when
  /// two users pick the same PIN.
  Uint8List _deriveAuth(String pin, Uint8List salt) {
    final mac = Hmac(sha256, salt);
    return Uint8List.fromList(mac.convert(utf8.encode(pin)).bytes);
  }

  Uint8List _randomBytes(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }
}
