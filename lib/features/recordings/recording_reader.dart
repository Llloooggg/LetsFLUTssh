import 'dart:async';

import '../../core/security/active_dbkey.dart';
import '../../src/rust/api/app.dart' as rust_secrets;
import '../../src/rust/api/recorder.dart' as rust_recorder;

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
/// recorded shell ran at so playback can resize the terminal to match.
///
/// Parsed Rust-side via `lfs_core::recorder::reader::decode_header_line`
/// over the FRB sync shim `recorder_decode_header_line`. The Dart
/// class is a thin value holder around the FRB-typed mirror so the
/// asciinema-v2 wire-shape grammar (field set, default fallbacks,
/// `env.SHELL` extraction) stays in one place Rust-side.
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

  /// Lift the FRB-typed mirror into the Dart value class. The JSON
  /// parse runs Rust-side (`recorder_decode_header_line`); this
  /// factory is the sole constructor every reader path uses.
  factory RecordingHeader.fromRust(rust_recorder.DbRecordingHeader header) =>
      RecordingHeader(
        width: header.width,
        height: header.height,
        wallClockEpochSeconds: header.wallClockEpochSeconds,
        shellLabel: header.shellLabel,
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
/// LFR encrypted versions:
/// * `0x01` — per-frame AES-GCM with empty AAD (legacy). Files
///   written before the AAD-binding upgrade keep decoding through
///   this path; new files never emit at this level.
/// * `0x02` — per-frame AAD = `frame_index_u64_le`. The writer
///   tracks a monotonic counter per recording (resets on rotate);
///   the reader recomputes it from frame position so a swap of two
///   frames invalidates the GCM tag at both swapped positions.
///
/// Both branches route through the same Rust-side
/// [`recorderOpenForPlayback`] FRB stream — Rust dispatches on the
/// file extension internally, so the Dart consumer hands the path
/// in once without branching. Reads stay sequential (no random
/// access into the timeline); a multi-MB recording plays back
/// without staging the whole timeline on the Dart heap.
///
/// Scrub-bar seek routes through [`recorderSeek`] + the
/// `recorderOpenForPlaybackAt` variant: the FRB layer binary-searches
/// `<recording>.idx` for the largest entry at or before `targetMs`,
/// returns the matched offset, and the playback adapter restarts the
/// iterator pre-positioned at that frame boundary. Legacy recordings
/// without a sidecar return `null` from `recorderSeek` and the dialog
/// disables the scrub bar with a tooltip.
class RecordingReader {
  RecordingReader._();

  /// Walk a recording file (either `.cast` plaintext or `.lfsr`
  /// encrypted) and yield every JSON-Lines record. The first event
  /// is the asciinema header (a JSON object); subsequent events are
  /// `[t, dir, data]` arrays. Errors during open / decrypt / decode
  /// surface as in-stream `DbPlaybackEvent.error` values which the
  /// loop maps to a [`RecordingFormatException`] so the playback UI
  /// keeps its existing branch shape.
  static Stream<RecordingDecodedLine> open(String filePath) async* {
    // The Rust playback adapter emits a tagged `DbPlaybackEvent`
    // per frame: `line` carries the decoded record, `error` (when
    // set) carries the abort reason. The shape works around FRB's
    // unawaited return-channel future: a `Result::Err` from the
    // Rust side would leak as an uncaught zone error, never
    // reaching `await for`. Emitting errors as in-stream events
    // keeps them on the consumer's catch surface.
    await for (final event in rust_recorder.recorderOpenForPlayback(
      path: filePath,
    )) {
      final err = event.error;
      if (err != null) {
        throw RecordingFormatException(err);
      }
      final line = event.line;
      if (line != null) {
        yield RecordingDecodedLine(line);
      }
    }
  }

  /// Variant of [`open`] that pre-positions the decoder at
  /// `byteOffset` + `startFrameIndex` returned by [`seek`]. The
  /// FRB sink yields events starting from the next frame past the
  /// offset — the asciinema header is NOT re-emitted, so the caller
  /// must already have the geometry from a prior `readMeta` /
  /// initial-open call.
  static Stream<RecordingDecodedLine> openAt(
    String filePath, {
    required int byteOffset,
    required int startFrameIndex,
  }) async* {
    await for (final event in rust_recorder.recorderOpenForPlaybackAt(
      path: filePath,
      startOffset: BigInt.from(byteOffset),
      startFrameIndex: BigInt.from(startFrameIndex),
    )) {
      final err = event.error;
      if (err != null) {
        throw RecordingFormatException(err);
      }
      final line = event.line;
      if (line != null) {
        yield RecordingDecodedLine(line);
      }
    }
  }

  /// Resolve `<filePath>.idx` and binary-search for the largest entry
  /// at or before `targetMs`. Returns the matched entry's byte offset
  /// into the main file plus the sidecar's entry index (the AAD
  /// counter the next encrypted frame is signed under). Returns null
  /// when no sidecar exists, the sidecar is empty, or the target
  /// lands before the first event — caller falls back to either a
  /// full re-decode (target after first event) or a no-op (target
  /// before first event).
  static Future<RecordingSeekHit?> seek(
    String filePath, {
    required int targetMs,
    required bool encrypted,
  }) async {
    final hit = await rust_recorder.recorderSeek(
      recordingPath: filePath,
      targetMs: BigInt.from(targetMs),
      encrypted: encrypted,
    );
    if (hit == null) return null;
    return RecordingSeekHit(
      byteOffset: hit.offset.toInt(),
      startFrameIndex: hit.entryIndex.toInt(),
      timestampMs: hit.timestampMs,
    );
  }

  /// Read just the header line of a recording — used to populate
  /// the browser list (duration / dimensions / wall-clock) without
  /// streaming the whole file. Returns null when the recording is
  /// empty or unparseable.
  ///
  /// `encrypted` short-circuits the FRB round-trip when the
  /// running tier has no active DB key — an encrypted recording
  /// cannot be decrypted, so the meta read would surface as a
  /// stream error and we'd still return null. Avoiding the
  /// spawn_blocking task per row keeps the browser scan cheap when
  /// the user opens it on a plaintext / auto-locked tier.
  static Future<RecordingMeta?> readMeta(
    String filePath, {
    required bool encrypted,
  }) async {
    if (encrypted && !rust_secrets.secretsHas(id: kActiveDbKeySecretId)) {
      return null;
    }
    try {
      RecordingHeader? header;
      var lastTimestamp = 0.0;
      var eventCount = 0;
      await for (final line in open(filePath)) {
        // Dispatch on the typed `DbRecordingLine` enum the Rust
        // decoder returns — header (object) lands on `Header`,
        // event (3-tuple) lands on `Event`, malformed lines and
        // unrelated shapes collapse to `Other` and are skipped.
        // No Dart-side `jsonDecode` lives in this loop.
        final decoded = rust_recorder.recorderDecodeLine(line: line.value);
        decoded.when(
          header: (h) {
            header ??= RecordingHeader.fromRust(h);
          },
          event: (e) {
            eventCount++;
            if (e.timestamp > lastTimestamp) lastTimestamp = e.timestamp;
          },
          other: () {},
        );
      }
      final resolvedHeader = header;
      if (resolvedHeader == null) return null;
      return RecordingMeta(
        header: resolvedHeader,
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
}

/// Parse a raw JSON-Lines record from the recording into either a
/// header object or an event tuple. Routes through the Rust-side
/// `recorder_decode_event_line` so the asciinema-v2 wire shape
/// stays in one place — the encrypted-envelope decode that
/// produces this line already lives Rust-side. Caller dispatches
/// on [RecordingFrame] vs the header (returned as `null` from
/// here; the playback dialog reads the header line through a
/// dedicated path).
RecordingFrame? decodeEventLine(String line) {
  final event = rust_recorder.recorderDecodeEventLine(line: line);
  if (event == null) return null;
  return RecordingFrame(event.timestamp, event.direction, event.data);
}

/// Parse a raw JSON-Lines record as the asciinema-v2 header object.
/// Routes through the Rust-side `recorder_decode_header_line` FRB
/// sync helper — same wire-shape ownership as [`decodeEventLine`].
/// Returns `null` for event tuples and any malformed shape so the
/// caller can fall through to the event-decode path.
RecordingHeader? decodeHeaderLine(String line) {
  final header = rust_recorder.recorderDecodeHeaderLine(line: line);
  if (header == null) return null;
  return RecordingHeader.fromRust(header);
}

/// Thin wrapper around a single JSON-Lines record yielded by the
/// stream readers. Public so the stream type signature stays
/// honest (yielding raw `String` would lose the "this is a record,
/// not arbitrary text" semantic at the type level).
class RecordingDecodedLine {
  final String value;
  RecordingDecodedLine(this.value);
}

/// Hit returned from [`RecordingReader.seek`]. Carries everything the
/// playback dialog needs to resume from a scrub target: the byte
/// offset to restart the decoder at, the sidecar entry index (= AAD
/// counter for the next encrypted frame), and the timestamp of the
/// matched entry (so the UI can snap the scrub thumb to the actual
/// frame boundary instead of the requested target).
class RecordingSeekHit {
  final int byteOffset;
  final int startFrameIndex;
  final int timestampMs;

  const RecordingSeekHit({
    required this.byteOffset,
    required this.startFrameIndex,
    required this.timestampMs,
  });
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
