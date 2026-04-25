import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

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
  /// Hard upper bound on file size before the recorder rolls to a
  /// new file under the same session. 100 MB is large enough for a
  /// multi-hour session of even a vim-heavy editing day; small
  /// enough that the asciinema export of a single recording stays
  /// trivially shareable.
  static const int maxFileBytes = 100 * 1024 * 1024;

  /// HKDF-derived 32-byte AES-256 key. Null in plaintext mode.
  final Uint8List? _key;

  /// Stable across the recorder's lifetime — used in asciinema
  /// timestamp deltas. Captured at construction so the first event's
  /// `t = 0` lines up with the real wall-clock of the session start.
  final DateTime _start;

  /// Open file handle. Re-opened when [_currentBytes] crosses
  /// [maxFileBytes] and a new rotation file is created.
  IOSink? _sink;
  int _currentBytes = 0;
  String? _currentPath;

  /// Outbound writes are queued so events emitted during a flush
  /// don't reorder — a strict serialised tail keeps timestamps
  /// monotonic in the rare case a stdout chunk arrives mid-await.
  final _writeQueue = StreamController<Uint8List>(sync: false);
  StreamSubscription<Uint8List>? _writeSub;

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
    required IOSink sink,
    required String path,
  }) : _key = key,
       _sink = sink,
       _currentPath = path,
       _start = DateTime.now() {
    _writeSub = _writeQueue.stream.listen(_drainOne);
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
      final file = File(path);
      await file.create();
      await hardenFilePerms(path);
      final sink = file.openWrite(mode: FileMode.append);
      // Magic header first so a stray file can be identified out of
      // band. Plaintext mode skips the magic — its content is
      // already directly playable as asciinema.
      if (encrypted) {
        sink.add(_lfrMagic);
        sink.add([_lfrVersion]);
      }
      final recorder = SessionRecorder._(
        sessionId: sessionId,
        terminalShellLabel: shellLabel,
        width: width,
        height: height,
        key: encrypted ? _deriveKey(dbKey) : null,
        sink: sink,
        path: path,
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
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    return _currentPath;
  }

  // -----------------------------------------------------------------
  // Implementation
  // -----------------------------------------------------------------

  static const List<int> _lfrMagic = [0x4C, 0x46, 0x52, 0x31]; // "LFR1"
  static const int _lfrVersion = 1;

  static Future<Directory> _ensureDirectory(String sessionId) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'recordings', sessionId));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Uint8List _deriveKey(Uint8List dbKey) {
    final hkdf = HKDFKeyDerivator(SHA256Digest())
      ..init(HkdfParameters(dbKey, 32, Uint8List(0), _hkdfInfo));
    final out = Uint8List(32);
    hkdf.deriveKey(null, 0, out, 0);
    return out;
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
    final framed = _key != null ? _encryptFrame(plaintext) : plaintext;
    _writeQueue.add(framed);
  }

  Uint8List _encryptFrame(Uint8List plaintext) {
    final nonce = _randomBytes(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(_key!), 128, nonce, Uint8List(0)),
      );
    final ct = cipher.process(plaintext);
    // Frame: [len(4 LE)][nonce(12)][ciphertext+tag]
    final frame = BytesBuilder(copy: false);
    final len = ByteData(4)..setUint32(0, plaintext.length, Endian.little);
    frame.add(len.buffer.asUint8List());
    frame.add(nonce);
    frame.add(ct);
    return frame.toBytes();
  }

  Future<void> _drainOne(Uint8List frame) async {
    if (_sink == null) return;
    if (_currentBytes + frame.length > maxFileBytes) {
      await _rotate();
    }
    _sink!.add(frame);
    _currentBytes += frame.length;
  }

  Future<void> _rotate() async {
    final old = _sink;
    _sink = null;
    await old?.flush();
    await old?.close();
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
    final sink = file.openWrite(mode: FileMode.append);
    if (_key != null) {
      sink.add(_lfrMagic);
      sink.add([_lfrVersion]);
    }
    _sink = sink;
    _currentPath = path;
    _currentBytes = 0;
    _enqueueHeader();
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }
}
