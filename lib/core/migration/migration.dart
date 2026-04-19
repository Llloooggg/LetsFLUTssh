/// One step in the migration chain for a single artefact.
///
/// Each Migration covers exactly one (artefactId, fromVersion ->
/// toVersion) transition. To go from version 0 to version 3 the
/// runner composes three Migration instances (0->1, 1->2, 2->3).
/// Skipping versions is forbidden — if the gap matters, ship the
/// intermediate migrations.
///
/// Atomicity contract:
/// 1. [apply] writes the new artefact bytes to a sibling temp file,
///    fsyncs, then renames over the original. If [apply] throws,
///    the original file remains untouched.
/// 2. After [apply] succeeds, the runner calls [validate] to verify
///    the post-migration shape is readable. If validation fails the
///    runner restores the pre-migration file from the swapped-out
///    sibling (when the migration retains a backup) or surfaces an
///    error so the user is not left with silently corrupt state.
abstract class Migration {
  /// id of the artefact this migration acts on. Must match an
  /// [Artefact.id] registered in the registry.
  String get artefactId;

  /// Version of the artefact this migration expects to read.
  int get fromVersion;

  /// Version of the artefact this migration produces.
  int get toVersion;

  /// Run the conversion. Implementations must be atomic — any failure
  /// must leave the artefact at [fromVersion] on disk.
  Future<void> apply();

  /// Verify the post-migration state is well-formed (round-trip read,
  /// schema check, magic header check, …). Return false to trigger
  /// rollback in the runner. Default = noop (assumes apply already
  /// validated internally).
  Future<bool> validate() async => true;

  @override
  String toString() => '$runtimeType($artefactId: $fromVersion -> $toVersion)';
}
