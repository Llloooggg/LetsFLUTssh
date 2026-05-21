import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../src/rust/api/bus.dart' as rust_bus;
import '../../src/rust/api/format.dart' as rust_format;
import '../../src/rust/api/recorder.dart' as rust_recorder;
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

  /// Resolved when the Rust worker emits `RecorderStopped` for our
  /// id. [close] awaits it (with a timeout) so the on-disk file is
  /// fully sealed before the caller proceeds. Trap: awaiting only
  /// the enqueue-close future leaves trailing bytes in the worker
  /// mailbox, producing a truncated recording on a fast disconnect.
  /// ARCH §3.13 documents the contract.
  final Completer<void> _stoppedCompleter = Completer<void>();

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
  /// Encryption mode is decided Rust-side from the running session's
  /// active DB key in `SecretStore` — when `app.dbkey.active` holds
  /// bytes the recorder writes encrypted `.lfsr`, when the slot is
  /// empty (plaintext tier) it writes raw asciinema `.cast`. The DB
  /// key never crosses the FRB boundary on this path; HKDF-derive
  /// to the recorder key happens entirely Rust-side via
  /// `recorder_register_from_active`.
  ///
  /// Returns null if the underlying directory cannot be created —
  /// caller treats null as "recording disabled silently for this
  /// session" rather than blocking the connect.
  static Future<SessionRecorder?> open({
    required String sessionId,
    required String shellLabel,
    required int width,
    required int height,
  }) async {
    try {
      final dirPath = await _sessionDirPath(sessionId);
      final isoTs = _isoTimestamp();
      // Rust owns the file-extension decision so the on-disk shape
      // matches the wire format the playback dispatcher routes off.
      // Earlier the Dart side picked `.lfsr` based on `secretsHas`
      // (true even on the plaintext tier because the slot carries
      // empty bytes there), while the Rust register-time check used
      // `!is_empty` — files ended up `.lfsr`-named with plaintext
      // asciinema content and playback failed with "no active DB
      // key". Now Dart hands the base path (no extension) and Rust
      // appends `.lfsr` / `.cast` against the same predicate it
      // uses for the encryption decision.
      final basePath = p.join(dirPath, isoTs);
      // `recorderRegisterFromActive` mkdir's the parent + opens the
      // file at 0600 inside `lfs_core::recorder::register_with_io`,
      // so no Dart-side `File.create` / `hardenFilePerms` is needed.
      final handleId = const Uuid().v4();
      // Rust pulls the DB key from `SecretStore.app.dbkey.active`,
      // runs the `letsflutssh-recording-v1` HKDF-SHA256 derive
      // in-process, and registers the recorder under the derived
      // key. When the active slot is empty (plaintext tier) the
      // recorder registers in plaintext-asciinema mode and the
      // file stays a valid asciinema document.
      final snapshot = await rust_recorder.recorderRegisterFromActive(
        id: handleId,
        sessionId: sessionId,
        basePath: basePath,
      );
      // `snapshot.path` is the final on-disk path with the
      // Rust-chosen extension. Override the local guess so the
      // playback / listing surfaces see the same value.
      final path = snapshot.path;
      final encrypted = snapshot.encrypted;
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
  ///
  /// Waits for `BusEvent_RecorderStopped` before completing so the
  /// on-disk file is fully sealed by the time the caller acts on
  /// the returned path (delete / display / export). The previous
  /// implementation only awaited the enqueue future, which let
  /// every event still in the worker's mailbox race the file
  /// close on a fast shell teardown — ARCH §3.13 documented the
  /// flush guarantee but the code did not enforce it.
  ///
  /// A 2 s timeout protects callers from hanging if the Rust
  /// worker has crashed; on timeout the path is returned but
  /// trailing bytes may be missing.
  Future<String?> close() async {
    if (_closed) return _currentPath;
    _closed = true;
    // Drain the serialised dispatch chain before sending the close
    // marker. Without this, a back-to-back `recordOutput → close`
    // race can schedule Close ahead of the unawaited event FRB
    // calls — the Rust worker then processes Close before the
    // trailing chunk lands and the user sees a truncated recording.
    // `_dispatchEnqueue` swallows its own exception, so this
    // barrier never throws.
    await _dispatchTail;
    // Rust-side `enqueue_blocking` drains any in-flight chunk
    // buffer before the close marker, so the trailing bytes that
    // arrived in the last 10 ms make it onto disk before the file
    // is sealed. The worker drains the mailbox until it hits the
    // close marker, then seals the file.
    try {
      await rust_recorder.recorderQueueEnqueueClose(id: _handleId);
    } catch (e) {
      AppLogger.instance.log(
        'recorderQueueEnqueueClose failed: $e',
        name: 'Recorder',
      );
    }
    try {
      await _stoppedCompleter.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      AppLogger.instance.log(
        'SessionRecorder close: RecorderStopped did not arrive within 2s — '
        'tail bytes may be missing on the final recording',
        name: 'Recorder',
        level: LogLevel.warn,
      );
    }
    await _busSub?.cancel();
    _busSub = null;
    return _currentPath;
  }

  // -----------------------------------------------------------------
  // Implementation
  // -----------------------------------------------------------------

  /// Compose `<app_support>/recordings/<sessionId>/` as a path
  /// string. No filesystem ops — the Rust recorder mkdir's the
  /// directory chain inside `register_with_io` / `enqueue_rotate`
  /// before opening the file.
  static Future<String> _sessionDirPath(String sessionId) async {
    final root = rust_recorder.recorderRecordingsRoot();
    return p.join(root, sessionId);
  }

  /// One-shot migration that fixes recordings written by builds
  /// where the file extension came from the Dart-side
  /// `secretsHas(ACTIVE_DBKEY_SECRET_ID)` check. On the plaintext
  /// tier that slot held empty bytes — `secretsHas` returned true,
  /// the file landed `.lfsr` but the Rust register-time
  /// `!is_empty` check kept the recorder in plaintext-asciinema
  /// mode. Playback then routed by extension to the encrypted
  /// reader and surfaced `RecordingFormatException: no active DB
  /// key — encrypted recording cannot be opened`.
  ///
  /// The Rust helper walks `<app_support>/recordings/` and renames
  /// every `.lfsr` whose first four bytes are not the
  /// [`lfs_core::recorder::LFR_MAGIC`] header. Idempotent: a
  /// fresh-write `.lfsr` file with the magic is left alone.
  /// Returns the count of files renamed so the caller can log it
  /// once on startup; the recordings browser calls this before
  /// the first list build.
  static Future<int> migrateMisnamedRecordings() async {
    try {
      final root = rust_recorder.recorderRecordingsRoot();
      final renamed = await rust_recorder.recorderMigrateMisnamedFiles(
        recordingsRoot: root,
      );
      return renamed;
    } catch (e, st) {
      AppLogger.instance.log(
        'recorder migrate sweep failed',
        name: 'Recorder',
        error: e,
        stackTrace: st,
        level: LogLevel.warn,
      );
      return 0;
    }
  }

  /// Tail of the serialised dispatch chain. Each `_enqueueEvent`
  /// chains its FRB call off the previous tail so the bytes reach
  /// the Rust-side per-id buffer in caller order. Two unawaited
  /// `recorderQueueEnqueueEvent` calls would otherwise race on
  /// `enqueue_event_chunk`'s buffer mutex inside the tokio runtime
  /// — `recordOutput("one") + recordOutput("two")` could land as
  /// `twoone` on disk. Chaining keeps each FRB call in flight one
  /// at a time, so the Rust-side `extend_from_slice` runs in the
  /// order the caller produced the chunks.
  ///
  /// `_dispatchEnqueue` swallows its own exceptions, so the chain
  /// itself never enters an error state.
  Future<void> _dispatchTail = Future<void>.value();

  /// Hand one PTY chunk to the Rust-side recorder queue. The Rust
  /// `enqueue_event_chunk` accumulator coalesces 100/sec russh
  /// `Data` packets into one mailbox entry per ~10 ms / 8 KiB so
  /// the writer worker isn't woken on every chunk. Fire-and-forget
  /// for the caller — the terminal pump never blocks on disk —
  /// but the dispatches are serialised via [_dispatchTail] so the
  /// per-id buffer extends in caller order, and [close] awaits the
  /// tail before sending the close marker.
  void _enqueueEvent(List<int> bytes, RecordDirection dir) {
    if (_closed || bytes.isEmpty) return;
    final direction = switch (dir) {
      RecordDirection.output => rust_recorder.DbRecordDirection.output,
      RecordDirection.input => rust_recorder.DbRecordDirection.input,
    };
    _dispatchTail = _dispatchTail.then(
      (_) => _dispatchEnqueue(bytes, direction),
    );
  }

  Future<void> _dispatchEnqueue(
    List<int> bytes,
    rust_recorder.DbRecordDirection direction,
  ) async {
    try {
      await rust_recorder.recorderQueueEnqueueEvent(
        id: _handleId,
        direction: direction,
        bytes: bytes,
      );
    } catch (e) {
      AppLogger.instance.log(
        'recorderQueueEnqueueEvent failed: $e',
        name: 'Recorder',
      );
    }
  }

  /// Handler for the per-id recorder topic. Three events matter
  /// here: `RecorderRotateRequested` triggers a fresh-file
  /// rotation; `RecorderStarted` (re-emitted by `rotate_to`)
  /// updates our cached `_currentPath`; `RecorderStopped` resolves
  /// the close-flush guard so [close] returns only after the
  /// worker has actually drained its mailbox and sealed the file.
  void _onBusEvent(rust_bus.BusEvent event) {
    switch (event) {
      case rust_bus.BusEvent_RecorderRotateRequested():
        unawaited(_rotate());
      case rust_bus.BusEvent_RecorderStarted(:final path):
        _currentPath = path;
      case rust_bus.BusEvent_RecorderStopped():
        if (!_stoppedCompleter.isCompleted) {
          _stoppedCompleter.complete();
        }
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
      final dirPath = await _sessionDirPath(sessionId);
      final ext = _encrypted ? 'lfsr' : 'cast';
      final isoTs = _isoTimestamp();
      final path = p.join(dirPath, '$isoTs.$ext');
      // Same as the initial-register path: Rust-side rotate worker
      // mkdir's the parent + opens 0600 inside the recorder actor.
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
