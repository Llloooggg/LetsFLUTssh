/// One step in the migration chain for a single artefact.
///
/// Each Migration covers exactly one `(artefactId, fromVersion ->
/// toVersion)` transition. To go from version 1 to version 3 the
/// runner composes two Migration instances (1->2, 2->3). Skipping
/// versions is forbidden — if the gap matters, ship the intermediate
/// migrations.
///
/// Atomicity contract: [apply] is responsible for atomicity end-to-end.
/// The standard pattern is to write the new artefact bytes to a sibling
/// temp file, fsync, then `rename` over the original (this is what
/// [VersionedBlob.write] does for envelope artefacts). If [apply]
/// throws before the rename, the original file is untouched and the
/// runner records the failure as a fatal [MigrationReport] entry.
abstract class Migration {
  /// id of the artefact this migration acts on. Must match an
  /// [Artefact.id] registered in the registry.
  String get artefactId;

  /// Version of the artefact this migration expects to read.
  int get fromVersion;

  /// Version of the artefact this migration produces.
  int get toVersion;

  /// Run the conversion. Implementations must be atomic — any failure
  /// must leave the artefact at [fromVersion] on disk. Throw on any
  /// error; the runner catches and records it as fatal.
  Future<void> apply();

  @override
  String toString() => '$runtimeType($artefactId: $fromVersion -> $toVersion)';
}
