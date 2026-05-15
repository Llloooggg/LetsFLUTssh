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

/// Argon2id parameter record (memory cost, iterations, parallelism).
///
/// The production profile is owned Rust-side in
/// `lfs_core::security::master_password::KdfParams::defaults` and
/// mirrored Dart-side into [productionDefaults] at startup via
/// [bootstrapFromRust]. Every fresh `enable` / `changePassword` /
/// `.lfs` export reads back from the mirror, so the Rust constant is
/// the single source of truth for the wall-clock cost.
///
/// Bumping any field on the Rust side is forward-compatible: the value
/// is stored in `credentials.kdf` and read back at verify time, so a
/// newer profile coexists with accounts enabled under the older one.
/// Downgrading is not — older binaries would fail to decode the
/// header.
class KdfParams {
  final KdfAlgorithm algorithm;
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  /// Argon2id constructor. Callers must supply explicit cost
  /// parameters — there are no Dart-side defaults; the canonical
  /// production profile lives in Rust and is exposed through
  /// [productionDefaults].
  const KdfParams.argon2id({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  }) : algorithm = KdfAlgorithm.argon2id;

  const KdfParams._({
    required this.algorithm,
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// Current production defaults, mirrored from
  /// `lfs_core::security::master_password::KdfParams::defaults` at
  /// startup. Reads before [bootstrapFromRust] has run throw
  /// [LateInitializationError] — wire it into the FRB-ready section
  /// of bootstrap (after `_initRustCoreOrFatal`) before any code path
  /// that touches the field.
  static late KdfParams productionDefaults;

  /// Populate [productionDefaults] from the canonical Rust constant.
  /// Safe to call more than once — every invocation overwrites the
  /// field with the same canonical value, so a test harness that has
  /// already bootstrapped FRB can rebootstrap the mirror without
  /// risking [LateInitializationError].
  static void bootstrapFromRust() {
    final p = rust_mp.kdfParamsProductionDefaults();
    productionDefaults = KdfParams._(
      algorithm: KdfAlgorithm.argon2id,
      memoryKiB: p.memoryKib,
      iterations: p.iterations,
      parallelism: p.parallelism,
    );
  }

  /// Pre-seed [productionDefaults] with cheap test-time values for
  /// widget tests that never load FRB (and thus cannot call
  /// [bootstrapFromRust]). The values match the Argon2id minimum
  /// (memory=8 KiB, t=1, p=1) so any Dart code path that touches the
  /// field during a unit/widget test gets a coherent record without
  /// burning CPU on a real derive. Tests that *do* load FRB
  /// subsequently overwrite this via [bootstrapFromRust], so the
  /// canonical Rust values still apply in integration tests.
  static void bootstrapForTests() {
    productionDefaults = const KdfParams._(
      algorithm: KdfAlgorithm.argon2id,
      memoryKiB: 8,
      iterations: 1,
      parallelism: 1,
    );
  }

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
