import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/active_dbkey.dart';
import 'package:letsflutssh/core/session/session_recorder.dart';
import 'package:letsflutssh/features/recordings/recording_reader.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_secrets;
import 'package:path/path.dart' as p;

import '../../helpers/frb_bootstrap.dart';

void main() {
  // Recorder writer + RecordingReader both go through `lfs_core`
  // (recorder + crypto). The unit suite previously skipped the
  // round-trip tests because the FRB native lib wasn't bootstrapped;
  // `requireFrbLoaded` boots `liblfs_frb.so` so the real
  // open/write/close/read path runs end-to-end.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rec_reader_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? tempDir.path
              : null,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('cast file: writer → reader roundtrip yields header + events', () async {
    final rec = await SessionRecorder.open(
      sessionId: 'sa',
      shellLabel: 'bash',
      width: 80,
      height: 24,
    );
    expect(rec, isNotNull);
    rec!.recordOutput(utf8.encode('hello'));
    rec.recordInput(utf8.encode('q'));
    final path = await rec.close();
    expect(path, isNotNull);

    final lines = <String>[];
    await for (final dec in RecordingReader.openCast(File(path!))) {
      lines.add(dec.value);
    }
    expect(lines, hasLength(3));
    final header = jsonDecode(lines[0]) as Map<String, Object?>;
    expect(header['version'], 2);
    final out = jsonDecode(lines[1]) as List;
    expect(out[1], 'o');
    expect(out[2], 'hello');
  });

  test('encrypted file: reader rebuilds the same lines', () async {
    // Stage a deterministic DB key in the active SecretStore slot
    // so the recorder picks the encrypted (.lfsr) branch and the
    // reader can derive the same recording key. Caller drops the
    // slot at the end so other tests start clean.
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    rust_secrets.secretsPut(id: kActiveDbKeySecretId, bytes: key);
    addTearDown(() => rust_secrets.secretsDrop(id: kActiveDbKeySecretId));
    final rec = await SessionRecorder.open(
      sessionId: 'sb',
      shellLabel: 'bash',
      width: 80,
      height: 24,
    );
    expect(rec, isNotNull);
    rec!.recordOutput(utf8.encode('one'));
    rec.recordOutput(utf8.encode('two'));
    final path = await rec.close();

    // The Rust-side recorder queue coalesces sub-window chunks
    // inside `enqueue_event_chunk` (10 ms / 8 KiB) before waking
    // the writer worker. Two back-to-back `recordOutput` calls in
    // the same micro-batch therefore produce one event carrying
    // the concatenation. We assert the payload + the byte order
    // rather than per-call event count — that's the user-facing
    // contract (what they saw on screen replays in order), and
    // the line count is an implementation artefact of the
    // batching window.
    final lines = <String>[];
    await for (final dec in RecordingReader.openEncrypted(File(path!))) {
      lines.add(dec.value);
    }
    // At minimum: header + ≥ 1 output event.
    expect(lines.length, greaterThanOrEqualTo(2));
    final payloads = lines
        .skip(1)
        .map((l) => (jsonDecode(l) as List)[2] as String)
        .join();
    expect(payloads, 'onetwo');
  });

  test('readMeta returns duration + dimensions', () async {
    final rec = await SessionRecorder.open(
      sessionId: 'sc',
      shellLabel: 'bash',
      width: 132,
      height: 40,
    );
    rec!.recordOutput(utf8.encode('hi'));
    final path = await rec.close();
    final meta = await RecordingReader.readMeta(File(path!), encrypted: false);
    expect(meta, isNotNull);
    expect(meta!.header.width, 132);
    expect(meta.header.height, 40);
    expect(meta.eventCount, 1);
  });

  test('readMeta returns null on a corrupt encrypted file', () async {
    // Active SecretStore slot must be populated; otherwise the reader
    // throws "no active key" before it ever gets to the corrupt-bytes
    // branch we're trying to exercise.
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    rust_secrets.secretsPut(id: kActiveDbKeySecretId, bytes: key);
    addTearDown(() => rust_secrets.secretsDrop(id: kActiveDbKeySecretId));
    final f = File(p.join(tempDir.path, 'corrupt.lfsr'));
    await f.writeAsBytes([0xFF, 0xFE, 0xFD, 0xFC, 0x01]);
    final meta = await RecordingReader.readMeta(f, encrypted: true);
    expect(meta, isNull);
  });

  // Regression: the per-frame `uint32` length prefix was read
  // straight into
  // `raf.readSync(ptLen + 16)` with no sanity cap. A malformed
  // `.lfsr` planted under the recordings dir with `0xffffffff` as
  // the first frame length would pull a 4 GiB allocation before
  // the AEAD failure had a chance to fire — local DoS just by
  // opening the recordings panel. The reader now rejects any frame
  // whose declared plaintext length exceeds the per-frame cap.
  test('rejects oversized frame length prefix without allocating', () async {
    // Same staging as the corrupt-file test — the reader has to
    // accept a key before it can hit the per-frame size cap.
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    rust_secrets.secretsPut(id: kActiveDbKeySecretId, bytes: key);
    addTearDown(() => rust_secrets.secretsDrop(id: kActiveDbKeySecretId));
    final f = File(p.join(tempDir.path, 'oversized.lfsr'));
    final bytes = <int>[
      // Magic + version.
      0x4C, 0x46, 0x52, 0x31, 0x01,
      // Frame length prefix = 0xffffffff (4 GiB) — well past the
      // 16 MiB cap. The reader must throw before reading further.
      0xFF, 0xFF, 0xFF, 0xFF,
    ];
    await f.writeAsBytes(bytes);
    final meta = await RecordingReader.readMeta(f, encrypted: true);
    // readMeta wraps every error as Ok(None) so the panel can list
    // the file with a delete button. The bound-check is what we're
    // really asserting — without the cap the await above would
    // attempt a multi-GB allocation and either OOM the test
    // process or hang.
    expect(meta, isNull);
  });
}
