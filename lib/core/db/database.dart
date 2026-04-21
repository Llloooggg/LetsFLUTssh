import 'package:drift/drift.dart';

import 'dao/config_dao.dart';
import 'dao/folder_dao.dart';
import 'dao/known_host_dao.dart';
import 'dao/session_dao.dart';
import 'dao/sftp_bookmark_dao.dart';
import 'dao/snippet_dao.dart';
import 'dao/ssh_key_dao.dart';
import 'dao/tag_dao.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Folders,
    Sessions,
    SshKeys,
    KnownHosts,
    AppConfigs,
    Tags,
    SessionTags,
    FolderTags,
    Snippets,
    SessionSnippets,
    SftpBookmarks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Schema version. v1 is the permanent floor — any on-disk DB that
  /// does not match this version (older or newer) is treated as corrupt
  /// and routed through [DbCorruptDialog] + [WipeAllService]. Bump this
  /// when adding/renaming columns or tables and append a `from{N-1}to{N}`
  /// step to [migration]; never skip a version.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    beforeOpen: (details) async {
      // Foreign keys are also set in database_opener; repeat here so drift's
      // own opener (used in tests that skip database_opener) honours them.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  // DAOs — lazy-initialized, one per domain.
  late final sessionDao = SessionDao(this);
  late final folderDao = FolderDao(this);
  late final sshKeyDao = SshKeyDao(this);
  late final knownHostDao = KnownHostDao(this);
  late final configDao = ConfigDao(this);
  late final tagDao = TagDao(this);
  late final snippetDao = SnippetDao(this);
  late final sftpBookmarkDao = SftpBookmarkDao(this);
}
