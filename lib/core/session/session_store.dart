import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import '../security/aes_gcm.dart';
import '../security/security_level.dart';
import 'session.dart';

/// CRUD + persistence for sessions.
///
/// Supports three security levels:
/// - [SecurityLevel.plaintext]: `sessions.json` with credentials in cleartext.
/// - [SecurityLevel.keychain]: `sessions.enc` encrypted with OS keychain key.
/// - [SecurityLevel.masterPassword]: `sessions.enc` encrypted with PBKDF2 key.
///
/// On upgrade from old format (`credentials.enc` + `credentials.key`),
/// automatically migrates data to the new unified format.
class SessionStore {
  static const _jsonFileName = 'sessions.json';
  static const _encFileName = 'sessions.enc';

  final List<Session> _sessions = [];
  final Set<String> _emptyFolders = {};
  final Set<String> _collapsedFolders = {};

  SecurityLevel _level;
  Uint8List? _encryptionKey;

  /// [directory] is the base directory for session files; resolved lazily
  /// from [getApplicationSupportDirectory] when not provided.
  SessionStore({
    String? directory,
    SecurityLevel level = SecurityLevel.plaintext,
  }) : _directory = directory,
       _level = level;

  final String? _directory;
  String? _basePath;
  String? _groupsFilePath;
  String? _collapsedFoldersFilePath;

  List<Session> get sessions => List.unmodifiable(_sessions);
  Set<String> get emptyFolders => Set.unmodifiable(_emptyFolders);
  Set<String> get collapsedFolders => Set.unmodifiable(_collapsedFolders);

  /// Current security level.
  SecurityLevel get securityLevel => _level;

  /// Set the encryption key (from keychain or master password derivation).
  void setEncryptionKey(Uint8List key, SecurityLevel level) {
    _encryptionKey = key;
    _level = level;
  }

  /// Clear the encryption key (revert to plaintext).
  void clearEncryptionKey() {
    _encryptionKey = null;
    _level = SecurityLevel.plaintext;
  }

  /// Guards concurrent [load] calls — second caller awaits the first.
  Future<List<Session>>? _loadFuture;

  /// Ensure file paths are resolved. Safe to call multiple times.
  Future<void> init() async {
    if (_basePath != null) return;
    final dirPath = _directory ?? (await getApplicationSupportDirectory()).path;
    _basePath = dirPath;
    _groupsFilePath = p.join(dirPath, 'empty_groups.json');
    _collapsedFoldersFilePath = p.join(dirPath, 'collapsed_folders.json');
  }

  String get _base => _basePath!;
  String get _groupsPath => _groupsFilePath!;
  String get _collapsedPath => _collapsedFoldersFilePath!;

  Future<List<Session>> load() async {
    if (_loadFuture != null) return _loadFuture!;
    final future = _doLoad();
    _loadFuture = future;
    try {
      return await future;
    } finally {
      _loadFuture = null;
    }
  }

  Future<List<Session>> _doLoad() async {
    await init();

    // Check for old format and migrate if needed.
    await _migrateFromOldFormat();

    try {
      await _loadSessions();
    } catch (e) {
      AppLogger.instance.log(
        'Failed to load sessions — backing up corrupt file',
        name: 'SessionStore',
        error: e,
      );
      // Try to back up whichever file exists.
      final encFile = File('$_base/$_encFileName');
      final jsonFile = File('$_base/$_jsonFileName');
      if (await encFile.exists()) {
        await _backupCorruptFile(encFile);
      } else if (await jsonFile.exists()) {
        await _backupCorruptFile(jsonFile);
      }
    }

    await _loadEmptyFolders();
    await _loadCollapsedFolders();

    return _sessions;
  }

  /// Load sessions from the appropriate file based on security level.
  Future<void> _loadSessions() async {
    if (_encryptionKey != null) {
      // Encrypted mode (keychain or master password).
      final encFile = File('$_base/$_encFileName');
      if (!await encFile.exists()) return;
      final encData = await encFile.readAsBytes();
      final json = AesGcm.decrypt(encData, _encryptionKey!);
      _parseSessions(json);
    } else {
      // Plaintext mode.
      final jsonFile = File('$_base/$_jsonFileName');
      if (!await jsonFile.exists()) return;
      final json = await jsonFile.readAsString();
      _parseSessions(json);
    }
  }

  void _parseSessions(String json) {
    final list = jsonDecode(json) as List;
    _sessions
      ..clear()
      ..addAll(list.map((e) => Session.fromJson(e as Map<String, dynamic>)));
  }

  /// Save sessions to the appropriate file based on security level.
  Future<void> _save() async {
    await init();
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(_sessions.map((s) => s.toJsonWithCredentials()).toList());

    if (_encryptionKey != null) {
      final encData = AesGcm.encrypt(json, _encryptionKey!);
      await writeBytesAtomic('$_base/$_encFileName', encData);
    } else {
      await writeFileAtomic('$_base/$_jsonFileName', json);
    }
  }

  /// Re-encrypt all data with a new key and security level.
  ///
  /// Used when enabling/disabling/changing master password or switching
  /// between keychain and plaintext.
  Future<void> reEncrypt(Uint8List? newKey, SecurityLevel newLevel) async {
    await init();

    // Delete old files (both formats).
    final oldEnc = File('$_base/$_encFileName');
    final oldJson = File('$_base/$_jsonFileName');

    // Update key and level, then save in new format.
    _encryptionKey = newKey;
    _level = newLevel;
    await _save();

    // Clean up the opposite format file.
    if (newKey != null) {
      // Switched to encrypted — delete plaintext.
      if (await oldJson.exists()) await oldJson.delete();
    } else {
      // Switched to plaintext — delete encrypted.
      if (await oldEnc.exists()) await oldEnc.delete();
    }
  }

  // ── Migration from old format ────────────────────────────────────

  /// Migrate from old format (separate `credentials.enc` + `credentials.key`)
  /// to unified format.
  ///
  /// Detection: `credentials.enc` file exists alongside `sessions.json`.
  /// After migration, old files are deleted.
  Future<void> _migrateFromOldFormat() async {
    final oldCredFile = File('$_base/credentials.enc');
    final oldKeyFile = File('$_base/credentials.key');
    final oldSessionsFile = File('$_base/$_jsonFileName');

    // Only migrate when old credential files exist.
    if (!await oldCredFile.exists()) return;

    AppLogger.instance.log(
      'Detected old format — starting migration',
      name: 'SessionStore',
    );

    // Load old sessions from plaintext JSON.
    if (await oldSessionsFile.exists()) {
      try {
        final json = await oldSessionsFile.readAsString();
        _parseSessions(json);
      } catch (e) {
        AppLogger.instance.log(
          'Failed to parse old sessions.json during migration',
          name: 'SessionStore',
          error: e,
        );
      }
    }

    // Decrypt old credentials and merge into sessions.
    // The key comes from either the external key (master password) or the
    // old credentials.key file.
    Uint8List? credKey = _encryptionKey;
    if (credKey == null && await oldKeyFile.exists()) {
      final keyBytes = await oldKeyFile.readAsBytes();
      if (keyBytes.length == AesGcm.keyLength) {
        credKey = keyBytes;
      }
    }

    if (credKey != null) {
      try {
        final encData = await oldCredFile.readAsBytes();
        final credJson = AesGcm.decrypt(encData, credKey);
        final credMap = jsonDecode(credJson) as Map<String, dynamic>;
        _mergeOldCredentials(credMap);
      } catch (e) {
        AppLogger.instance.log(
          'Failed to decrypt old credentials during migration — '
          'sessions will load without secrets',
          name: 'SessionStore',
          error: e,
        );
      }
    }

    // Save in new format.
    await _save();

    // Delete old files.
    try {
      await oldCredFile.delete();
      if (await oldKeyFile.exists()) await oldKeyFile.delete();
      AppLogger.instance.log(
        'Migration complete — old files deleted',
        name: 'SessionStore',
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to delete old files after migration',
        name: 'SessionStore',
        error: e,
      );
    }
  }

  /// Merge old credential data into in-memory sessions.
  void _mergeOldCredentials(Map<String, dynamic> credMap) {
    for (int i = 0; i < _sessions.length; i++) {
      final s = _sessions[i];
      final cred = credMap[s.id] as Map<String, dynamic>?;
      if (cred == null) continue;
      final password = cred['password'] as String? ?? '';
      final keyData = cred['key_data'] as String? ?? '';
      final passphrase = cred['passphrase'] as String? ?? '';
      if (password.isEmpty && keyData.isEmpty && passphrase.isEmpty) continue;
      _sessions[i] = s.copyWith(
        auth: s.auth.copyWith(
          password: password.isNotEmpty ? password : s.password,
          keyData: keyData.isNotEmpty ? keyData : s.keyData,
          passphrase: passphrase.isNotEmpty ? passphrase : s.passphrase,
        ),
      );
    }
  }

  // ── Corrupt file backup ──────────────────────────────────────────

  Future<void> _backupCorruptFile(File file) async {
    try {
      final backupPath = '${file.path}.corrupt';
      await file.copy(backupPath);
      AppLogger.instance.log(
        'Corrupt file backed up to $backupPath',
        name: 'SessionStore',
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to back up corrupt file',
        name: 'SessionStore',
        error: e,
      );
    }
  }

  // ── Empty folders persistence ────────────────────────────────────

  Future<void> _loadEmptyFolders() async {
    await init();
    final file = File(_groupsPath);
    if (!await file.exists()) return;
    try {
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      _emptyFolders
        ..clear()
        ..addAll(list.cast<String>());
    } catch (e) {
      AppLogger.instance.log(
        'Failed to load empty folders',
        name: 'SessionStore',
        error: e,
      );
    }
  }

  Future<void> _saveEmptyFolders() async {
    await init();
    await writeFileAtomic(_groupsPath, jsonEncode(_emptyFolders.toList()));
  }

  Future<void> addEmptyFolder(String folderPath) async {
    if (folderPath.isEmpty) return;
    _emptyFolders.add(folderPath);
    AppLogger.instance.log(
      'Added empty folder: $folderPath',
      name: 'SessionStore',
    );
    await _saveEmptyFolders();
  }

  Future<void> removeEmptyFolder(String folderPath) async {
    _emptyFolders.remove(folderPath);
    AppLogger.instance.log(
      'Removed empty folder: $folderPath',
      name: 'SessionStore',
    );
    await _saveEmptyFolders();
  }

  // ── Collapsed folders persistence ────────────────────────────────

  Future<void> _loadCollapsedFolders() async {
    await init();
    final file = File(_collapsedPath);
    if (!await file.exists()) return;
    try {
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      _collapsedFolders
        ..clear()
        ..addAll(list.cast<String>());
    } catch (e) {
      AppLogger.instance.log(
        'Failed to load collapsed folders',
        name: 'SessionStore',
        error: e,
      );
    }
  }

  Future<void> _saveCollapsedFolders() async {
    await init();
    await writeFileAtomic(
      _collapsedPath,
      jsonEncode(_collapsedFolders.toList()),
    );
  }

  Future<void> toggleFolderCollapsed(String folderPath) async {
    final wasCollapsed = _collapsedFolders.contains(folderPath);
    if (wasCollapsed) {
      _collapsedFolders.remove(folderPath);
    } else {
      _collapsedFolders.add(folderPath);
    }
    AppLogger.instance.log(
      'Folder ${wasCollapsed ? 'expanded' : 'collapsed'}: $folderPath',
      name: 'SessionStore',
    );
    await _saveCollapsedFolders();
  }

  /// Count sessions in a folder and its subfolders.
  int countSessionsInFolder(String folderPath) {
    return _sessions
        .where(
          (s) => s.folder == folderPath || s.folder.startsWith('$folderPath/'),
        )
        .length;
  }

  // ── Folder operations ────────────────────────────────────────────

  Future<void> renameFolder(String oldPath, String newPath) async {
    if (oldPath.isEmpty || newPath.isEmpty || oldPath == newPath) return;

    for (int i = 0; i < _sessions.length; i++) {
      final s = _sessions[i];
      if (s.folder == oldPath) {
        _sessions[i] = s.copyWith(folder: newPath);
      } else if (s.folder.startsWith('$oldPath/')) {
        _sessions[i] = s.copyWith(
          folder: newPath + s.folder.substring(oldPath.length),
        );
      }
    }

    final toRemove = <String>[];
    final toAdd = <String>[];
    for (final g in _emptyFolders) {
      if (g == oldPath) {
        toRemove.add(g);
        toAdd.add(newPath);
      } else if (g.startsWith('$oldPath/')) {
        toRemove.add(g);
        toAdd.add(newPath + g.substring(oldPath.length));
      }
    }
    _emptyFolders.removeAll(toRemove);
    _emptyFolders.addAll(toAdd);

    final colToRemove = <String>[];
    final colToAdd = <String>[];
    for (final c in _collapsedFolders) {
      if (c == oldPath) {
        colToRemove.add(c);
        colToAdd.add(newPath);
      } else if (c.startsWith('$oldPath/')) {
        colToRemove.add(c);
        colToAdd.add(newPath + c.substring(oldPath.length));
      }
    }
    _collapsedFolders.removeAll(colToRemove);
    _collapsedFolders.addAll(colToAdd);

    await Future.wait([_save(), _saveEmptyFolders(), _saveCollapsedFolders()]);
  }

  Future<void> deleteFolder(String folderPath) async {
    if (folderPath.isEmpty) return;
    _sessions.removeWhere(
      (s) => s.folder == folderPath || s.folder.startsWith('$folderPath/'),
    );
    _emptyFolders.removeWhere(
      (g) => g == folderPath || g.startsWith('$folderPath/'),
    );
    _collapsedFolders.removeWhere(
      (c) => c == folderPath || c.startsWith('$folderPath/'),
    );
    await Future.wait([_save(), _saveEmptyFolders(), _saveCollapsedFolders()]);
  }

  Future<void> deleteAll() async {
    _sessions.clear();
    _emptyFolders.clear();
    _collapsedFolders.clear();
    await Future.wait([_save(), _saveEmptyFolders(), _saveCollapsedFolders()]);
  }

  // ── Snapshot / restore (for undo) ────────────────────────────────

  Future<void> restoreSnapshot(
    List<Session> sessions,
    Set<String> emptyFolders,
  ) async {
    _sessions
      ..clear()
      ..addAll(sessions);
    _emptyFolders
      ..clear()
      ..addAll(emptyFolders);
    await Future.wait([_save(), _saveEmptyFolders()]);
  }

  // ── CRUD ─────────────────────────────────────────────────────────

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
  }

  Future<void> deleteMultiple(Set<String> ids) async {
    if (ids.isEmpty) return;
    _sessions.removeWhere((s) => ids.contains(s.id));
    await _save();
  }

  Future<void> moveMultiple(Set<String> ids, String newFolder) async {
    if (ids.isEmpty) return;
    for (var i = 0; i < _sessions.length; i++) {
      if (ids.contains(_sessions[i].id)) {
        _sessions[i] = _sessions[i].copyWith(folder: newFolder);
      }
    }
    await _save();
  }

  Session? get(String id) {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<Session> duplicateSession(String id) async {
    final original = get(id);
    if (original == null) throw ArgumentError('Session not found: $id');
    final copy = original.duplicate();
    await add(copy);
    return copy;
  }

  Future<void> moveSession(String sessionId, String newFolder) async {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    _sessions[idx] = _sessions[idx].copyWith(folder: newFolder);
    await _save();
  }

  Future<void> moveFolder(String folderPath, String newParent) async {
    if (folderPath.isEmpty) return;
    final folderName = folderPath.split('/').last;
    final newPath = newParent.isEmpty ? folderName : '$newParent/$folderName';
    if (newPath == folderPath) return;
    if (newPath.startsWith('$folderPath/')) return;
    await renameFolder(folderPath, newPath);
  }

  // ── Query ────────────────────────────────────────────────────────

  List<String> folders() {
    final g = _sessions
        .map((s) => s.folder)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList();
    g.sort();
    return g;
  }

  List<Session> byFolder(String folder) {
    return _sessions.where((s) => s.folder == folder).toList();
  }

  List<Session> search(String query) => filterSessions(_sessions, query);

  static List<Session> filterSessions(List<Session> sessions, String query) {
    if (query.isEmpty) return sessions;
    final q = query.toLowerCase();
    return sessions.where((s) {
      return s.label.toLowerCase().contains(q) ||
          s.folder.toLowerCase().contains(q) ||
          s.host.toLowerCase().contains(q) ||
          s.user.toLowerCase().contains(q);
    }).toList();
  }
}
