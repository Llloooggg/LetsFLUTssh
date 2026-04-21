import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/migration/artefact.dart';
import 'package:letsflutssh/core/migration/migration.dart';
import 'package:letsflutssh/core/migration/migration_runner.dart';
import 'package:letsflutssh/core/migration/registry.dart';

class _StubArtefact extends Artefact {
  _StubArtefact({
    required this.id,
    required this.targetVersion,
    required int onDiskVersion,
  }) : _onDiskVersion = onDiskVersion;

  @override
  final String id;
  @override
  final int targetVersion;
  int _onDiskVersion;

  void setOnDiskVersion(int v) => _onDiskVersion = v;

  @override
  Future<int> readVersion() async => _onDiskVersion;
}

class _RecordingMigration extends Migration {
  _RecordingMigration({
    required this.artefactId,
    required this.fromVersion,
    required this.toVersion,
    this.onApply,
    this.shouldThrow = false,
    List<String>? log,
  }) : _log = log ?? <String>[];

  @override
  final String artefactId;
  @override
  final int fromVersion;
  @override
  final int toVersion;

  final Future<void> Function()? onApply;
  final bool shouldThrow;
  final List<String> _log;
  List<String> get log => _log;

  @override
  Future<void> apply() async {
    _log.add('apply:$artefactId:$fromVersion->$toVersion');
    if (shouldThrow) throw StateError('boom');
    if (onApply != null) await onApply!();
  }
}

void main() {
  group('MigrationRunner.runOnStartup', () {
    test('no-op when no artefacts are registered', () async {
      final runner = MigrationRunner(MigrationRegistry.empty());
      final report = await runner.runOnStartup();
      expect(report.noOp, isTrue);
      expect(report.steps, isEmpty);
      expect(report.futureVersions, isEmpty);
      expect(report.fatalError, isNull);
    });

    test('skips artefacts already at their target version', () async {
      final reg = MigrationRegistry();
      reg.registerArtefact(
        _StubArtefact(id: 'a', targetVersion: 2, onDiskVersion: 2),
      );
      final report = await MigrationRunner(reg).runOnStartup();
      expect(report.steps, isEmpty);
      expect(report.noOp, isTrue);
    });

    test(
      'skips artefacts that do not exist on disk yet (version -1)',
      () async {
        final reg = MigrationRegistry();
        reg.registerArtefact(
          _StubArtefact(id: 'a', targetVersion: 3, onDiskVersion: -1),
        );
        final report = await MigrationRunner(reg).runOnStartup();
        expect(report.steps, isEmpty);
        expect(report.fatalError, isNull);
      },
    );

    test('runs the chain of migrations from on-disk to target', () async {
      final artefact = _StubArtefact(
        id: 'config',
        targetVersion: 3,
        onDiskVersion: 0,
      );
      final reg = MigrationRegistry();
      reg.registerArtefact(artefact);
      final shared = <String>[];
      reg.registerMigration(
        _RecordingMigration(
          artefactId: 'config',
          fromVersion: 0,
          toVersion: 1,
          log: shared,
          onApply: () async => artefact.setOnDiskVersion(1),
        ),
      );
      reg.registerMigration(
        _RecordingMigration(
          artefactId: 'config',
          fromVersion: 1,
          toVersion: 2,
          log: shared,
          onApply: () async => artefact.setOnDiskVersion(2),
        ),
      );
      reg.registerMigration(
        _RecordingMigration(
          artefactId: 'config',
          fromVersion: 2,
          toVersion: 3,
          log: shared,
          onApply: () async => artefact.setOnDiskVersion(3),
        ),
      );
      final report = await MigrationRunner(reg).runOnStartup();
      expect(report.hasFailures, isFalse);
      expect(report.migratedCount, 3);
      expect(report.steps.map((s) => s.toVersion).toList(), [1, 2, 3]);
      expect(shared, [
        'apply:config:0->1',
        'apply:config:1->2',
        'apply:config:2->3',
      ]);
    });

    test('reports unsupported future version without erroring', () async {
      final reg = MigrationRegistry();
      reg.registerArtefact(
        _StubArtefact(id: 'config', targetVersion: 1, onDiskVersion: 99),
      );
      final report = await MigrationRunner(reg).runOnStartup();
      expect(report.fatalError, isNull);
      expect(report.futureVersions, hasLength(1));
      expect(report.futureVersions.first.artefactId, 'config');
      expect(report.futureVersions.first.onDiskVersion, 99);
      expect(report.hasFailures, isTrue);
    });

    test('halts and reports when a migration step is missing', () async {
      // Only the 0 -> 1 migration is registered, but target is 2.
      // The runner should advance once, then fail to find the next step.
      final artefact = _StubArtefact(
        id: 'config',
        targetVersion: 2,
        onDiskVersion: 0,
      );
      final reg = MigrationRegistry();
      reg.registerArtefact(artefact);
      reg.registerMigration(
        _RecordingMigration(
          artefactId: 'config',
          fromVersion: 0,
          toVersion: 1,
          onApply: () async => artefact.setOnDiskVersion(1),
        ),
      );
      final report = await MigrationRunner(reg).runOnStartup();
      expect(report.fatalError, isA<StateError>());
      expect(report.steps, hasLength(2)); // 0->1 succeeded, 1->2 failed
      expect(report.steps.first.succeeded, isTrue);
      expect(report.steps.last.succeeded, isFalse);
    });

    test('halts when a migration apply throws', () async {
      final reg = MigrationRegistry();
      reg.registerArtefact(
        _StubArtefact(id: 'config', targetVersion: 1, onDiskVersion: 0),
      );
      reg.registerMigration(
        _RecordingMigration(
          artefactId: 'config',
          fromVersion: 0,
          toVersion: 1,
          shouldThrow: true,
        ),
      );
      final report = await MigrationRunner(reg).runOnStartup();
      expect(report.fatalError, isA<StateError>());
      expect(report.steps, hasLength(1));
      expect(report.steps.first.succeeded, isFalse);
    });

    test('runs artefacts in declared dependency order', () async {
      final logs = <String>[];

      final a = _StubArtefact(id: 'config', targetVersion: 1, onDiskVersion: 0);
      final b = _StubArtefact(id: 'vault', targetVersion: 1, onDiskVersion: 0);
      final reg = MigrationRegistry();
      // Register vault first to ensure ordering doesn't fall back to
      // registration order.
      reg.registerArtefact(b);
      reg.registerArtefact(a);
      reg.registerMigration(
        _RecordingMigration(
          artefactId: 'config',
          fromVersion: 0,
          toVersion: 1,
          log: logs,
          onApply: () async => a.setOnDiskVersion(1),
        ),
      );
      reg.registerMigration(
        _RecordingMigration(
          artefactId: 'vault',
          fromVersion: 0,
          toVersion: 1,
          log: logs,
          onApply: () async => b.setOnDiskVersion(1),
        ),
      );
      reg.declareDependency('vault', ['config']);

      final report = await MigrationRunner(reg).runOnStartup();
      expect(report.hasFailures, isFalse);
      // Config must run before vault.
      final firstApply = logs.firstWhere((l) => l.startsWith('apply:config'));
      final secondApply = logs.firstWhere((l) => l.startsWith('apply:vault'));
      expect(logs.indexOf(firstApply) < logs.indexOf(secondApply), isTrue);
    });

    test('detects a dependency cycle and reports a fatal error', () async {
      final reg = MigrationRegistry();
      reg.registerArtefact(
        _StubArtefact(id: 'a', targetVersion: 1, onDiskVersion: 0),
      );
      reg.registerArtefact(
        _StubArtefact(id: 'b', targetVersion: 1, onDiskVersion: 0),
      );
      reg.declareDependency('a', ['b']);
      reg.declareDependency('b', ['a']);
      final report = await MigrationRunner(reg).runOnStartup();
      expect(report.fatalError, isA<StateError>());
    });

    test(
      'tolerates dependencies whose dependent id is not registered',
      () async {
        // Regression: buildAppMigrationRegistry declares deps for
        // vault artefacts that are not yet registered. The old
        // _topoSort mis-reported this as "dependency cycle: Null
        // check operator used on a null value" on every fresh
        // install, routing the user through the corrupt-DB dialog.
        final reg = MigrationRegistry();
        reg.registerArtefact(
          _StubArtefact(id: 'config', targetVersion: 1, onDiskVersion: -1),
        );
        reg.declareDependencies(
          const ['unregistered_vault', 'unregistered_hash'],
          const ['config'],
        );
        final report = await MigrationRunner(reg).runOnStartup();
        expect(report.fatalError, isNull);
        expect(report.hasFailures, isFalse);
      },
    );
  });

  group('MigrationRegistry guards', () {
    test('rejects duplicate artefact ids', () {
      final reg = MigrationRegistry();
      reg.registerArtefact(
        _StubArtefact(id: 'a', targetVersion: 1, onDiskVersion: 0),
      );
      expect(
        () => reg.registerArtefact(
          _StubArtefact(id: 'a', targetVersion: 1, onDiskVersion: 0),
        ),
        throwsStateError,
      );
    });

    test('rejects duplicate migrations for the same fromVersion', () {
      final reg = MigrationRegistry();
      reg.registerMigration(
        _RecordingMigration(artefactId: 'a', fromVersion: 0, toVersion: 1),
      );
      expect(
        () => reg.registerMigration(
          _RecordingMigration(artefactId: 'a', fromVersion: 0, toVersion: 2),
        ),
        throwsStateError,
      );
    });
  });
}
