import 'artefact.dart';
import 'migration.dart';

/// Mutable registry of every artefact + migration the runner knows
/// about. Populated at app startup *before* `MigrationRunner.run` so
/// composition stays explicit (no service-locator scanning).
///
/// The list is intentionally simple: order does not matter for
/// migrations within a single artefact (the runner sorts by
/// `fromVersion`); order between artefacts is encoded via
/// [Registry.dependencies] so the runner can run one artefact's
/// migrations after another's (e.g. config before vault, since vault
/// layout reads tier from config).
class MigrationRegistry {
  MigrationRegistry({
    List<Artefact>? artefacts,
    List<Migration>? migrations,
    Map<String, List<String>>? dependencies,
  }) : _artefacts = [...?artefacts],
       _migrations = [...?migrations],
       _dependencies = {...?dependencies};

  final List<Artefact> _artefacts;
  final List<Migration> _migrations;

  /// `{artefactId: [otherArtefactIds...]}` — every entry in the value
  /// list must run its migrations BEFORE the key artefact runs its
  /// own. Used by the runner's topological sort.
  final Map<String, List<String>> _dependencies;

  List<Artefact> get artefacts => List.unmodifiable(_artefacts);
  List<Migration> get migrations => List.unmodifiable(_migrations);
  Map<String, List<String>> get dependencies => Map.unmodifiable(_dependencies);

  void registerArtefact(Artefact artefact) {
    if (_artefacts.any((a) => a.id == artefact.id)) {
      throw StateError('Duplicate artefact id: ${artefact.id}');
    }
    _artefacts.add(artefact);
  }

  void registerMigration(Migration migration) {
    final dup = _migrations.any(
      (m) =>
          m.artefactId == migration.artefactId &&
          m.fromVersion == migration.fromVersion,
    );
    if (dup) {
      throw StateError(
        'Duplicate migration for ${migration.artefactId} '
        'from ${migration.fromVersion}',
      );
    }
    _migrations.add(migration);
  }

  /// Declare that [artefactId] should be migrated only after every
  /// id in [after] has been migrated. Cycles throw at runner time.
  void declareDependency(String artefactId, List<String> after) {
    _dependencies.putIfAbsent(artefactId, () => []).addAll(after);
  }

  /// Convenience constant for the default empty registry — used as
  /// initial state in tests + on first app launch before any
  /// registration happens.
  static MigrationRegistry empty() => MigrationRegistry();
}
