import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/port_forwards_dao.dart';
import '../../core/session/session.dart';
import '../../core/ssh/port_forward_rule.dart';
import '../../providers/session_provider.dart';
import '../../providers/tag_provider.dart';
import '../../src/rust/api/app.dart' as rust_app;
import '../../src/rust/api/db.dart' as rust_db;
import '../../utils/logger.dart';
import 'session_edit_dialog.dart';

/// Persist every payload [SaveResult] carries for a *new* session —
/// parent `sessions` row, transport-specific detail row
/// (`ssh_session_details` / `webdav_session_details` /
/// `s3_session_details`), port-forward rules, tag links. Single funnel
/// shared by every call site that opens [SessionEditDialog] so any
/// new payload field reaches every code path with one edit instead
/// of N parallel destructure lists drifting out of sync.
///
/// Invariant: the parent row writes BEFORE every detail / link
/// table — the FK constraints (`ON DELETE CASCADE` keyed by
/// `session_id`) need a real parent row before any child row can
/// land. `applySessionSaveResult` orders the calls accordingly.
///
/// `onConnect` runs after every write finishes when [SaveResult]'s
/// `connect` flag is set; passing `null` skips the connect step
/// (sidebar edit / move paths).
Future<void> applySessionSaveResult(
  WidgetRef ref,
  SaveResult result, {
  void Function(Session session)? onConnect,
}) async {
  final session = result.session;
  await ref.read(sessionMutatorProvider).add(session);
  await syncSessionDetailsFromSaveResult(ref, session.id, result);
  if (result.connect && onConnect != null) {
    onConnect(session);
  }
}

/// Run every detail-row + tag sync the dialog requested for an
/// already-persisted session. Use this from the *edit* path which
/// owns the parent-row write itself (`updatePartial`) and only
/// needs the side-channel sync. Tag sync errors are swallowed and
/// logged — they're best-effort and must not wedge a successful
/// session edit.
Future<void> syncSessionDetailsFromSaveResult(
  WidgetRef ref,
  String sessionId,
  SaveResult result,
) async {
  await syncForwards(sessionId, result.forwards);
  if (result.webdavData != null) {
    await syncWebDavDetails(sessionId, result.webdavData!);
  }
  if (result.s3Data != null) {
    await syncS3Details(sessionId, result.s3Data!);
  }
  if (result.pendingTagIds != null) {
    try {
      await _syncTagAssignments(ref, sessionId, result.pendingTagIds!);
    } catch (e, st) {
      AppLogger.instance.log(
        'Tag sync after save failed for <id>: $e',
        name: 'SessionEdit',
        error: e,
        stackTrace: st,
        level: LogLevel.warn,
      );
    }
  }
}

Future<void> syncForwards(
  String sessionId,
  List<PortForwardRule> nextRules,
) async {
  final existing = await loadPortForwards(sessionId);
  final keep = nextRules.map((r) => r.id).toSet();
  for (final old in existing) {
    if (!keep.contains(old.id)) {
      await deletePortForward(old.id);
    }
  }
  for (final r in nextRules) {
    await upsertPortForward(sessionId, r);
  }
}

Future<void> syncWebDavDetails(String sessionId, WebDavSaveData data) async {
  await rust_db.dbWebdavSessionDetailsUpsert(
    rec: rust_db.DbWebDavSessionDetails(
      sessionId: sessionId,
      baseUrl: data.baseUrl,
      username: data.username,
      authMethod: data.authMethod,
      trustedCertPem: data.trustedCertPem,
      insecureSkipVerify: data.insecureSkipVerify,
    ),
  );
  if (data.passwordDirty && data.password.isNotEmpty) {
    await rust_db.dbWebdavSessionDetailsSetPassword(
      sessionId: sessionId,
      password: data.password,
    );
    await rust_app.secretsPut(
      id: rust_db.dbWebdavSessionDetailsSecretId(sessionId: sessionId),
      bytes: utf8.encode(data.password),
    );
  }
}

Future<void> syncS3Details(String sessionId, S3SaveData data) async {
  await rust_db.dbS3SessionDetailsUpsert(
    rec: rust_db.DbS3SessionDetails(
      sessionId: sessionId,
      accessKeyId: data.accessKeyId,
      region: data.region,
      endpoint: data.endpoint,
      pathStyle: data.pathStyle,
      defaultBucket: data.defaultBucket,
      defaultPrefix: data.defaultPrefix,
      trustedCertPem: data.trustedCertPem,
      insecureSkipVerify: data.insecureSkipVerify,
    ),
  );
  if (data.passwordDirty && data.secretAccessKey.isNotEmpty) {
    await rust_db.dbS3SessionDetailsSetSecretAccessKey(
      sessionId: sessionId,
      secretAccessKey: data.secretAccessKey,
    );
    await rust_app.secretsPut(
      id: rust_db.dbS3SessionDetailsSecretId(sessionId: sessionId),
      bytes: utf8.encode(data.secretAccessKey),
    );
  }
}

Future<void> _syncTagAssignments(
  WidgetRef ref,
  String sessionId,
  Set<String> nextTagIds,
) async {
  final existing = await rust_db.dbTagsListForSession(sessionId: sessionId);
  final existingIds = {for (final t in existing) t.id};
  final toAdd = nextTagIds.difference(existingIds);
  final toRemove = existingIds.difference(nextTagIds);
  if (toAdd.isEmpty && toRemove.isEmpty) return;
  final notifier = ref.read(tagsProvider.notifier);
  for (final id in toAdd) {
    await notifier.tagSession(sessionId, id);
  }
  for (final id in toRemove) {
    await notifier.untagSession(sessionId, id);
  }
}
