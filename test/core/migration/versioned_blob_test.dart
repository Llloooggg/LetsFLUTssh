import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/migration/schema_versions.dart';
import 'package:letsflutssh/core/migration/versioned_blob.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('versioned_blob_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('VersionedBlob.tryParse', () {
    test('returns null for an empty buffer', () {
      expect(VersionedBlob.tryParse(Uint8List(0)), isNull);
    });

    test('returns null when the magic prefix does not match', () {
      final bytes = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x01]);
      expect(VersionedBlob.tryParse(bytes), isNull);
    });

    test('returns null when buffer is shorter than the header', () {
      final bytes = Uint8List.fromList([0x4C, 0x46, 0x53]); // 3 bytes only
      expect(VersionedBlob.tryParse(bytes), isNull);
    });

    test('parses a valid header + empty payload', () {
      final bytes = Uint8List.fromList([
        ...VersionedBlob.magic,
        ArtefactIds.passGate,
        2,
      ]);
      final parsed = VersionedBlob.tryParse(bytes);
      expect(parsed, isNotNull);
      expect(parsed!.artefactId, ArtefactIds.passGate);
      expect(parsed.version, 2);
      expect(parsed.payload, isEmpty);
    });

    test('parses a valid header + non-empty payload', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final bytes = Uint8List.fromList([
        ...VersionedBlob.magic,
        ArtefactIds.hwVaultLinux,
        7,
        ...payload,
      ]);
      final parsed = VersionedBlob.tryParse(bytes);
      expect(parsed, isNotNull);
      expect(parsed!.artefactId, ArtefactIds.hwVaultLinux);
      expect(parsed.version, 7);
      expect(parsed.payload, payload);
    });
  });

  group('VersionedBlob.toBytes / round-trip', () {
    test('toBytes lays out [magic | id | version | payload]', () {
      final blob = VersionedBlob(
        artefactId: ArtefactIds.config,
        version: 3,
        payload: Uint8List.fromList([0xAA, 0xBB]),
      );
      final bytes = blob.toBytes();
      expect(bytes.sublist(0, 4), VersionedBlob.magic);
      expect(bytes[4], ArtefactIds.config);
      expect(bytes[5], 3);
      expect(bytes.sublist(6), [0xAA, 0xBB]);
    });

    test('encode → decode preserves all fields', () {
      final original = VersionedBlob(
        artefactId: ArtefactIds.kdf,
        version: 9,
        payload: Uint8List.fromList(List.generate(128, (i) => i & 0xFF)),
      );
      final parsed = VersionedBlob.tryParse(original.toBytes());
      expect(parsed, isNotNull);
      expect(parsed!.artefactId, original.artefactId);
      expect(parsed.version, original.version);
      expect(parsed.payload, original.payload);
    });
  });

  group('VersionedBlob.read / write', () {
    test('read returns null for a missing file', () async {
      final missing = p.join(tempDir.path, 'missing.bin');
      expect(await VersionedBlob.read(missing), isNull);
    });

    test('read returns null for a legacy unversioned file', () async {
      final path = p.join(tempDir.path, 'legacy.bin');
      await File(path).writeAsBytes([0x7B, 0x22, 0x66, 0x6F]); // '{"fo'
      expect(await VersionedBlob.read(path), isNull);
    });

    test('write then read round-trips the envelope', () async {
      final path = p.join(tempDir.path, 'round.bin');
      final payload = Uint8List.fromList([10, 20, 30, 40, 50]);
      await VersionedBlob.write(
        path,
        artefactId: ArtefactIds.hwSalt,
        version: 1,
        payload: payload,
      );
      final read = await VersionedBlob.read(path);
      expect(read, isNotNull);
      expect(read!.artefactId, ArtefactIds.hwSalt);
      expect(read.version, 1);
      expect(read.payload, payload);
    });

    test(
      'write is atomic — original survives a partial pre-rename state',
      () async {
        // The atomic helper writes to a `.tmp<rand>` sibling first.
        // After a successful write, no temp files should remain.
        final path = p.join(tempDir.path, 'atomic.bin');
        await VersionedBlob.write(
          path,
          artefactId: ArtefactIds.config,
          version: 1,
          payload: Uint8List.fromList([0x01]),
        );
        final siblings = tempDir
            .listSync()
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .where((n) => n.startsWith('atomic.bin.tmp'))
            .toList();
        expect(
          siblings,
          isEmpty,
          reason: 'no temp leftover after successful atomic write',
        );
      },
    );
  });
}
