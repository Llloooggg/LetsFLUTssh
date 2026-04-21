import '../../utils/logger.dart';
import 'artefact.dart';
import 'migration.dart';
import 'registry.dart';

/// Thrown when an artefact on disk reports a version greater than
/// anything the current build knows how to handle. The user is running
/// an older binary against newer-format state — usually the result of
/// downgrading after a forward migration ran. Runner surfaces this via
/// the report and refuses to start the unlock flow; data is preserved
/// so a re-upgrade recovers cleanly.
class UnsupportedFutureVersionException implements Exception {
  final String artefactId;
  final int onDiskVersion;
  final int knownTargetVersion;

  const UnsupportedFutureVersionException({
    required this.artefactId,
    required this.onDiskVersion,
    required this.knownTargetVersion,
  });

  @override
  String toString() =>
      'UnsupportedFutureVersionException(artefact=$artefactId, '
      'onDisk=$onDiskVersion, knownTarget=$knownTargetVersion)';
}

/// Per-step record of a migration the runner ran (or tried to run).
class MigrationStep {
  final String artefactId;
  final int fromVersion;
  final int toVersion;
  final bool succeeded;
  final Object? error;

  const MigrationStep({
    required this.artefactId,
    required this.fromVersion,
    required this.toVersion,
    required this.succeeded,
    this.error,
  });

  @override
  String toString() =>
      'MigrationStep($artefactId: $fromVersion -> $toVersion, '
      'ok=$succeeded${error != null ? ', error=$error' : ''})';
}

/// Aggregate result of one [MigrationRunner.runOnStartup] call.
class MigrationReport {
  final List<MigrationStep> steps;
  final List<UnsupportedFutureVersionException> futureVersions;
  final Object? fatalError;

  const MigrationReport({
    this.steps = const [],
    this.futureVersions = const [],
    this.fatalError,
  });

  bool get hasFailures =>
      fatalError != null ||
      futureVersions.isNotEmpty ||
      steps.any((s) => !s.succeeded);

  /// True when the runner is entirely satisfied — every artefact is
  /// already at its target version, nothing was migrated, no errors.
  bool get noOp =>
      steps.isEmpty && futureVersions.isEmpty && fatalError == null;

  /// Count of successful migrations; useful for the post-run toast.
  int get migratedCount => steps.where((s) => s.succeeded).length;
}

/// Orchestrator that walks the [MigrationRegistry] and applies any
/// migrations needed to bring on-disk state up to date with the current
/// build's [SchemaVersions].
///
/// Always called at app startup, BEFORE the security init path opens
/// any artefact. Idempotent — calling twice in a row is a no-op on the
/// second call.
class MigrationRunner {
  MigrationRunner(this._registry);

  final MigrationRegistry _registry;

  /// Walk every registered artefact, compute the migration chain, and
  /// apply each step in dependency order. Returns a report; caller
  /// decides whether to surface failures via dialog.
  Future<MigrationReport> runOnStartup() async {
    final List<MigrationStep> steps = [];
    final List<UnsupportedFutureVersionException> future = [];

    final List<Artefact> ordered;
    try {
      ordered = _topoSort(_registry.artefacts, _registry.dependencies);
    } catch (e) {
      AppLogger.instance.log(
        'MigrationRunner: dependency cycle: $e',
        name: 'MigrationRunner',
      );
      return MigrationReport(fatalError: e);
    }

    for (final artefact in ordered) {
      final int onDisk;
      try {
        onDisk = await artefact.readVersion();
      } catch (e) {
        AppLogger.instance.log(
          'MigrationRunner: readVersion(${artefact.id}) failed: $e',
          name: 'MigrationRunner',
        );
        return MigrationReport(steps: steps, fatalError: e);
      }

      // Absent artefact (clean install for this slot) — nothing to do.
      if (onDisk < 0) continue;

      final target = artefact.targetVersion;
      if (onDisk == target) continue;

      if (onDisk > target) {
        future.add(
          UnsupportedFutureVersionException(
            artefactId: artefact.id,
            onDiskVersion: onDisk,
            knownTargetVersion: target,
          ),
        );
        continue;
      }

      // onDisk < target — walk the chain step by step.
      var current = onDisk;
      while (current < target) {
        final step = _findMigration(artefact.id, current);
        if (step == null) {
          final err = StateError(
            'No migration registered for ${artefact.id} '
            'from version $current',
          );
          steps.add(
            MigrationStep(
              artefactId: artefact.id,
              fromVersion: current,
              toVersion: current + 1,
              succeeded: false,
              error: err,
            ),
          );
          return MigrationReport(steps: steps, fatalError: err);
        }

        try {
          await step.apply();
          steps.add(
            MigrationStep(
              artefactId: artefact.id,
              fromVersion: step.fromVersion,
              toVersion: step.toVersion,
              succeeded: true,
            ),
          );
          current = step.toVersion;
        } catch (e) {
          AppLogger.instance.log(
            'MigrationRunner: $step apply failed: $e',
            name: 'MigrationRunner',
          );
          steps.add(
            MigrationStep(
              artefactId: artefact.id,
              fromVersion: step.fromVersion,
              toVersion: step.toVersion,
              succeeded: false,
              error: e,
            ),
          );
          return MigrationReport(steps: steps, fatalError: e);
        }
      }
    }

    return MigrationReport(steps: steps, futureVersions: future);
  }

  /// Return the migration chain that [runOnStartup] would execute
  /// without actually applying anything. Useful for debug builds,
  /// diagnostics, and the registry-completeness unit test. The
  /// returned steps all have `succeeded: false` (they were not run).
  Future<List<MigrationStep>> plan() async {
    final steps = <MigrationStep>[];
    final ordered = _topoSort(_registry.artefacts, _registry.dependencies);
    for (final artefact in ordered) {
      final onDisk = await artefact.readVersion();
      if (onDisk < 0) continue;
      final target = artefact.targetVersion;
      if (onDisk >= target) continue;
      var current = onDisk;
      while (current < target) {
        final step = _findMigration(artefact.id, current);
        if (step == null) {
          steps.add(
            MigrationStep(
              artefactId: artefact.id,
              fromVersion: current,
              toVersion: current + 1,
              succeeded: false,
              error: StateError(
                'No migration registered for ${artefact.id} from $current',
              ),
            ),
          );
          break;
        }
        steps.add(
          MigrationStep(
            artefactId: artefact.id,
            fromVersion: step.fromVersion,
            toVersion: step.toVersion,
            succeeded: false,
          ),
        );
        current = step.toVersion;
      }
    }
    return steps;
  }

  Migration? _findMigration(String artefactId, int fromVersion) {
    for (final m in _registry.migrations) {
      if (m.artefactId == artefactId && m.fromVersion == fromVersion) {
        return m;
      }
    }
    return null;
  }

  /// Kahn's algorithm — order artefacts so every dependency is
  /// migrated before the artefact that depends on it.
  static List<Artefact> _topoSort(
    List<Artefact> artefacts,
    Map<String, List<String>> deps,
  ) {
    final byId = {for (final a in artefacts) a.id: a};
    final indegree = <String, int>{for (final a in artefacts) a.id: 0};
    final adj = <String, List<String>>{
      for (final a in artefacts) a.id: <String>[],
    };

    // Registry may declare dependencies for artefacts that are not yet
    // registered (future-proofing for vault / hash artefacts). Skip
    // both sides when either endpoint is unknown so dangling deps do
    // not poison the indegree map with ids `byId` cannot resolve.
    deps.forEach((id, after) {
      if (!byId.containsKey(id)) return;
      for (final pre in after) {
        if (!byId.containsKey(pre)) continue;
        adj[pre]!.add(id);
        indegree[id] = indegree[id]! + 1;
      }
    });

    final queue = <String>[
      for (final id in indegree.keys)
        if (indegree[id] == 0) id,
    ];
    final ordered = <Artefact>[];
    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      ordered.add(byId[id]!);
      for (final next in adj[id]!) {
        indegree[next] = indegree[next]! - 1;
        if (indegree[next] == 0) queue.add(next);
      }
    }
    if (ordered.length != artefacts.length) {
      throw StateError('Cycle in migration dependencies');
    }
    return ordered;
  }
}
