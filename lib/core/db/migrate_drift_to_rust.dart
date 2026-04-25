import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/db.dart' as rust_db;
import '../../utils/logger.dart';
import 'database.dart' as drift;

/// Marker file written under app-support after the v1 migration runs
/// cleanly. Presence = drift→rusqlite copy already happened, skip.
const _markerName = '.lfs_core_migration_v1.done';

/// Read every drift table and replay it through the Rust DAOs so
/// `lfs_core.db` ends up byte-for-byte equivalent to drift's
/// `letsflutssh.db`. Idempotent: a marker file under app-support
/// stops repeat runs; failures bail without writing the marker so
/// the next launch retries.
///
/// One-shot data backfill. Once every consumer reads from the FRB
/// DAOs and drift is removed, this helper retires alongside it.
///
/// Failures are logged at warn level and swallowed; the app keeps
/// running off whichever engine still works. The next boot retries.
/// We never crash the app because the mirror failed.
Future<void> migrateDriftToRustOnce(drift.AppDatabase db) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final marker = File(p.join(dir.path, _markerName));
    if (await marker.exists()) return;

    AppLogger.instance.log(
      'Starting drift → rusqlite mirror migration',
      name: 'RustDbMigration',
    );

    var folders = 0;
    for (final f in await db.folderDao.getAll()) {
      await rust_db.dbFoldersUpsert(
        row: rust_db.DbFolder(
          id: f.id,
          name: f.name,
          parentId: f.parentId,
          sortOrder: f.sortOrder,
          collapsed: f.collapsed,
          createdAtMs: f.createdAt.millisecondsSinceEpoch,
        ),
      );
      folders++;
    }

    var sshKeys = 0;
    for (final k in await db.sshKeyDao.getAll()) {
      await rust_db.dbSshKeysUpsert(
        row: rust_db.DbSshKey(
          id: k.id,
          label: k.label,
          privateKey: k.privateKey,
          publicKey: k.publicKey,
          keyType: k.keyType,
          isGenerated: k.isGenerated,
          createdAtMs: k.createdAt.millisecondsSinceEpoch,
        ),
      );
      sshKeys++;
    }

    var sessions = 0;
    for (final s in await db.sessionDao.getAll()) {
      await rust_db.dbSessionsUpsert(
        row: rust_db.DbSession(
          id: s.id,
          label: s.label,
          folderId: s.folderId,
          host: s.host,
          port: s.port,
          user: s.user,
          authType: s.authType,
          password: s.password,
          keyPath: s.keyPath,
          keyData: s.keyData,
          keyId: s.keyId,
          passphrase: s.passphrase,
          sortOrder: s.sortOrder,
          notes: s.notes,
          lastConnectedAtMs: s.lastConnectedAt?.millisecondsSinceEpoch,
          extras: s.extras,
          viaSessionId: s.viaSessionId,
          viaHost: s.viaHost,
          viaPort: s.viaPort,
          viaUser: s.viaUser,
          createdAtMs: s.createdAt.millisecondsSinceEpoch,
          updatedAtMs: s.updatedAt.millisecondsSinceEpoch,
        ),
      );
      sessions++;
    }

    var knownHosts = 0;
    for (final h in await db.knownHostDao.getAll()) {
      await rust_db.dbKnownHostsUpsertByHostPort(
        host: h.host,
        port: h.port,
        keyType: h.keyType,
        keyBase64: h.keyBase64,
        addedAtMs: h.addedAt.millisecondsSinceEpoch,
      );
      knownHosts++;
    }

    final config = await db.configDao.get();
    final autoLock = await db.configDao.getAutoLockMinutes();
    if (config != null || autoLock != 0) {
      await rust_db.dbAppConfigsUpsert(
        row: rust_db.DbAppConfig(
          data: config ?? '{}',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          autoLockMinutes: autoLock,
        ),
      );
    }

    var tags = 0;
    for (final t in await db.tagDao.getAll()) {
      await rust_db.dbTagsUpsert(
        row: rust_db.DbTag(
          id: t.id,
          name: t.name,
          color: t.color,
          createdAtMs: t.createdAt.millisecondsSinceEpoch,
        ),
      );
      tags++;
    }

    // M2M links — sessions ↔ tags, folders ↔ tags, sessions ↔ snippets.
    // Read each session's / folder's links and replay them.
    var sessionTags = 0;
    var folderTags = 0;
    for (final s in await db.sessionDao.getAll()) {
      final linked = await db.tagDao.getForSession(s.id);
      for (final t in linked) {
        await rust_db.dbSessionTagsLink(sessionId: s.id, tagId: t.id);
        sessionTags++;
      }
    }
    for (final f in await db.folderDao.getAll()) {
      final linked = await db.tagDao.getForFolder(f.id);
      for (final t in linked) {
        await rust_db.dbFolderTagsLink(folderId: f.id, tagId: t.id);
        folderTags++;
      }
    }

    var snippets = 0;
    for (final s in await db.snippetDao.getAll()) {
      await rust_db.dbSnippetsUpsert(
        row: rust_db.DbSnippet(
          id: s.id,
          title: s.title,
          command: s.command,
          description: s.description,
          createdAtMs: s.createdAt.millisecondsSinceEpoch,
          updatedAtMs: s.updatedAt.millisecondsSinceEpoch,
        ),
      );
      snippets++;
    }

    var sessionSnippets = 0;
    for (final s in await db.sessionDao.getAll()) {
      final linked = await db.snippetDao.getForSession(s.id);
      for (final sn in linked) {
        await rust_db.dbSessionSnippetsLink(sessionId: s.id, snippetId: sn.id);
        sessionSnippets++;
      }
    }

    var portForwards = 0;
    for (final s in await db.sessionDao.getAll()) {
      final rules = await db.portForwardRuleDao.getBySession(s.id);
      for (final r in rules) {
        await rust_db.dbPortForwardsUpsert(
          row: rust_db.DbPortForwardRule(
            id: r.id,
            sessionId: r.sessionId,
            kind: r.kind,
            bindHost: r.bindHost,
            bindPort: r.bindPort,
            remoteHost: r.remoteHost,
            remotePort: r.remotePort,
            description: r.description,
            enabled: r.enabled,
            sortOrder: r.sortOrder,
            createdAtMs: r.createdAt.millisecondsSinceEpoch,
          ),
        );
        portForwards++;
      }
    }

    var sftpBookmarks = 0;
    for (final s in await db.sessionDao.getAll()) {
      final marks = await db.sftpBookmarkDao.getForSession(s.id);
      for (final m in marks) {
        await rust_db.dbSftpBookmarksUpsert(
          row: rust_db.DbSftpBookmark(
            id: m.id,
            sessionId: m.sessionId,
            remotePath: m.remotePath,
            label: m.label,
            createdAtMs: m.createdAt.millisecondsSinceEpoch,
          ),
        );
        sftpBookmarks++;
      }
    }

    await marker.create(recursive: true);
    await marker.writeAsString(
      DateTime.now().toUtc().toIso8601String(),
      flush: true,
    );

    AppLogger.instance.log(
      'drift → rusqlite mirror complete: '
      'folders=$folders sshKeys=$sshKeys sessions=$sessions '
      'knownHosts=$knownHosts tags=$tags sessionTags=$sessionTags '
      'folderTags=$folderTags snippets=$snippets '
      'sessionSnippets=$sessionSnippets portForwards=$portForwards '
      'sftpBookmarks=$sftpBookmarks',
      name: 'RustDbMigration',
    );
  } catch (e, st) {
    AppLogger.instance.log(
      'drift → rusqlite mirror failed: ${e.runtimeType}',
      name: 'RustDbMigration',
      level: LogLevel.warn,
      error: e,
      stackTrace: st,
    );
  }
}
