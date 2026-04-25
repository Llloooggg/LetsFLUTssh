import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/hkdf.dart';

/// One asciinema-v2 event read out of a recording file. The fields
/// mirror the JSON-Lines schema 1:1 — `timestamp` is seconds-since-
/// session-start (the asciinema header carries the wall-clock
/// origin), `direction` is `'o'` (output the user saw) or `'i'`
/// (input the user typed), `data` is the raw text payload.
class RecordingFrame {
  final double timestamp;
  final String direction;
  final String data;

  const RecordingFrame(this.timestamp, this.direction, this.data);
}

/// Decoded asciinema-v2 header — carries the dimensions the
/// recorded shell ran at so playback can resize xterm to match.
class RecordingHeader {
  final int width;
  final int height;
  final int wallClockEpochSeconds;
  final String? shellLabel;

  const RecordingHeader({
    required this.width,
    required this.height,
    required this.wallClockEpochSeconds,
    this.shellLabel,
  });

  static RecordingHeader fromJson(Map<String, Object?> json) => RecordingHeader(
    width: (json['width'] as num?)?.toInt() ?? 80,
    height: (json['height'] as num?)?.toInt() ?? 24,
    wallClockEpochSeconds: (json['timestamp'] as num?)?.toInt() ?? 0,
    shellLabel: (json['env'] is Map<String, Object?>)
        ? ((json['env'] as Map<String, Object?>)['SHELL'] as String?)
        : null,
  );
}

/// Pure decoder for the recording files the [SessionRecorder] writes.
///
/// Two formats:
/// - `.cast` — raw asciinema v2 JSON-Lines, no envelope, written
///   when the running security tier is plaintext.
/// - `.lfsr` — the encrypted envelope: 4-byte `LFR1` magic + 1-byte
///   version + a stream of `[len(4 LE)][nonce(12)][cipher][tag(16)]`
///   AES-256-GCM frames whose plaintext is the same JSON-Lines.
///
/// The reader takes ownership of the file's read lifecycle:
/// [openCast] / [openEncrypted] both expose a `Stream<RecordingFrame>`
/// that yields header-then-events lazily, so a multi-MB recording
/// can be played back without staging the whole timeline in memory.
class RecordingReader {
  RecordingReader._();

  static const _hkdfInfo = 'letsflutssh-recording-v1';
  static const List<int> _expectedMagic = [0x4C, 0x46, 0x52, 0x31];

  /// Walk a `.cast` plaintext recording. The first event is the
  /// asciinema header (a JSON object); subsequent events are
  /// `[t, dir, data]` arrays.
  static Stream<RecordingDecodedLine> openCast(File file) async* {
    await for (final line
        in file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.isEmpty) continue;
      yield RecordingDecodedLine(line);
    }
  }

  /// Walk an encrypted `.lfsr` recording. [dbKey] is the running
  /// session's DB encryption key; the recording key is derived
  /// from it via the same HKDF-SHA-256 chain the recorder used.
  static Stream<RecordingDecodedLine> openEncrypted(File file, Uint8List dbKey) async* {
    final key = _deriveKey(dbKey);
    final raf = file.openSync();
    try {
      // Magic + version sniff. Throw early so the playback UI can
      // show "wrong format" instead of feeding garbage to GCM.
      final head = raf.readSync(5);
      if (head.length < 5) {
        throw const RecordingFormatException('Truncated header');
      }
      for (var i = 0; i < 4; i++) {
        if (head[i] != _expectedMagic[i]) {
          throw const RecordingFormatException('Bad magic — not an LFR1 file');
        }
      }
      if (head[4] != 1) {
        throw RecordingFormatException(
          'Unsupported recording version ${head[4]}',
        );
      }
      while (raf.positionSync() < raf.lengthSync()) {
        final lenBytes = raf.readSync(4);
        if (lenBytes.length < 4) break;
        final ptLen = ByteData.sublistView(
          lenBytes,
        ).getUint32(0, Endian.little);
        final nonce = raf.readSync(12);
        // ciphertext = plaintext-len + 16 (GCM tag)
        final ct = raf.readSync(ptLen + 16);
        final cipher = GCMBlockCipher(AESEngine())
          ..init(
            false,
            AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
          );
        final pt = cipher.process(ct);
        // Each frame's plaintext is one JSON-Lines record with a
        // trailing newline — strip the newline before yielding so
        // the parsed JSON does not carry surprise whitespace.
        yield RecordingDecodedLine(utf8.decode(pt).trimRight());
      }
    } finally {
      raf.closeSync();
    }
  }

  /// Read just the header line of a recording — used to populate
  /// the browser list (duration / dimensions / wall-clock) without
  /// streaming the whole file. Returns null when the recording is
  /// empty or unparseable.
  static Future<RecordingMeta?> readMeta(
    File file, {
    required bool encrypted,
    required Uint8List? dbKey,
  }) async {
    try {
      final stream = encrypted ? openEncrypted(file, dbKey!) : openCast(file);
      RecordingHeader? header;
      var lastTimestamp = 0.0;
      var eventCount = 0;
      await for (final line in stream) {
        final json = jsonDecode(line.value);
        if (header == null && json is Map<String, Object?>) {
          header = RecordingHeader.fromJson(json);
        } else if (json is List && json.length >= 3) {
          eventCount++;
          final ts = (json[0] as num).toDouble();
          if (ts > lastTimestamp) lastTimestamp = ts;
        }
      }
      if (header == null) return null;
      return RecordingMeta(
        header: header,
        durationSeconds: lastTimestamp,
        eventCount: eventCount,
      );
    } catch (_) {
      // Corrupt / wrong-key / truncated — surface as "no meta" so
      // the browser can still list the file with its filesystem
      // size and offer a delete button.
      return null;
    }
  }

  static Uint8List _deriveKey(Uint8List dbKey) {
    final hkdf = HKDFKeyDerivator(SHA256Digest())
      ..init(
        HkdfParameters(
          dbKey,
          32,
          Uint8List(0),
          Uint8List.fromList(_hkdfInfo.codeUnits),
        ),
      );
    final out = Uint8List(32);
    hkdf.deriveKey(null, 0, out, 0);
    return out;
  }
}

/// Parse a raw JSON-Lines record from the recording into either a
/// header object or an event tuple. Caller dispatches on
/// [RecordingFrame] vs [RecordingHeader].
RecordingFrame? decodeEventLine(String line) {
  try {
    final v = jsonDecode(line);
    if (v is List && v.length >= 3) {
      return RecordingFrame(
        (v[0] as num).toDouble(),
        v[1] as String,
        v[2] as String,
      );
    }
  } catch (_) {
    // Header line or malformed record — caller treats as skip.
  }
  return null;
}

/// Thin wrapper around a single JSON-Lines record yielded by the
/// stream readers. Public so the stream type signature stays
/// honest (yielding raw `String` would lose the "this is a record,
/// not arbitrary text" semantic at the type level).
class RecordingDecodedLine {
  final String value;
  RecordingDecodedLine(this.value);
}

/// Aggregated metadata for the browser list view.
class RecordingMeta {
  final RecordingHeader header;
  final double durationSeconds;
  final int eventCount;

  const RecordingMeta({
    required this.header,
    required this.durationSeconds,
    required this.eventCount,
  });
}

/// Thrown when the recording file's bytes do not match the
/// expected format. Surfaced to the playback UI as "this file is
/// not a valid recording" instead of a stack trace.
class RecordingFormatException implements Exception {
  final String message;
  const RecordingFormatException(this.message);
  @override
  String toString() => 'RecordingFormatException: $message';
}
