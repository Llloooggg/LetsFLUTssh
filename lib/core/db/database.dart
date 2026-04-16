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

  /// Schema version. Bump this when adding/renaming columns or tables and
  /// extend [migration] with a `from{N-1}to{N}` step. Never skip a version.
  ///
  /// History:
  ///   1 — initial schema (first public release).
  ///   2 — `app_configs.auto_lock_minutes` column. Moves the auto-lock
  ///       timeout out of plaintext `config.json` into the encrypted DB
  ///       so an attacker with disk access cannot tamper with it.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(appConfigs, appConfigs.autoLockMinutes);
      }
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
