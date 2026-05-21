/// Coverage for [lfsCoreDbExists], [verifyRustDbReadable] and
/// [ensureRustDbOpen].
///
/// These three helpers wire the Dart bootstrap path against the
/// Rust-owned sqlite handle. The DB path + support directory are
/// resolved Rust-side from the directory pinned at `configStoreInit`
/// (via `dbDefaultPath`), and the SQLCipher open / probe runs through
/// FRB — loaded from the workspace target. The test pins a temp dir.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/rust_db_init.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;
import 'package:path/path.dart' as p;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUpAll(() async {
    await requireFrbLoaded();
    tmp = Directory.systemTemp.createTempSync('rust_db_init_');
    rust_config.configStoreInit(supportDir: tmp.path);
  });

  setUp(() {
    // Shared pinned dir — drop the DB file + sidecars so each test
    // starts from a known existence state.
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File(p.join(tmp.path, 'letsflutssh.db$suffix'));
      if (f.existsSync()) f.deleteSync();
    }
  });

  tearDownAll(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('lfsCoreDbExists', () {
    test('returns false when letsflutssh.db is missing', () async {
      expect(await lfsCoreDbExists(), isFalse);
    });

    test('returns true after the file is created at support dir', () async {
      final path = p.join(tmp.path, 'letsflutssh.db');
      File(path).writeAsBytesSync(const [0]);
      expect(await lfsCoreDbExists(), isTrue);
    });
  });

  group('verifyRustDbReadable', () {
    test('returns true after a successful dbInit against :memory:', () async {
      // Use :memory: so this test does not race the support-dir
      // file slot with the ensureRustDbOpen group below.
      await rust_app.dbInit(path: ':memory:', key: const []);
      expect(await verifyRustDbReadable(), isTrue);
    });
  });

  group('ensureRustDbOpen', () {
    test('asserts when both key and secretId are provided', () async {
      await expectLater(
        ensureRustDbOpen(
          key: Uint8List.fromList(List<int>.filled(32, 7)),
          secretId: 'unused',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('plaintext open creates letsflutssh.db at support dir', () async {
      await ensureRustDbOpen();
      expect(File(p.join(tmp.path, 'letsflutssh.db')).existsSync(), isTrue);
      expect(await lfsCoreDbExists(), isTrue);
    });

    test('plaintext open leaves the DB readable via the probe', () async {
      await ensureRustDbOpen();
      expect(await verifyRustDbReadable(), isTrue);
    });

    test('encrypted open creates the file and stays readable', () async {
      // 32-byte key — SQLCipher AES-256-CBC accepts the raw bytes
      // exactly as the production master-key path supplies them.
      final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      await ensureRustDbOpen(key: key);
      expect(File(p.join(tmp.path, 'letsflutssh.db')).existsSync(), isTrue);
      expect(await verifyRustDbReadable(), isTrue);
    });

    test(
      'idempotent — calling twice on the same path does not throw',
      () async {
        final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 2));
        await ensureRustDbOpen(key: key);
        await ensureRustDbOpen(key: key);
        expect(await verifyRustDbReadable(), isTrue);
      },
    );
  });
}
