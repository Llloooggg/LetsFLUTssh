import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session_recorder.dart';
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;
import 'package:path/path.dart' as p;

import '../../helpers/frb_bootstrap.dart';

void main() {
  // SessionRecorder open/write/close routes through `lfs_core::recorder`
  // (FRB). The unit suite previously skipped these tests when the
  // FRB native lib was unavailable; now `requireFrbLoaded` boots the
  // real `liblfs_frb.so` so we exercise the actual round-trip end
  // to end. Encrypted-mode coverage stays in
  // `lfs_core::crypto::tests` (KAT round-trip + AES-GCM correctness).
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    await requireFrbLoaded();
    tempDir = await Directory.systemTemp.createTemp('session_recorder_test_');
    // The recorder resolves <support>/recordings from the dir pinned at
    // configStoreInit; pin this temp dir so the round-trip writes land
    // where the assertions read.
    rust_config.configStoreInit(supportDir: tempDir.path);
  });

  setUp(() {
    // Shared pinned dir across the file — clear the recordings tree so
    // each test starts fresh.
    final rec = Directory(p.join(tempDir.path, 'recordings'));
    if (rec.existsSync()) rec.deleteSync(recursive: true);
  });

  tearDownAll(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<File> onlyFile(Directory dir) async {
    // Filter out the `.idx` sidecar — every recording lands as a
    // main file plus its index sibling. The tests pin the main
    // file's contents; the sidecar has its own coverage in the
    // Rust-side `index_sidecar` unit tests.
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => !f.path.endsWith('.idx'))
        .toList();
    expect(files, hasLength(1), reason: 'expected exactly one recording');
    return files.single;
  }

  test('plaintext mode writes raw asciinema JSON-Lines', () async {
    final rec = await SessionRecorder.open(
      sessionId: 's1',
      shellLabel: 'bash',
      width: 80,
      height: 24,
    );
    expect(rec, isNotNull);
    rec!.recordOutput(utf8.encode('hello'));
    rec.recordInput(utf8.encode('q'));
    final path = await rec.close();
    expect(path, isNotNull);
    expect(p.extension(path!), '.cast');

    final lines = File(path).readAsLinesSync();
    // Header line + 2 events.
    expect(lines, hasLength(3));
    final header = jsonDecode(lines[0]) as Map<String, Object?>;
    expect(header['version'], 2);
    expect(header['width'], 80);
    expect(header['height'], 24);
    final out = jsonDecode(lines[1]) as List;
    expect(out[1], 'o');
    expect(out[2], 'hello');
    final inp = jsonDecode(lines[2]) as List;
    expect(inp[1], 'i');
    expect(inp[2], 'q');
  });

  test('close is idempotent', () async {
    final rec = await SessionRecorder.open(
      sessionId: 's3',
      shellLabel: 'bash',
      width: 80,
      height: 24,
    );
    final first = await rec!.close();
    final again = await rec.close();
    expect(again, equals(first));
  });

  test('record* after close is silently dropped', () async {
    final rec = await SessionRecorder.open(
      sessionId: 's4',
      shellLabel: 'bash',
      width: 80,
      height: 24,
    );
    await rec!.close();
    rec.recordOutput(utf8.encode('ignored'));
    final dir = Directory(p.join(tempDir.path, 'recordings', 's4'));
    final file = await onlyFile(dir);
    final lines = file.readAsLinesSync();
    // Only the header — recordOutput after close is a no-op.
    expect(lines, hasLength(1));
  });

  test('writes an event with non-ASCII payload intact', () async {
    final rec = await SessionRecorder.open(
      sessionId: 's5',
      shellLabel: 'bash',
      width: 80,
      height: 24,
    );
    rec!.recordOutput(utf8.encode('café 漢 🎉'));
    final path = await rec.close();
    final lines = File(path!).readAsLinesSync();
    expect((jsonDecode(lines[1]) as List)[2], 'café 漢 🎉');
  });

  // Encrypted-mode round-trip stays in `lfs_core::crypto::tests` —
  // KAT tests + AES-GCM correctness exercise the same HKDF / encrypt
  // primitives the recorder pulls in. Re-running them through the
  // Dart layer adds no coverage that the Rust suite doesn't already
  // pin down.

  // Back-to-back `recordOutput` calls without an `await` between
  // them must land on disk in caller order. The previous fire-and-
  // forget dispatch raced concurrent FRB tasks for the per-id
  // buffer mutex inside the tokio runtime, so a `one + two`
  // sequence could arrive at the buffer as `two + one` and replay
  // `twoone`. The dispatch chain pins caller order at the Dart
  // boundary.
  test('back-to-back recordOutput chunks land in caller order', () async {
    final rec = await SessionRecorder.open(
      sessionId: 's6',
      shellLabel: 'bash',
      width: 80,
      height: 24,
    );
    expect(rec, isNotNull);
    const chunks = ['one', 'two', 'three', 'four', 'five', 'six'];
    for (final chunk in chunks) {
      rec!.recordOutput(utf8.encode(chunk));
    }
    final path = await rec!.close();
    final lines = File(path!).readAsLinesSync();
    final payloads = lines
        .skip(1)
        .map((l) => (jsonDecode(l) as List)[2] as String)
        .join();
    expect(payloads, chunks.join());
  });
}
