import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../src/rust/api/crypto.dart' as rust_crypto;
import '../../src/rust/api/recorder.dart' as rust_recorder;
import '../../utils/file_utils.dart';
import '../../utils/logger.dart';

/// Direction marker on a recording event — matches asciinema v2's
/// `"o"` / `"i"` codes so an exported plaintext stream can be played
/// back in any asciinema-compatible viewer.
enum RecordDirection {
  output('o'),
  input('i');

  final String code;
  const RecordDirection(this.code);
}

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
class SessionRecorder {
  /// HKDF-derived 32-byte AES-256 key. Null in plaintext mode.
  final Uint8List? _key;

  /// Per-file byte cap, fetched from
  /// `lfs_core::recorder::MAX_FILE_BYTES` once at open time.
  /// The Rust side owns the cap so the Dart caller does not keep
  /// a stale duplicate.
  final int _maxFileBytes;

  /// Stable across the recorder's lifetime — used in asciinema
  /// timestamp deltas. Captured at construction so the first event's
  /// `t = 0` lines up with the real wall-clock of the session start.
  final DateTime _start;

  /// Active Rust-side recorder handle id. Re-allocated on each
  /// rotation (`_rotate` closes the previous handle and registers
  /// a fresh one). Empty when the recorder is closed.
  String _handleId;
  int _currentBytes = 0;
  String? _currentPath;

  /// Outbound writes are queued so events emitted during a flush
  /// don't reorder — a strict serialised tail keeps timestamps
  /// monotonic in the rare case a stdout chunk arrives mid-await.
  final _writeQueue = StreamController<Uint8List>(sync: false);
  StreamSubscription<void>? _writeSub;

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
    required Uint8List? key,
    required String handleId,
    required String path,
    required int maxFileBytes,
  }) : _key = key,
       _maxFileBytes = maxFileBytes,
       _handleId = handleId,
       _currentPath = path,
       _start = DateTime.now() {
    // The Rust recorder owns IO + encryption now; the Dart queue
    // serialises asciinema header + per-event JSON lines and hands
    // each plaintext buffer to the FRB endpoint. Arrival order
    // through `asyncMap` keeps timestamps monotonic across the FRB
    // round-trip.
    _writeSub = _writeQueue.stream.asyncMap(_drainOne).listen((_) {});
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
      final isoTs = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
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
      final cap = (await rust_recorder.recorderMaxFileBytes()).toInt();
      final recorder = SessionRecorder._(
        sessionId: sessionId,
        terminalShellLabel: shellLabel,
        width: width,
        height: height,
        key: key,
        handleId: handleId,
        path: path,
        maxFileBytes: cap,
      );
      // Emit asciinema v2 header line so any plaintext export — and
      // the encrypted file once decrypted — starts with a valid
      // asciinema document.
      recorder._enqueueHeader();
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
    await _writeQueue.close();
    await _writeSub?.cancel();
    if (_handleId.isNotEmpty) {
      try {
        await rust_recorder.recorderClose(id: _handleId);
      } catch (e) {
        AppLogger.instance.log('recorderClose failed: $e', name: 'Recorder');
      }
      _handleId = '';
    }
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

  void _enqueueHeader() {
    final header = jsonEncode({
      'version': 2,
      'width': width,
      'height': height,
      'timestamp': _start.millisecondsSinceEpoch ~/ 1000,
      'env': {'TERM': 'xterm-256color', 'SHELL': terminalShellLabel},
    });
    _enqueuePlaintext(Uint8List.fromList(utf8.encode('$header\n')));
  }

  void _enqueueEvent(List<int> bytes, RecordDirection dir) {
    if (_closed || bytes.isEmpty) return;
    final delta = DateTime.now().difference(_start).inMicroseconds / 1e6;
    final str = utf8.decode(bytes, allowMalformed: true);
    final line = jsonEncode([delta, dir.code, str]);
    _enqueuePlaintext(Uint8List.fromList(utf8.encode('$line\n')));
  }

  void _enqueuePlaintext(Uint8List plaintext) {
    if (_closed) return;
    _writeQueue.add(plaintext);
  }

  /// Drain one queued plaintext buffer onto disk via the Rust
  /// recorder. Encryption (when `_key` is set) + the
  /// `[len][nonce][ct+tag]` framing both happen Rust-side; Dart
  /// only owns the asciinema header / event-line composition that
  /// produced `plaintext`.
  Future<void> _drainOne(Uint8List plaintext) async {
    if (_handleId.isEmpty) return;
    try {
      final total = await rust_recorder.recorderRecordFrame(
        id: _handleId,
        plaintext: plaintext,
      );
      _currentBytes = total.toInt();
    } catch (e) {
      AppLogger.instance.log(
        'recorderRecordFrame failed: $e',
        name: 'Recorder',
      );
      return;
    }
    if (_currentBytes > _maxFileBytes) {
      await _rotate();
    }
  }

  /// Roll the active recording to a fresh timestamped file under
  /// the same session directory. Path generation stays Dart-side
  /// (`getApplicationSupportDirectory` + `hardenFilePerms` are
  /// platform-aware); the Rust `recorderRotateTo` call closes the
  /// current handle, opens the new file in append mode, writes
  /// magic + version when encrypted, and resets the byte counter
  /// in one atomic step under the registry mutex. The handle id
  /// stays stable so bus subscribers tracking the recording across
  /// rotations don't re-bind.
  Future<void> _rotate() async {
    if (_handleId.isEmpty) return;
    final dir = await _ensureDirectory(sessionId);
    final isoTs = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final ext = _key != null ? 'lfsr' : 'cast';
    final path = p.join(dir.path, '$isoTs.$ext');
    final file = File(path);
    await file.create();
    await hardenFilePerms(path);
    try {
      final snap = await rust_recorder.recorderRotateTo(
        id: _handleId,
        newPath: path,
      );
      _currentPath = snap.path;
      _currentBytes = snap.bytesWritten.toInt();
    } catch (e) {
      AppLogger.instance.log('recorderRotateTo failed: $e', name: 'Recorder');
      return;
    }
    _enqueueHeader();
  }
}
