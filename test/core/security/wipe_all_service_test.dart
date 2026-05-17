import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/security/wipe_all_service.dart';

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('WipeReport', () {
    test('default constructor — every list empty, every flag false', () {
      const r = WipeReport();
      expect(r.deletedFiles, isEmpty);
      expect(r.failedFiles, isEmpty);
      expect(r.keychainPurged, isFalse);
      expect(r.nativeVaultCleared, isFalse);
      expect(r.biometricOverlayCleared, isFalse);
      expect(r.hasFailures, isFalse);
    });

    test('hasFailures flips when failedFiles non-empty', () {
      const r = WipeReport(failedFiles: ['credentials.kdf']);
      expect(r.hasFailures, isTrue);
    });

    test('non-empty deletedFiles alone does not flip hasFailures', () {
      const r = WipeReport(deletedFiles: ['letsflutssh.db']);
      expect(r.hasFailures, isFalse);
    });
  });

  group('WipeAllService', () {
    late Directory tmp;
    late WipeAllService service;
    int evictCalls = 0;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lfs_wipe_');
      evictCalls = 0;
      service = WipeAllService(
        supportDirFactory: () async => tmp,
        // Skip the keychain purge — would touch the host's libsecret
        // and leave state behind.
        purgeKeychain: false,
        credentialCacheEvict: () async => evictCalls++,
      );
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    group('hasPendingWipe', () {
      test('returns false on a clean support dir', () async {
        expect(await service.hasPendingWipe(), isFalse);
      });

      test('returns true after a `.wipe-pending` marker is written', () async {
        // Marker now carries a `LFWP` magic + version-1 byte
        // header so a foreign drop at the path doesn't coerce
        // the next launch into a recovery wipe. Write the
        // exact envelope shape the Rust writer emits.
        final marker = File('${tmp.path}/.wipe-pending');
        marker.writeAsBytesSync(<int>[
          0x4C, 0x46, 0x57, 0x50, // 'L','F','W','P'
          0x01, // version
          ...'42\n'.codeUnits, // body — opaque breadcrumb
        ]);
        expect(await service.hasPendingWipe(), isTrue);
      });
    });

    group('hasAnyState', () {
      test('returns false on a clean support dir', () async {
        expect(await service.hasAnyState(), isFalse);
      });

      test('returns true once a managed security artefact lands', () async {
        // `credentials.kdf` is on the orphan-probe list (Rust side)
        // — its presence alone signals "prior install state".
        File('${tmp.path}/credentials.kdf').writeAsBytesSync(const [0]);
        expect(await service.hasAnyState(), isTrue);
      });
    });

    group('wipeAll', () {
      test('empty support dir → no failures, evict still fires', () async {
        final report = await service.wipeAll();

        expect(evictCalls, 1);
        expect(report.hasFailures, isFalse);
        expect(report.keychainPurged, isFalse);
      });

      test('deletes existing managed files', () async {
        // Pre-seed a managed-file the Rust sweep recognises.
        File('${tmp.path}/credentials.kdf').writeAsBytesSync(const [1, 2, 3]);
        File('${tmp.path}/credentials.verify').writeAsBytesSync(const [4]);

        final report = await service.wipeAll();

        expect(File('${tmp.path}/credentials.kdf').existsSync(), isFalse);
        expect(File('${tmp.path}/credentials.verify').existsSync(), isFalse);
        expect(report.deletedFiles, isNotEmpty);
        expect(report.hasFailures, isFalse);
      });

      test('clears `.wipe-pending` marker once the sweep completes', () async {
        File('${tmp.path}/.wipe-pending').writeAsStringSync('');

        await service.wipeAll();

        expect(File('${tmp.path}/.wipe-pending').existsSync(), isFalse);
      });

      test('a thrown evict callback does not abort the sweep', () async {
        File('${tmp.path}/credentials.kdf').writeAsBytesSync(const [0]);
        final svc = WipeAllService(
          supportDirFactory: () async => tmp,
          purgeKeychain: false,
          credentialCacheEvict: () async {
            throw StateError('cache flush blew up');
          },
        );

        // Should not throw — the orchestrator catches + logs.
        final report = await svc.wipeAll();

        // File sweep still ran.
        expect(File('${tmp.path}/credentials.kdf').existsSync(), isFalse);
        expect(report.hasFailures, isFalse);
      });

      test('null evict hook is allowed (startup-resume path)', () async {
        final svc = WipeAllService(
          supportDirFactory: () async => tmp,
          purgeKeychain: false,
          // credentialCacheEvict intentionally null.
        );
        final report = await svc.wipeAll();
        expect(report.hasFailures, isFalse);
      });

      test('hasPendingWipe is false after a clean wipeAll', () async {
        await service.wipeAll();
        expect(await service.hasPendingWipe(), isFalse);
      });
    });
  });
}
