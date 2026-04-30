import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../src/rust/api/bus.dart' as rust_bus;
import '../../src/rust/api/crypto.dart' as rust_crypto;
import '../../src/rust/api/format.dart' as rust_format;
import '../../src/rust/api/recorder.dart' as rust_recorder;
import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import '../bus/app_bus.dart';

/// Direction marker on a recording event — matches asciinema v2's
/// `"o"` / `"i"` codes. Mapped onto `lfs_core::recorder::RecordDirection`
/// (FRB-mirrored as [rust_recorder.DbRecordDirection]) inside
/// [_enqueueEvent].
enum RecordDirection { output, input }

/// Per-shell session recorder.
///
/// Captures the user-visible terminal output stream plus the input
/// keystrokes, framed as asciinema v2 events, and persists them
/// encrypted at rest under the same key material the rest of the
/// app uses (HKDF-derived from the DB encryption key, info-tagged
/// for key-separation). Recordings live as discrete files under
/// `<appSupport>/recordings/<sessionId>/<isoTimestamp>.lfsr`.
///
/// **Why per-shell, not per-connection.** Multi-pane connections
/// run independent shell channels — each pane has its own xterm
/// buffer, scrollback, and dimensions. A connection-level recorder
/// would interleave bytes from N shells into a single timeline that
/// no playback tool could un-mix. Per-shell keeps each recording
/// straight-line.
///
/// **Why asciinema v2 inside an encryption envelope, not a custom
/// binary format.** asciinema is the de-facto interop format —
/// `asciinema play file.cast` plays it on any platform without our
/// app installed. By keeping the plaintext shape standard we get
/// `Export to .cast` for free at any future point: decrypt → write
/// out the same JSON-Lines we already produce. A custom binary
/// format would lock recordings inside our app forever.
///
/// **Why per-event GCM frames.** Each event is wrapped in its own
/// `[len(4 LE)][nonce(12)][cipher(len)][tag(16)]` frame so a
/// truncated tail (e.g. crashed app, full disk mid-write) loses
/// only the trailing event, not the whole timeline. Random nonces
/// per frame plus the same authenticated key give us standard GCM
/// guarantees per event.
///
/// **Plaintext mode.** When the running [SecurityTier] is
/// `plaintext`, the recorder writes raw asciinema JSON-Lines (no
/// envelope, no encryption) to a `.cast` file, with `chmod 600`.
/// The user already opted out of crypto at the tier level — adding
/// a different surface for one feature would be misleading. The
/// file extension differs (`.cast` vs `.lfsr`) so the loader can
/// pick the right path without reading magic bytes first.
///
/// **Write ordering.** All header / event / rotate / close calls
/// route through the per-id Rust write queue
/// (`recorder_queue_enqueue_*`); the Rust worker drains in arrival
/// order. Concurrent stdout chunks land on disk in the order they
/// were emitted even when the FRB runtime fans them out across
/// threads.
class SessionRecorder {
  /// Has the underlying recording an encryption key set on the
  /// Rust side. Drives the file-extension pick on rotation
  /// (`.lfsr` vs `.cast`); the actual key bytes live Rust-side
  /// for the recording's lifetime.
  final bool _encrypted;

  /// Active Rust-side recorder handle id. Re-used across
  /// rotations — the Rust worker swaps the file handle in place
  /// so subscribers tracking the recording don't have to re-bind.
  final String _handleId;
  String? _currentPath;

  /// Subscription to the per-id recorder bus topic — flips the
  /// file path on rotate-requested and remembers the last
  /// reported on-disk path so [close] returns the freshest value.
  StreamSubscription<rust_bus.BusEvent>? _busSub;

  /// Set by [close]; subsequent record calls become no-ops so the
  /// shell teardown's last bytes do not throw on a closed sink.
  bool _closed = false;

  final String sessionId;
  final String terminalShellLabel;
  final int width;
  final int height;

  SessionRecorder._({
    required this.sessionId,
    required this.terminalShellLabel,
    required this.width,
    required this.height,
    required bool encrypted,
    required String handleId,
    required String path,
  }) : _encrypted = encrypted,
       _handleId = handleId,
       _currentPath = path {
    _busSub = AppBus.instance.subscribeRecorder(_handleId).listen(_onBusEvent);
  }

  /// Open a recorder rooted at the platform's app-support directory.
  ///
  /// [dbKey] is the running session's DB encryption key; when null
  /// the recorder writes plaintext asciinema (`.cast`) instead of
  /// encrypted (`.lfsr`). Returns null if the underlying directory
  /// cannot be created — caller treats null as "recording disabled
  /// silently for this session" rather than blocking the connect.
  static Future<SessionRecorder?> open({
    required String sessionId,
    required String shellLabel,
    required int width,
    required int height,
    required Uint8List? dbKey,
  }) async {
    try {
      final dir = await _ensureDirectory(sessionId);
      final encrypted = dbKey != null;
      final ext = encrypted ? 'lfsr' : 'cast';
      final isoTs = _isoTimestamp();
      final path = p.join(dir.path, '$isoTs.$ext');
      // Empty file with hardened perms before Rust opens its
      // append-mode handle — keeps the existing 0600 / no-group
      // discipline regardless of which side owns the writer.
      final file = File(path);
      await file.create();
      await hardenFilePerms(path);
      final key = encrypted ? await _deriveKey(dbKey) : null;
      final handleId = const Uuid().v4();
      // Rust opens the file in append mode and writes the LFR1
      // magic + version when `key` is non-empty. Plaintext mode
      // (empty key bytes) leaves the file untouched at open so the
      // result stays a valid asciinema document.
      await rust_recorder.recorderRegister(
        id: handleId,
        sessionId: sessionId,
        path: path,
        key: key ?? Uint8List(0),
      );
      // Spawn the per-id worker before any enqueue arrives. The
      // worker owns the asciinema event ordering on disk.
      await rust_recorder.recorderQueueSpawn(id: handleId);
      final recorder = SessionRecorder._(
        sessionId: sessionId,
        terminalShellLabel: shellLabel,
        width: width,
        height: height,
        encrypted: encrypted,
        handleId: handleId,
        path: path,
      );
      // Emit asciinema v2 header line so any plaintext export — and
      // the encrypted file once decrypted — starts with a valid
      // asciinema document.
      await rust_recorder.recorderQueueEnqueueHeader(
        id: handleId,
        width: width,
        height: height,
        shellLabel: shellLabel,
      );
      return recorder;
    } catch (e, st) {
      AppLogger.instance.log(
        'SessionRecorder.open failed',
        name: 'Recorder',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Record a chunk of bytes the user saw on the terminal.
  void recordOutput(List<int> bytes) =>
      _enqueueEvent(bytes, RecordDirection.output);

  /// Record a chunk of bytes the user typed (after xterm has
  /// processed them into the wire-format the shell sees — same
  /// layer the broadcast wrapper uses).
  void recordInput(List<int> bytes) =>
      _enqueueEvent(bytes, RecordDirection.input);

  /// Flush queued frames and close the file. Returns the path of the
  /// last written file so callers (UI delete actions, settings) can
  /// reference it.
  Future<String?> close() async {
    if (_closed) return _currentPath;
    _closed = true;
    try {
      await rust_recorder.recorderQueueEnqueueClose(id: _handleId);
    } catch (e) {
      AppLogger.instance.log(
        'recorderQueueEnqueueClose failed: $e',
        name: 'Recorder',
      );
    }
    await _busSub?.cancel();
    _busSub = null;
    return _currentPath;
  }

  // -----------------------------------------------------------------
  // Implementation
  // -----------------------------------------------------------------

  static Future<Directory> _ensureDirectory(String sessionId) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'recordings', sessionId));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Uint8List> _deriveKey(Uint8List dbKey) async {
    final out = await rust_crypto.cryptoHkdfSha256(
      ikm: dbKey,
      salt: Uint8List(0),
      info: _hkdfInfo,
      length: 32,
    );
    return Uint8List.fromList(out);
  }

  // Distinct from any other HKDF context the app uses so a key
  // recovered from a recording cannot decrypt the DB and vice versa.
  static final Uint8List _hkdfInfo = Uint8List.fromList(
    'letsflutssh-recording-v1'.codeUnits,
  );

  void _enqueueEvent(List<int> bytes, RecordDirection dir) {
    if (_closed || bytes.isEmpty) return;
    // Fire-and-forget. The Rust worker holds the mailbox; ordering
    // across calls is preserved because tokio mpsc is FIFO.
    unawaited(
      rust_recorder
          .recorderQueueEnqueueEvent(
            id: _handleId,
            direction: switch (dir) {
              RecordDirection.output => rust_recorder.DbRecordDirection.output,
              RecordDirection.input => rust_recorder.DbRecordDirection.input,
            },
            bytes: Uint8List.fromList(bytes),
          )
          .catchError((Object e) {
            AppLogger.instance.log(
              'recorderQueueEnqueueEvent failed: $e',
              name: 'Recorder',
            );
          }),
    );
  }

  /// Handler for the per-id recorder topic. Two events matter
  /// here: `RecorderRotateRequested` triggers a fresh-file
  /// rotation; `RecorderStarted` (re-emitted by `rotate_to`)
  /// updates our cached `_currentPath`.
  void _onBusEvent(rust_bus.BusEvent event) {
    switch (event) {
      case rust_bus.BusEvent_RecorderRotateRequested():
        unawaited(_rotate());
      case rust_bus.BusEvent_RecorderStarted(:final path):
        _currentPath = path;
      case _:
        break;
    }
  }

  /// Allocate a fresh file under the same session dir and ask the
  /// Rust worker to roll over to it. The Rust side closes the old
  /// file, opens the new one in append mode, writes the magic +
  /// version when encrypted, resets the byte counter, then re-
  /// emits the asciinema header — order matters so a decrypted
  /// recording stays a valid asciinema document mid-rotation.
  Future<void> _rotate() async {
    if (_closed) return;
    try {
      final dir = await _ensureDirectory(sessionId);
      final ext = _encrypted ? 'lfsr' : 'cast';
      final isoTs = _isoTimestamp();
      final path = p.join(dir.path, '$isoTs.$ext');
      final file = File(path);
      await file.create();
      await hardenFilePerms(path);
      await rust_recorder.recorderQueueEnqueueRotate(
        id: _handleId,
        newPath: path,
      );
      await rust_recorder.recorderQueueEnqueueHeader(
        id: _handleId,
        width: width,
        height: height,
        shellLabel: terminalShellLabel,
      );
    } catch (e) {
      AppLogger.instance.log(
        'SessionRecorder rotate failed: $e',
        name: 'Recorder',
      );
    }
  }

  /// Routes through `lfs_core::format::format_filesafe_iso_timestamp`
  /// so the colon-replacement + fractional-drop grammar lives one
  /// place.
  static String _isoTimestamp() {
    final now = DateTime.now().toUtc();
    return rust_format.formatFilesafeIsoTimestamp(
      year: now.year,
      month: now.month,
      day: now.day,
      hour: now.hour,
      minute: now.minute,
      second: now.second,
    );
  }
}
