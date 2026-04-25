import 'package:drift/drift.dart';

import 'dao/config_dao.dart';
import 'dao/folder_dao.dart';
import 'dao/known_host_dao.dart';
import 'dao/port_forward_rule_dao.dart';
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
    PortForwardRules,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Schema version. v1 is the permanent floor — any on-disk DB that
  /// reports a version below 1 (pre-framework legacy) is treated as
  /// corrupt and routed through [DbCorruptDialog] + [WipeAllService].
  /// Forward bumps follow drift's normal `onUpgrade` flow with a
  /// `from{N-1}to{N}` branch per step; never skip a version.
  ///
  /// Version log:
  /// - v1: initial schema.
  /// - v2: `Sessions.extras TEXT NOT NULL DEFAULT '{}'` — free-form
  ///   JSON bag for feature flags that don't justify dedicated
  ///   columns (see `tables.dart` Sessions.extras for the rationale).
  /// - v3: `PortForwardRules` table — one row per SSH port-forward
  ///   attached to a session, opened by `PortForwardRuntime` on
  ///   connect via the `ConnectionExtension` hook.
  /// - v4: ProxyJump columns on `Sessions` — `via_session_id` (FK
  ///   into Sessions, ON DELETE SET NULL) plus `via_host` /
  ///   `via_port` / `via_user` for one-off override bastions.
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createPerformanceIndexes(this);
    },
    onUpgrade: (m, from, to) async {
      // Walk every step from `from` up to `to` so we never skip a
      // version. Each branch is responsible for one schema delta and
      // must be additive (DEFAULT-backed columns, new tables) — drift
      // cannot rewrite NOT NULL columns without a default in-place.
      if (from < 2) {
        await m.addColumn(sessions, sessions.extras);
      }
      if (from < 3) {
        await m.createTable(portForwardRules);
      }
      if (from < 4) {
        await m.addColumn(sessions, sessions.viaSessionId);
        await m.addColumn(sessions, sessions.viaHost);
        await m.addColumn(sessions, sessions.viaPort);
        await m.addColumn(sessions, sessions.viaUser);
      }
    },
    beforeOpen: (details) async {
      // Foreign keys are also set in database_opener; repeat here so drift's
      // own opener (used in tests that skip database_opener) honours them.
      await customStatement('PRAGMA foreign_keys = ON');
      // Performance indexes live outside `schemaVersion` — they are pure
      // query-plan speedups, idempotent via `IF NOT EXISTS`, and adding a
      // new one must never trip the "any other version = corrupt" guard
      // that routes existing v1 DBs through `WipeAllService`. Running them
      // on every open costs microseconds on cached sqlite_master.
      await _createPerformanceIndexes(this);
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
  late final portForwardRuleDao = PortForwardRuleDao(this);
}

/// Create performance-only indexes. Not part of the schema (no
/// [AppDatabase.schemaVersion] bump) — adding a row here is a pure
/// query-plan optimization. Statements are `CREATE INDEX IF NOT EXISTS`
/// so they are safe to re-run on every open and harmless on fresh DBs
/// just initialized by `createAll`.
///
/// Each entry backs a known hot query path:
/// - `sessions(folder_id)` — `SessionDao.getByFolder` runs on every
///   sidebar render and folder click; without it every read is a full
///   table scan against all sessions.
/// - `folders(parent_id)` — `FolderDao.getChildren` is called inside the
///   recursive `getDescendantIds` CTE; the index lets each recursion step
///   resolve children in O(log n) instead of O(n).
/// - `sftp_bookmarks(session_id)` — `SftpBookmarkDao.getForSession` runs
///   on every SFTP pane open for a session.
Future<void> _createPerformanceIndexes(AppDatabase db) async {
  const statements = <String>[
    'CREATE INDEX IF NOT EXISTS idx_sessions_folder_id '
        'ON sessions (folder_id)',
    'CREATE INDEX IF NOT EXISTS idx_folders_parent_id '
        'ON folders (parent_id)',
    'CREATE INDEX IF NOT EXISTS idx_sftp_bookmarks_session_id '
        'ON sftp_bookmarks (session_id)',
  ];
  for (final sql in statements) {
    await db.customStatement(sql);
  }
}
