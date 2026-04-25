import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session_recorder.dart';
import 'package:letsflutssh/features/recordings/recording_reader.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
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
      dbKey: null,
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
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final rec = await SessionRecorder.open(
      sessionId: 'sb',
      shellLabel: 'bash',
      width: 80,
      height: 24,
      dbKey: key,
    );
    expect(rec, isNotNull);
    rec!.recordOutput(utf8.encode('one'));
    rec.recordOutput(utf8.encode('two'));
    final path = await rec.close();

    final lines = <String>[];
    await for (final dec in RecordingReader.openEncrypted(File(path!), key)) {
      lines.add(dec.value);
    }
    expect(lines, hasLength(3));
    final outOne = jsonDecode(lines[1]) as List;
    final outTwo = jsonDecode(lines[2]) as List;
    expect(outOne[2], 'one');
    expect(outTwo[2], 'two');
  });

  test('readMeta returns duration + dimensions', () async {
    final rec = await SessionRecorder.open(
      sessionId: 'sc',
      shellLabel: 'bash',
      width: 132,
      height: 40,
      dbKey: null,
    );
    rec!.recordOutput(utf8.encode('hi'));
    final path = await rec.close();
    final meta = await RecordingReader.readMeta(
      File(path!),
      encrypted: false,
      dbKey: null,
    );
    expect(meta, isNotNull);
    expect(meta!.header.width, 132);
    expect(meta.header.height, 40);
    expect(meta.eventCount, 1);
  });

  test('readMeta returns null on a corrupt encrypted file', () async {
    final f = File(p.join(tempDir.path, 'corrupt.lfsr'));
    await f.writeAsBytes([0xFF, 0xFE, 0xFD, 0xFC, 0x01]);
    final meta = await RecordingReader.readMeta(
      f,
      encrypted: true,
      dbKey: Uint8List(32),
    );
    expect(meta, isNull);
  });
}
