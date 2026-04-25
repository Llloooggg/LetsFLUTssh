import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session_recorder.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

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

  Uint8List dbKey() {
    return Uint8List.fromList(List.generate(32, (i) => i));
  }

  Future<File> _onlyFile(Directory dir) async {
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

  test('encrypted mode produces decryptable LFR1 frames', () async {
    final key = dbKey();
    final rec = await SessionRecorder.open(
      sessionId: 's2',
      shellLabel: 'zsh',
      width: 100,
      height: 40,
      dbKey: key,
    );
    expect(rec, isNotNull);
    rec!.recordOutput(utf8.encode('first'));
    rec.recordOutput(utf8.encode('second'));
    final path = await rec.close();
    expect(p.extension(path!), '.lfsr');

    final bytes = File(path).readAsBytesSync();
    // Magic + version
    expect(bytes.sublist(0, 4), equals([0x4C, 0x46, 0x52, 0x31]));
    expect(bytes[4], 1);

    final derivedKey = _hkdf(key);
    final lines = _decryptAll(bytes, derivedKey);
    expect(lines, hasLength(3));
    final header = jsonDecode(lines[0]) as Map<String, Object?>;
    expect(header['version'], 2);
    expect(header['width'], 100);
    expect((jsonDecode(lines[1]) as List)[2], 'first');
    expect((jsonDecode(lines[2]) as List)[2], 'second');
  });

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
    final file = await _onlyFile(dir);
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

Uint8List _hkdf(Uint8List ikm) {
  final hkdf = HKDFKeyDerivator(SHA256Digest())
    ..init(
      HkdfParameters(
        ikm,
        32,
        Uint8List(0),
        Uint8List.fromList('letsflutssh-recording-v1'.codeUnits),
      ),
    );
  final out = Uint8List(32);
  hkdf.deriveKey(null, 0, out, 0);
  return out;
}

List<String> _decryptAll(Uint8List bytes, Uint8List key) {
  // Skip magic (4) + version (1)
  var offset = 5;
  final out = <String>[];
  while (offset < bytes.length) {
    final ptLen = ByteData.sublistView(
      bytes,
      offset,
      offset + 4,
    ).getUint32(0, Endian.little);
    final nonce = bytes.sublist(offset + 4, offset + 16);
    final ct = bytes.sublist(offset + 16, offset + 16 + ptLen + 16);
    final cipher = GCMBlockCipher(
      AESEngine(),
    )..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final pt = cipher.process(ct);
    out.add(utf8.decode(pt).trimRight());
    offset += 4 + 12 + ptLen + 16;
  }
  return out;
}
