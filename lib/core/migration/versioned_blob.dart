import 'dart:io';
import 'dart:typed_data';

import '../../utils/file_utils.dart';

/// Fixed binary envelope used by every framework-managed artefact.
///
/// Layout:
/// ```
/// offset  size  meaning
/// 0       4     magic = ASCII 'L','F','S',0x01
/// 4       1     artefact id (see [ArtefactIds])
/// 5       1     payload format version
/// 6       N     payload bytes (artefact-specific)
/// ```
///
/// Files predating the envelope are detected as "version 0" — the
/// reader inspects the first 4 bytes; if they do not match the magic
/// the file is treated as a legacy unversioned blob and the
/// corresponding `v0_to_v1` migration is responsible for parsing it
/// and rewriting under the envelope.
///
/// Writes are atomic: bytes go to a `.tmp<rand>` sibling, perms are
/// hardened, then `rename` swaps over the original. A crash mid-write
/// leaves the original intact.
class VersionedBlob {
  /// 4-byte magic prefix written at the head of every envelope.
  static const List<int> magic = [0x4C, 0x46, 0x53, 0x01]; // 'L','F','S',1
  static const int headerLength = 6;

  final int artefactId;
  final int version;
  final Uint8List payload;

  const VersionedBlob({
    required this.artefactId,
    required this.version,
    required this.payload,
  });

  /// Encode header + payload into a contiguous byte buffer.
  Uint8List toBytes() {
    final out = Uint8List(headerLength + payload.length);
    out.setRange(0, 4, magic);
    out[4] = artefactId & 0xFF;
    out[5] = version & 0xFF;
    out.setRange(headerLength, out.length, payload);
    return out;
  }

  /// Parse [bytes] as an envelope. Returns null when the magic does
  /// not match — caller treats null as "legacy unversioned blob,
  /// route through the v0 migration".
  static VersionedBlob? tryParse(Uint8List bytes) {
    if (bytes.length < headerLength) return null;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return null;
    }
    return VersionedBlob(
      artefactId: bytes[4],
      version: bytes[5],
      payload: Uint8List.sublistView(bytes, headerLength),
    );
  }

  /// Read the file at [path] and try to parse it as an envelope.
  /// Returns null if the file is missing, too short, or lacks the
  /// magic header.
  static Future<VersionedBlob?> read(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return tryParse(bytes);
  }

  /// Atomically write a fresh envelope to [path].
  static Future<void> write(
    String path, {
    required int artefactId,
    required int version,
    required Uint8List payload,
  }) async {
    final blob = VersionedBlob(
      artefactId: artefactId,
      version: version,
      payload: payload,
    );
    final bytes = blob.toBytes();
    await File(path).parent.create(recursive: true);
    await writeBytesAtomic(path, bytes);
  }
}
