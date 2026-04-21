/// One step in the migration chain for a single artefact.
///
/// Each Migration covers exactly one (artefactId, fromVersion ->
/// toVersion) transition. To go from version 0 to version 3 the
/// runner composes three Migration instances (0->1, 1->2, 2->3).
/// Skipping versions is forbidden — if the gap matters, ship the
/// intermediate migrations.
///
/// Atomicity contract:
/// 1. [apply] is responsible for atomicity end-to-end. The standard
///    pattern is to write the new artefact bytes to a sibling temp
///    file, fsync, then `rename` over the original (this is what
///    [VersionedBlob.write] does for envelope artefacts). If [apply]
///    throws before the rename, the original file is untouched.
/// 2. After [apply] succeeds, the runner calls [validate] as a sanity
///    net (round-trip read, schema check, magic header check, ...).
///    Returning `false` flags the step as failed in the
///    [MigrationReport] but does not restore the previous file —
///    the runner has no backup to swap back. Migrations that need
///    post-validate rollback must hold their own `.bak` sibling and
///    perform the swap-back inside [apply] themselves.
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
  /// schema check, magic header check, …). Returning `false` flags the
  /// step as failed in the [MigrationReport] but does not roll the file
  /// back (see the atomicity contract above). Default = noop (assumes
  /// [apply] already validated internally).
  Future<bool> validate() async => true;

  @override
  String toString() => '$runtimeType($artefactId: $fromVersion -> $toVersion)';
}
