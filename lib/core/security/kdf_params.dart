import 'dart:typed_data';

import '../../src/rust/api/master_password.dart' as rust_mp;

/// Supported key-derivation algorithms. The on-disk enum value is the
/// stable wire ID — new entries must never reuse existing IDs or the
/// format versioning guarantee breaks.
enum KdfAlgorithm {
  /// Argon2id — OWASP's recommended password-hashing KDF. Memory-hard,
  /// resists GPU/ASIC cracking far better than PBKDF2.
  argon2id(0x01);

  final int id;
  const KdfAlgorithm(this.id);

  static KdfAlgorithm? fromId(int id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// Parameters for the current production Argon2id profile.
///
/// Chosen as the "golden middle" between security and mid-tier mobile
/// wall-clock time:
/// - `memoryKiB = 47104` (46 MiB) — OWASP 2024 recommended floor
/// - `iterations = 2` — one full pass is valid, two gives headroom
/// - `parallelism = 1` — one lane keeps the isolate single-core
///
/// Bumping any field is forward-compatible: the value is stored in
/// `credentials.kdf` and read back at verify time, so a newer profile
/// can coexist with accounts enabled under the older one. Downgrading
/// is not — older binaries would fail to decode the header.
class KdfParams {
  final KdfAlgorithm algorithm;
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  /// OWASP 2024 Argon2id memory floor: 46 MiB = 46 * 1024 KiB.
  /// Kept as a named constant so the unit (KiB vs MiB vs bytes) is
  /// obvious at the call site instead of looking up whether `47104`
  /// is bytes, KiB, or MiB.
  static const int _defaultMemoryKiB = 46 * 1024;

  const KdfParams.argon2id({
    this.memoryKiB = _defaultMemoryKiB,
    this.iterations = 2,
    this.parallelism = 1,
  }) : algorithm = KdfAlgorithm.argon2id;

  const KdfParams._({
    required this.algorithm,
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// Current production defaults. All fresh `enable()` / `changePassword()`
  /// calls write these. Old files keep whatever they were encoded with.
  static const KdfParams productionDefaults = KdfParams.argon2id();

  /// Serialize algorithm ID + params via
  /// `lfs_core::security::master_password::KdfParams::encode` (FRB
  /// sync). Excludes the salt — the file layout places it after this
  /// block.
  Uint8List encode() {
    switch (algorithm) {
      case KdfAlgorithm.argon2id:
        return rust_mp.kdfParamsEncode(
          memoryKib: memoryKiB,
          iterations: iterations,
          parallelism: parallelism,
        );
    }
  }

  /// Deserialize algorithm + params starting at [bytes]. Throws
  /// [FormatException] on unknown algorithm ID, truncated buffer, or
  /// params outside the Rust-side sanity ceilings (1 GiB / 16 iters /
  /// 8 lanes — ~20× over today's production profile, defuses a
  /// crafted header from OOM-ing the unlock isolate).
  ///
  /// Routes through `lfs_core::security::master_password::KdfParams::decode`
  /// so the validator lives one place; the catch translates the
  /// Rust-side anyhow error into the [FormatException] shape callers
  /// already match against.
  static KdfParams decode(Uint8List bytes) {
    try {
      final p = rust_mp.kdfParamsDecode(bytes: bytes);
      return KdfParams._(
        algorithm: KdfAlgorithm.argon2id,
        memoryKiB: p.memoryKib,
        iterations: p.iterations,
        parallelism: p.parallelism,
      );
    } catch (e) {
      // AnyhowException stringifies as `anyhow_exception "<msg>"`.
      // Pull the canonical "KdfParams: …" tail back out so the
      // user-facing exception matches the contract documented
      // above.
      final msg = e.toString();
      final idx = msg.indexOf('KdfParams:');
      if (idx < 0) rethrow;
      throw FormatException(msg.substring(idx).replaceAll(RegExp(r'"$'), ''));
    }
  }

  /// Byte length of the encoded algorithm + params block. Used by file
  /// format readers to know where the salt starts.
  int get encodedLength {
    switch (algorithm) {
      case KdfAlgorithm.argon2id:
        return 10;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KdfParams &&
          algorithm == other.algorithm &&
          memoryKiB == other.memoryKiB &&
          iterations == other.iterations &&
          parallelism == other.parallelism);

  @override
  int get hashCode =>
      Object.hash(algorithm, memoryKiB, iterations, parallelism);

  @override
  String toString() =>
      'KdfParams($algorithm, m=${memoryKiB}KiB, t=$iterations, p=$parallelism)';
}
