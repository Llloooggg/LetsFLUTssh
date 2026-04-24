// Standalone fuzz target for the KdfParams binary decoder.
//
// The encoder writes a 10-byte blob: 1-byte algorithm ID + 4-byte
// memory (KiB) + 4-byte iterations + 1-byte parallelism. The
// decoder has to tolerate every malformed / truncated / hostile
// input without crashing — import callers read this from user-
// supplied `.lfs` archives, so the blob is always untrusted.
//
// Compiled to a native libFuzzer target via
// `.clusterfuzzlite/build.sh`. Reads raw bytes from stdin and
// feeds them to a self-contained decode() that mirrors the
// production logic from lib/core/security/kdf_params.dart without
// Flutter / pubspec dependencies.
//
// Usage:
//   dart compile exe fuzz/fuzz_kdf_params.dart -o fuzz/out/fuzz_kdf_params
//   printf '\x01\x00\x00\xb8\x00\x00\x00\x00\x02\x01' | ./fuzz/out/fuzz_kdf_params

import 'dart:io';
import 'dart:typed_data';

void main() {
  // Binary target: read raw bytes, not a UTF-8 line.
  // `readLineSync` decodes through the system encoder and throws
  // FormatException on any non-ASCII byte — libFuzzer feeds random
  // bytes, not text, so we loop on readByteSync.
  final buf = <int>[];
  int b;
  while ((b = stdin.readByteSync()) != -1) {
    buf.add(b);
  }
  if (buf.isEmpty) return;
  final bytes = Uint8List.fromList(buf);
  try {
    _decode(bytes);
  } on FormatException {
    // Expected — malformed input produces a typed failure, not a
    // crash.
  }
}

/// Mirror of `KdfParams.decode` in lib/core/security/kdf_params.dart.
/// Logic is isolated here so the fuzz binary stays dependency-free
/// (dart compile exe with Flutter/pub packages is fat).
///
/// Must stay in lock-step with the production caps — the whole
/// point of fuzzing this decoder is to exercise the rejection
/// branches for untrusted `.lfs` headers (malicious memory=∞ would
/// OOM the importer before the KDF even runs). If the production
/// caps change, update the constants below AND the seed corpus in
/// `.clusterfuzzlite/build.sh` so libFuzzer has anchors that sit
/// on each branch boundary.
const int _argon2idMaxMemoryKiB = 1024 * 1024; // 1 GiB
const int _argon2idMaxIterations = 16;
const int _argon2idMaxParallelism = 8;

void _decode(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw const FormatException('KdfParams: empty input');
  }
  final algoId = bytes[0];
  if (algoId != 0x01) {
    throw FormatException('KdfParams: unknown algorithm id 0x$algoId');
  }
  if (bytes.length < 10) {
    throw const FormatException('KdfParams: truncated Argon2id header');
  }
  final bd = ByteData.sublistView(bytes, 0, 10);
  final memoryKiB = bd.getUint32(1);
  final iterations = bd.getUint32(5);
  final parallelism = bd.getUint8(9);
  if (memoryKiB == 0 || iterations == 0 || parallelism == 0) {
    throw const FormatException('KdfParams: Argon2id params must be > 0');
  }
  if (memoryKiB > _argon2idMaxMemoryKiB) {
    throw FormatException(
      'KdfParams: Argon2id memory $memoryKiB KiB exceeds sanity cap '
      '$_argon2idMaxMemoryKiB KiB',
    );
  }
  if (iterations > _argon2idMaxIterations) {
    throw FormatException(
      'KdfParams: Argon2id iterations $iterations exceeds sanity cap '
      '$_argon2idMaxIterations',
    );
  }
  if (parallelism > _argon2idMaxParallelism) {
    throw FormatException(
      'KdfParams: Argon2id parallelism $parallelism exceeds sanity cap '
      '$_argon2idMaxParallelism',
    );
  }
  // Touch the values so the decoder work is observable — the
  // libFuzzer coverage map attributes this to the accept branch.
  memoryKiB.hashCode;
  iterations.hashCode;
  parallelism.hashCode;
}
