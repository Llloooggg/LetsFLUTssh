import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/migration/archive_registry.dart';
import 'package:letsflutssh/core/migration/migration.dart';

class _FakeMigration extends Migration {
  _FakeMigration({required this.fromVersion, required this.toVersion});

  @override
  String get artefactId => 'archive';
  @override
  final int fromVersion;
  @override
  final int toVersion;
  @override
  Future<void> apply() async {}
}

void main() {
  group('ArchiveMigrationRegistry', () {
    test('baseline is empty — chain() returns [] when from == to', () {
      final reg = ArchiveMigrationRegistry();
      expect(reg.migrations, isEmpty);
      expect(reg.chain(1, 1), isEmpty);
    });

    test('register + chain composes migrations from a start to target', () {
      final reg = ArchiveMigrationRegistry();
      reg.register(_FakeMigration(fromVersion: 1, toVersion: 2));
      reg.register(_FakeMigration(fromVersion: 2, toVersion: 3));
      final steps = reg.chain(1, 3);
      expect(steps, hasLength(2));
      expect(steps.first.fromVersion, 1);
      expect(steps.first.toVersion, 2);
      expect(steps.last.fromVersion, 2);
      expect(steps.last.toVersion, 3);
    });

    test('register rejects a duplicate fromVersion', () {
      final reg = ArchiveMigrationRegistry();
      reg.register(_FakeMigration(fromVersion: 1, toVersion: 2));
      expect(
        () => reg.register(_FakeMigration(fromVersion: 1, toVersion: 2)),
        throwsStateError,
      );
    });

    test('chain throws when a step is missing', () {
      final reg = ArchiveMigrationRegistry();
      reg.register(_FakeMigration(fromVersion: 1, toVersion: 2));
      expect(() => reg.chain(1, 5), throwsStateError);
    });

    test('singleton archiveMigrationRegistry starts empty', () {
      expect(archiveMigrationRegistry.migrations, isEmpty);
    });
  });
}
