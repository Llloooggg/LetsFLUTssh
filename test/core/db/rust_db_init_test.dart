/// Coverage for [lfsCoreDbExists], [verifyRustDbReadable] and
/// [ensureRustDbOpen].
///
/// These three helpers wire the Dart bootstrap path against the
/// Rust-owned sqlite handle. They route through path_provider for
/// the support directory and through FRB for the actual SQLCipher
/// open / probe — both must be live for the assertions to mean
/// anything. The path_provider channel is stubbed to a per-test
/// temp directory; FRB is loaded from the workspace target.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/rust_db_init.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:path/path.dart' as p;

import '../../helpers/fake_path_provider.dart';
import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late Directory tmp;

  setUp(() {
    tmp = installFakePathProvider();
  });

  tearDown(() {
    uninstallFakePathProvider(tmp);
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

    test('returns false when path_provider channel is unhandled', () async {
      // Drop the channel handler so getApplicationSupportDirectory
      // surfaces MissingPluginException — the helper must catch and
      // degrade to false rather than propagate.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      expect(await lfsCoreDbExists(), isFalse);
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

    test('swallows path_provider failure rather than propagating', () async {
      // Drop the channel so getApplicationSupportDirectory throws.
      // The helper must log and return without rethrowing — the
      // caller's downstream verifyRustDbReadable probe is what
      // gates the recovery flow, not an unhandled future on the
      // bootstrap rail.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await ensureRustDbOpen();
    });
  });
}
