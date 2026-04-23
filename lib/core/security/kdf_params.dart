import 'dart:typed_data';

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

  const KdfParams.argon2id({
    this.memoryKiB = 47104,
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

  /// Serialize algorithm ID + params. Excludes the salt — the file layout
  /// places it after this block.
  Uint8List encode() {
    switch (algorithm) {
      case KdfAlgorithm.argon2id:
        final b = ByteData(10);
        b.setUint8(0, algorithm.id);
        b.setUint32(1, memoryKiB);
        b.setUint32(5, iterations);
        b.setUint8(9, parallelism);
        return b.buffer.asUint8List();
    }
  }

  /// Sanity ceilings for Argon2id params. A legitimate header writes
  /// production defaults (46 MiB, 2 iters, 1 lane); future profile
  /// bumps would at most double those. The upper bounds exist to
  /// defuse a crafted `credentials.kdf` that asks for absurd costs —
  /// 4 GiB of memory, a million iterations — which would wedge the
  /// unlock isolate rather than fail cleanly. 1 GiB / 16 iters / 8
  /// lanes gives ~20× headroom over today's production profile, well
  /// past any plausible security bump, while keeping a single
  /// malicious header from turning into an OOM on unlock.
  static const int _argon2idMaxMemoryKiB = 1024 * 1024; // 1 GiB
  static const int _argon2idMaxIterations = 16;
  static const int _argon2idMaxParallelism = 8;

  /// Deserialize algorithm + params starting at [bytes]. Throws
  /// [FormatException] on unknown algorithm ID, truncated buffer, or
  /// params outside the sanity ceilings documented above.
  ///
  /// Returns the parsed params; callers pass [bytes.sublist(0,
  /// encodedLength)] back to `encode()` for round-trip.
  static KdfParams decode(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('KdfParams: empty input');
    }
    final algo = KdfAlgorithm.fromId(bytes[0]);
    if (algo == null) {
      throw FormatException(
        'KdfParams: unknown algorithm id 0x'
        '${bytes[0].toRadixString(16).padLeft(2, '0')}',
      );
    }
    switch (algo) {
      case KdfAlgorithm.argon2id:
        if (bytes.length < 10) {
          throw const FormatException('KdfParams: truncated Argon2id params');
        }
        final b = ByteData.sublistView(bytes, 0, 10);
        final mem = b.getUint32(1);
        final iters = b.getUint32(5);
        final par = b.getUint8(9);
        if (mem == 0 || iters == 0 || par == 0) {
          throw const FormatException('KdfParams: Argon2id params must be > 0');
        }
        if (mem > _argon2idMaxMemoryKiB) {
          throw FormatException(
            'KdfParams: Argon2id memory $mem KiB exceeds sanity cap '
            '$_argon2idMaxMemoryKiB KiB',
          );
        }
        if (iters > _argon2idMaxIterations) {
          throw FormatException(
            'KdfParams: Argon2id iterations $iters exceeds sanity cap '
            '$_argon2idMaxIterations',
          );
        }
        if (par > _argon2idMaxParallelism) {
          throw FormatException(
            'KdfParams: Argon2id parallelism $par exceeds sanity cap '
            '$_argon2idMaxParallelism',
          );
        }
        return KdfParams._(
          algorithm: algo,
          memoryKiB: mem,
          iterations: iters,
          parallelism: par,
        );
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
