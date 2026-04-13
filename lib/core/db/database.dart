import 'package:drift/drift.dart';

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
}
