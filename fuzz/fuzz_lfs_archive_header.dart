// Standalone fuzz target for the LFS encrypted-archive header
// parser.
//
// Header layout (v2 Argon2id):
//   bytes[0..4]   = "LFSE" magic
//   bytes[4]      = version (0x02 for Argon2id)
//   bytes[5..15]  = KdfParams blob (1 + 4 + 4 + 1 = 10 bytes)
//   bytes[15..47] = 32-byte salt
//   bytes[47..59] = 12-byte IV
//   bytes[59..]   = AES-GCM ciphertext
//
// Parsing must tolerate every truncated / bad-magic / bad-version /
// out-of-bounds-KDF-params / negative-sized-payload mutation the
// fuzzer throws at it. The decrypt step (running Argon2id on
// user-supplied params) is intentionally skipped here — a single
// attacker-crafted "memoryKiB = 4 GiB" would OOM the libFuzzer
// worker before the second input landed. The production
// _decryptArgon2id enforces caps before running the KDF; this fuzz
// stops at header parsing.
//
// Usage:
//   dart compile exe fuzz/fuzz_lfs_archive_header.dart -o fuzz/out/fuzz_lfs_archive_header

import 'dart:io';
import 'dart:typed_data';

// DoS caps mirror lib/features/settings/export_import.dart so the
// fuzz enforcement tracks the production gate.
const int _maxMemoryKiB = 512 * 1024; // 512 MiB
const int _maxIterations = 16;
const int _maxParallelism = 16;

const List<int> _magic = [0x4C, 0x46, 0x53, 0x45]; // 'LFSE'
const int _versionArgon2id = 0x02;
const int _saltLen = 32;
const int _ivLen = 12;
const int _kdfBlobLen = 10;

void main() {
  // Binary target: raw bytes from stdin. `readLineSync` would
  // decode via UTF-8 and throw on non-ASCII; libFuzzer feeds
  // arbitrary bytes.
  final buf = <int>[];
  int b;
  while ((b = stdin.readByteSync()) != -1) {
    buf.add(b);
  }
  if (buf.isEmpty) return;
  final bytes = Uint8List.fromList(buf);
  try {
    _parseHeader(bytes);
  } on FormatException {
    // Expected typed failure path.
  }
}

/// Mirror of `_decryptArgon2id`'s header-parsing prelude. Parses +
/// validates everything up to (but not including) the AES-GCM
/// decrypt step.
void _parseHeader(Uint8List bytes) {
  if (bytes.length < _magic.length + 1) {
    throw const FormatException('LFS: too short for magic + version');
  }
  for (var i = 0; i < _magic.length; i++) {
    if (bytes[i] != _magic[i]) {
      throw const FormatException('LFS: bad magic');
    }
  }
  final version = bytes[_magic.length];
  if (version != _versionArgon2id) {
    throw FormatException('LFS: unsupported version 0x$version');
  }
  final paramsStart = _magic.length + 1;
  if (bytes.length < paramsStart + _kdfBlobLen) {
    throw const FormatException('LFS: truncated KDF params');
  }
  final algoId = bytes[paramsStart];
  if (algoId != 0x01) {
    throw FormatException('LFS: unknown KDF algorithm 0x$algoId');
  }
  final bd = ByteData.sublistView(
    bytes,
    paramsStart,
    paramsStart + _kdfBlobLen,
  );
  final memoryKiB = bd.getUint32(1);
  final iterations = bd.getUint32(5);
  final parallelism = bd.getUint8(9);
  if (memoryKiB > _maxMemoryKiB ||
      iterations > _maxIterations ||
      parallelism > _maxParallelism) {
    throw FormatException(
      'LFS: params exceed import caps '
      '(m=$memoryKiB, t=$iterations, p=$parallelism)',
    );
  }
  final saltStart = paramsStart + _kdfBlobLen;
  if (bytes.length < saltStart + _saltLen + _ivLen) {
    throw const FormatException('LFS: truncated payload');
  }
  // Touch salt + iv bounds so coverage attribution reaches the
  // bounds-check branches.
  final saltHash = bytes.sublist(saltStart, saltStart + _saltLen).length;
  final ivHash = bytes
      .sublist(saltStart + _saltLen, saltStart + _saltLen + _ivLen)
      .length;
  saltHash.hashCode;
  ivHash.hashCode;
}
