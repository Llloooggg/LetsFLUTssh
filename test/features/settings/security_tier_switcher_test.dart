import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/features/settings/security_tier_switcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late SecurityTierSwitcher switcher;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tier_switcher_test_');
    db = AppDatabase(NativeDatabase.memory());
    switcher = SecurityTierSwitcher(
      markerFileFactory: () async =>
          File('${tempDir.path}/.tier-transition-pending'),
      keyFactory: () => Uint8List.fromList(List<int>.filled(32, 7)),
      // Stub the rekey — in-memory drift DB cannot run
      // SQLite3MultipleCiphers' PRAGMA rekey, but the switcher's
      // contract (write marker → rekey → apply wrapper …) is the
      // unit under test here.
      rekey: (_, _) async {},
    );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('SecurityTierSwitcher.switchTier', () {
    test(
      'walks every step in order and clears the marker at the end',
      () async {
        final order = <String>[];
        await switcher.switchTier(
          db: db,
          targetMarkerPayload: '{"tier":"keychain"}',
          applyWrapper: (_) async => order.add('applyWrapper'),
          persistConfig: (_) async => order.add('persistConfig'),
          clearPrevious: () async => order.add('clearPrevious'),
        );
        expect(order, ['applyWrapper', 'persistConfig', 'clearPrevious']);
        expect(await switcher.readPendingMarker(), isNull);
      },
    );

    test('marker is written before rekey and cleared after success', () async {
      String? observedMarker;
      await switcher.switchTier(
        db: db,
        targetMarkerPayload: '{"tier":"paranoid"}',
        applyWrapper: (_) async {
          // By the time the wrapper runs, the marker has been
          // written and rekey has succeeded. Read it from disk to
          // confirm.
          observedMarker = await switcher.readPendingMarker();
        },
        persistConfig: (_) async {},
        clearPrevious: () async {},
      );
      expect(observedMarker, '{"tier":"paranoid"}');
      expect(await switcher.readPendingMarker(), isNull);
    });

    test(
      'applyWrapper failure leaves marker in place for crash recovery',
      () async {
        await expectLater(
          switcher.switchTier(
            db: db,
            targetMarkerPayload: '{"tier":"hardware"}',
            applyWrapper: (_) async => throw StateError('vault write failed'),
            persistConfig: (_) async {},
            clearPrevious: () async {},
          ),
          throwsA(isA<StateError>()),
        );
        // Marker survives — next startup can complete or roll back.
        expect(await switcher.readPendingMarker(), '{"tier":"hardware"}');
      },
    );

    test('clearMarker is idempotent on a clean dir', () async {
      await switcher.clearMarker();
      expect(await switcher.readPendingMarker(), isNull);
    });
  });
}
