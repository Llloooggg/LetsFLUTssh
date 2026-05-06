/// Pure-logic coverage for [DbMigrationReportHelpers].
///
/// The helpers reshape the FRB-generated migration report into the
/// noOp / hasFailures / migratedCount predicates the toast + reset
/// dialog branches read. Test the predicate truth tables directly
/// against const-constructed reports — no FRB / no platform.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/migration/migration_runner.dart';
import 'package:letsflutssh/src/rust/api/migration.dart' as rust_migration;

void main() {
  rust_migration.DbMigrationReport report({
    List<rust_migration.DbMigrationStep> steps = const [],
    List<rust_migration.DbUnsupportedFutureVersion> futureVersions = const [],
    String? fatalError,
  }) => rust_migration.DbMigrationReport(
    steps: steps,
    futureVersions: futureVersions,
    fatalError: fatalError,
  );

  rust_migration.DbMigrationStep step({
    String artefactId = 'config.json',
    int fromVersion = 1,
    int toVersion = 2,
    bool succeeded = true,
    String? error,
  }) => rust_migration.DbMigrationStep(
    artefactId: artefactId,
    fromVersion: fromVersion,
    toVersion: toVersion,
    succeeded: succeeded,
    error: error,
  );

  rust_migration.DbUnsupportedFutureVersion futureVersion({
    String artefactId = 'config.json',
    int onDiskVersion = 99,
    int knownTargetVersion = 2,
  }) => rust_migration.DbUnsupportedFutureVersion(
    artefactId: artefactId,
    onDiskVersion: onDiskVersion,
    knownTargetVersion: knownTargetVersion,
  );

  group('DbMigrationReportHelpers.noOp', () {
    test('true when every list empty and no fatal error', () {
      expect(report().noOp, isTrue);
    });

    test('false when a step ran (even if it succeeded)', () {
      expect(report(steps: [step()]).noOp, isFalse);
    });

    test('false when a future-version artefact is present', () {
      expect(report(futureVersions: [futureVersion()]).noOp, isFalse);
    });

    test('false when a fatal error is present', () {
      expect(report(fatalError: 'boom').noOp, isFalse);
    });
  });

  group('DbMigrationReportHelpers.hasFailures', () {
    test('false on an empty report', () {
      expect(report().hasFailures, isFalse);
    });

    test('false when every step succeeded and no other failures', () {
      expect(
        report(steps: [step(), step(fromVersion: 2, toVersion: 3)]).hasFailures,
        isFalse,
      );
    });

    test('true on any non-succeeded step', () {
      expect(
        report(
          steps: [
            step(),
            step(succeeded: false, error: 'permission denied'),
          ],
        ).hasFailures,
        isTrue,
      );
    });

    test('true on a future-version artefact (newer-than-this-build)', () {
      expect(report(futureVersions: [futureVersion()]).hasFailures, isTrue);
    });

    test('true on any fatal error', () {
      expect(report(fatalError: 'panicked').hasFailures, isTrue);
    });
  });

  group('DbMigrationReportHelpers.migratedCount', () {
    test('zero on an empty steps list', () {
      expect(report().migratedCount, 0);
    });

    test('zero when every step failed', () {
      expect(
        report(
          steps: [
            step(succeeded: false, error: 'a'),
            step(fromVersion: 2, toVersion: 3, succeeded: false, error: 'b'),
          ],
        ).migratedCount,
        0,
      );
    });

    test('counts only succeeded steps, ignores failed mixed in', () {
      expect(
        report(
          steps: [
            step(),
            step(fromVersion: 2, toVersion: 3, succeeded: false, error: 'x'),
            step(fromVersion: 3, toVersion: 4),
          ],
        ).migratedCount,
        2,
      );
    });
  });
}
