import 'package:drift/drift.dart';

import 'dao/config_dao.dart';
import 'dao/connection_log_dao.dart';
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
    ConnectionLogs,
    Snippets,
    SessionSnippets,
    SftpBookmarks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  // DAOs — lazy-initialized, one per domain.
  late final sessionDao = SessionDao(this);
  late final folderDao = FolderDao(this);
  late final sshKeyDao = SshKeyDao(this);
  late final knownHostDao = KnownHostDao(this);
  late final configDao = ConfigDao(this);
  late final tagDao = TagDao(this);
  late final connectionLogDao = ConnectionLogDao(this);
  late final snippetDao = SnippetDao(this);
  late final sftpBookmarkDao = SftpBookmarkDao(this);
}
