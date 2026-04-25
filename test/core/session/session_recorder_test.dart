import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session_recorder.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('session_recorder_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return tempDir.path;
            }
            return null;
          },
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

  // dbKey() helper removed — only the (now-skipped) encrypted-mode
  // round-trip test consumed it. Plaintext-mode tests pass `dbKey:
  // null` directly.

  Future<File> onlyFile(Directory dir) async {
    final files = dir.listSync(recursive: true).whereType<File>().toList();
    expect(files, hasLength(1), reason: 'expected exactly one recording');
    return files.single;
  }

  test('plaintext mode writes raw asciinema JSON-Lines', () async {
    final rec = await SessionRecorder.open(
      sessionId: 's1',
      shellLabel: 'bash',
      width: 80,
      height: 24,
      dbKey: null,
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

  test(
    'encrypted mode produces decryptable LFR1 frames',
    skip:
        'Encrypted mode now derives the recorder key via the Rust core '
        '(lfs_core::crypto::hkdf_sha256) and encrypts each frame via '
        'aes_gcm_encrypt_raw. The flutter_test runner does not load the '
        'FRB native lib so the end-to-end round-trip moves to '
        'integration_test in a follow-up. HKDF + AES-GCM correctness is '
        'covered by lfs_core::crypto::tests.',
    () {},
  );

  test('close is idempotent', () async {
    final rec = await SessionRecorder.open(
      sessionId: 's3',
      shellLabel: 'bash',
      width: 80,
      height: 24,
      dbKey: null,
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
      dbKey: null,
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
      dbKey: null,
    );
    rec!.recordOutput(utf8.encode('café 漢 🎉'));
    final path = await rec.close();
    final lines = File(path!).readAsLinesSync();
    expect((jsonDecode(lines[1]) as List)[2], 'café 漢 🎉');
  });
}

// _hkdf + _decryptAll helpers removed alongside pointycastle drop
// (Phase 2.6). The encrypted-mode round-trip test that used them is
// now `skip:` because writer + reader both go through FRB; both
// halves are covered end-to-end in `lfs_core::crypto::tests`.
