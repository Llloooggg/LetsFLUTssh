import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import '../security/credential_store.dart';
import 'session.dart';

/// CRUD + JSON persistence for sessions.
///
/// Session metadata is stored in plaintext JSON. Secrets (password, keyData,
/// passphrase) are stored in an AES-256-GCM encrypted file via [CredentialStore].
class SessionStore {
  static const _fileName = 'sessions.json';

  final List<Session> _sessions = [];
  final Set<String> _emptyGroups = {};
  final CredentialStore _credStore = CredentialStore();
  late final String _filePath;
  late final String _groupsFilePath;
  bool _initialized = false;

  List<Session> get sessions => List.unmodifiable(_sessions);
  Set<String> get emptyGroups => Set.unmodifiable(_emptyGroups);

  Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationSupportDirectory();
    _filePath = p.join(dir.path, _fileName);
    _groupsFilePath = p.join(dir.path, 'empty_groups.json');
    _initialized = true;
  }

  Future<List<Session>> load() async {
    await init();
    final file = File(_filePath);
    if (!await file.exists()) return _sessions;
    try {
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      _sessions
        ..clear()
        ..addAll(list.map((e) => Session.fromJson(e as Map<String, dynamic>)));

      await _mergeAndMigrateCredentials();
    } catch (e) {
      AppLogger.instance.log('Failed to load sessions, starting fresh', name: 'SessionStore', error: e);
    }

    // Load empty groups
    await _loadEmptyGroups();

    return _sessions;
  }

  /// Load credentials from encrypted store, merge into sessions,
  /// and migrate any legacy plaintext credentials.
  Future<void> _mergeAndMigrateCredentials() async {
    Map<String, CredentialData> allCreds;
    try {
      allCreds = await _credStore.loadAll();
    } on CredentialStoreException catch (e) {
      // Decryption failed — do NOT overwrite encrypted store.
      // Keep sessions without credentials rather than risk data loss.
      AppLogger.instance.log('Credential decryption failed, '
          'skipping merge to prevent data loss', name: 'SessionStore', error: e);
      return;
    }
    bool needsMigration = false;

    for (int i = 0; i < _sessions.length; i++) {
      final s = _sessions[i];
      final cred = allCreds[s.id];
      if (cred != null && !cred.isEmpty) {
        _sessions[i] = _mergeCredential(s, cred);
      } else if (_hasPlaintextCredentials(s)) {
        needsMigration = true;
      }
    }

    if (needsMigration) {
      await _migrateCredentials();
    }
  }

  /// Merge encrypted credential data into a session object.
  Session _mergeCredential(Session session, CredentialData cred) {
    return session.copyWith(
      auth: session.auth.copyWith(
        password: cred.password.isNotEmpty ? cred.password : session.password,
        keyData: cred.keyData.isNotEmpty ? cred.keyData : session.keyData,
        passphrase:
            cred.passphrase.isNotEmpty ? cred.passphrase : session.passphrase,
      ),
    );
  }

  /// Check if a session has credentials stored in plaintext.
  bool _hasPlaintextCredentials(Session s) {
    return s.password.isNotEmpty ||
        s.keyData.isNotEmpty ||
        s.passphrase.isNotEmpty;
  }

  /// Migrate plaintext credentials from sessions.json to encrypted store,
  /// then re-save sessions.json without secrets.
  Future<void> _migrateCredentials() async {
    Map<String, CredentialData> allCreds;
    try {
      allCreds = await _credStore.loadAll();
    } on CredentialStoreException {
      // Cannot load existing creds — start fresh map for migration.
      // This is safe: we only add plaintext creds that exist in sessions.json.
      allCreds = {};
    }
    for (final s in _sessions) {
      if (s.password.isNotEmpty || s.keyData.isNotEmpty || s.passphrase.isNotEmpty) {
        allCreds[s.id] = CredentialData(
          password: s.password,
          keyData: s.keyData,
          passphrase: s.passphrase,
        );
      }
    }
    await _credStore.saveAll(allCreds);
    // Re-save sessions.json without secrets (toJson() now excludes them).
    await _saveSessionFile();
  }

  /// Save session metadata (no secrets) to JSON file.
  Future<void> _saveSessionFile() async {
    await init();
    final content = const JsonEncoder.withIndent('  ')
        .convert(_sessions.map((s) => s.toJson()).toList());
    await writeFileAtomic(_filePath, content);
  }

  /// Save session metadata + credentials to their respective stores.
  ///
  /// Both saves are attempted together. If credential save fails,
  /// the session file is still persisted (credentials remain in memory
  /// and will be retried on next save).
  Future<void> _save() async {
    await _saveSessionFile();
    try {
      await _saveCredentials();
    } catch (e) {
      AppLogger.instance.log('Credential save failed, '
          'session file was saved — credentials will retry on next save',
          name: 'SessionStore', error: e);
    }
  }

  /// Save all credentials to encrypted store.
  Future<void> _saveCredentials() async {
    final allCreds = <String, CredentialData>{};
    for (final s in _sessions) {
      if (s.password.isNotEmpty || s.keyData.isNotEmpty || s.passphrase.isNotEmpty) {
        allCreds[s.id] = CredentialData(
          password: s.password,
          keyData: s.keyData,
          passphrase: s.passphrase,
        );
      }
    }
    await _credStore.saveAll(allCreds);
  }

  Future<void> _loadEmptyGroups() async {
    await init();
    final file = File(_groupsFilePath);
    if (!await file.exists()) return;
    try {
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      _emptyGroups
        ..clear()
        ..addAll(list.cast<String>());
    } catch (e) {
      AppLogger.instance.log('Failed to load empty groups', name: 'SessionStore', error: e);
    }
  }

  Future<void> _saveEmptyGroups() async {
    await init();
    await writeFileAtomic(_groupsFilePath, jsonEncode(_emptyGroups.toList()));
  }

  /// Add an empty group folder (persists even without sessions).
  Future<void> addEmptyGroup(String groupPath) async {
    if (groupPath.isEmpty) return;
    _emptyGroups.add(groupPath);
    await _saveEmptyGroups();
  }

  /// Remove an empty group (called when no longer needed).
  Future<void> removeEmptyGroup(String groupPath) async {
    _emptyGroups.remove(groupPath);
    await _saveEmptyGroups();
  }

  /// Rename a group and all its subgroups.
  /// Updates sessions and empty groups with the old path prefix.
  Future<void> renameGroup(String oldPath, String newPath) async {
    if (oldPath.isEmpty || newPath.isEmpty || oldPath == newPath) return;

    // Update sessions: exact match or subgroup (oldPath/...)
    for (int i = 0; i < _sessions.length; i++) {
      final s = _sessions[i];
      if (s.group == oldPath) {
        _sessions[i] = s.copyWith(group: newPath);
      } else if (s.group.startsWith('$oldPath/')) {
        _sessions[i] = s.copyWith(group: newPath + s.group.substring(oldPath.length));
      }
    }

    // Update empty groups
    final toRemove = <String>[];
    final toAdd = <String>[];
    for (final g in _emptyGroups) {
      if (g == oldPath) {
        toRemove.add(g);
        toAdd.add(newPath);
      } else if (g.startsWith('$oldPath/')) {
        toRemove.add(g);
        toAdd.add(newPath + g.substring(oldPath.length));
      }
    }
    _emptyGroups.removeAll(toRemove);
    _emptyGroups.addAll(toAdd);

    await Future.wait([_save(), _saveEmptyGroups()]);
  }

  /// Delete a group: remove all sessions and empty groups under this path.
  Future<void> deleteGroup(String groupPath) async {
    if (groupPath.isEmpty) return;

    // Delete sessions in this group and subgroups
    final toDelete = _sessions
        .where((s) => s.group == groupPath || s.group.startsWith('$groupPath/'))
        .map((s) => s.id)
        .toList();
    for (final id in toDelete) {
      _sessions.removeWhere((s) => s.id == id);
      await _credStore.delete(id);
    }

    // Remove empty groups under this path
    _emptyGroups.removeWhere(
      (g) => g == groupPath || g.startsWith('$groupPath/'),
    );

    await Future.wait([_save(), _saveEmptyGroups()]);
  }

  /// Delete all sessions and empty groups.
  Future<void> deleteAll() async {
    for (final s in _sessions) {
      await _credStore.delete(s.id);
    }
    _sessions.clear();
    _emptyGroups.clear();
    await Future.wait([_save(), _saveEmptyGroups()]);
  }

  /// Load credentials for the given session IDs.
  Future<Map<String, CredentialData>> loadCredentials(Set<String> sessionIds) async {
    if (sessionIds.isEmpty) return {};
    final all = await _credStore.loadAllSafe();
    return {
      for (final id in sessionIds)
        if (all.containsKey(id)) id: all[id]!,
    };
  }

  /// Replace sessions and empty groups with the given state and persist.
  /// Optionally restores credentials for sessions that were deleted.
  Future<void> restoreSnapshot(
    List<Session> sessions,
    Set<String> emptyGroups, [
    Map<String, CredentialData> credentials = const {},
  ]) async {
    _sessions
      ..clear()
      ..addAll(sessions);
    _emptyGroups
      ..clear()
      ..addAll(emptyGroups);
    await Future.wait([_save(), _saveEmptyGroups()]);
    if (credentials.isNotEmpty) {
      final all = await _credStore.loadAllSafe();
      all.addAll(credentials);
      await _credStore.saveAll(all);
    }
  }

  /// Count sessions in a group and its subgroups.
  int countSessionsInGroup(String groupPath) {
    return _sessions
        .where((s) => s.group == groupPath || s.group.startsWith('$groupPath/'))
        .length;
  }

  Future<void> add(Session session) async {
    final error = session.validate();
    if (error != null) throw ArgumentError(error);
    _sessions.add(session);
    await _save();
  }

  Future<void> update(Session session) async {
    final error = session.validate();
    if (error != null) throw ArgumentError(error);
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx < 0) throw ArgumentError('Session not found: ${session.id}');
    _sessions[idx] = session;
    await _save();
  }

  Future<void> delete(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    await _save();
    await _credStore.delete(id);
  }

  /// Delete multiple sessions by IDs in a single save.
  Future<void> deleteMultiple(Set<String> ids) async {
    if (ids.isEmpty) return;
    _sessions.removeWhere((s) => ids.contains(s.id));
    await _save();
    for (final id in ids) {
      await _credStore.delete(id);
    }
  }

  /// Move multiple sessions to a new group in a single save.
  Future<void> moveMultiple(Set<String> ids, String newGroup) async {
    if (ids.isEmpty) return;
    for (var i = 0; i < _sessions.length; i++) {
      if (ids.contains(_sessions[i].id)) {
        _sessions[i] = _sessions[i].copyWith(group: newGroup);
      }
    }
    await _save();
  }

  Session? get(String id) {
    try {
      return _sessions.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Duplicate a session with new ID and "(copy)" suffix.
  Future<Session> duplicateSession(String id) async {
    final original = get(id);
    if (original == null) throw ArgumentError('Session not found: $id');
    final copy = original.duplicate();
    await add(copy);
    return copy;
  }

  /// Move a session to a different group.
  Future<void> moveSession(String sessionId, String newGroup) async {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    _sessions[idx] = _sessions[idx].copyWith(group: newGroup);
    await _save();
  }

  /// Move a group (and all its sessions/subgroups) under a new parent.
  /// [groupPath] — current full path, [newParent] — new parent path ('' for root).
  Future<void> moveGroup(String groupPath, String newParent) async {
    if (groupPath.isEmpty) return;
    final folderName = groupPath.split('/').last;
    final newPath = newParent.isEmpty ? folderName : '$newParent/$folderName';
    if (newPath == groupPath) return;
    // Prevent moving into own subtree
    if (newPath.startsWith('$groupPath/')) return;

    await renameGroup(groupPath, newPath);
  }

  /// Unique group paths sorted alphabetically.
  List<String> groups() {
    final g = _sessions.map((s) => s.group).where((g) => g.isNotEmpty).toSet().toList();
    g.sort();
    return g;
  }

  /// Sessions in a specific group.
  List<Session> byGroup(String group) {
    return _sessions.where((s) => s.group == group).toList();
  }

  /// Search sessions by label, group, or host.
  List<Session> search(String query) => filterSessions(_sessions, query);

  /// Filter a session list by query. Static so providers can reuse
  /// the logic without depending on store instance state.
  static List<Session> filterSessions(List<Session> sessions, String query) {
    if (query.isEmpty) return sessions;
    final q = query.toLowerCase();
    return sessions.where((s) {
      return s.label.toLowerCase().contains(q) ||
          s.group.toLowerCase().contains(q) ||
          s.host.toLowerCase().contains(q) ||
          s.user.toLowerCase().contains(q);
    }).toList();
  }
}
