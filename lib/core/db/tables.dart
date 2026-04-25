import 'package:drift/drift.dart';

// ---------------------------------------------------------------------------
// Core tables
// ---------------------------------------------------------------------------

/// Folder tree — self-referencing via [parentId].
///
/// Root folders have parentId = null. Nested folders reference their parent.
/// Replaces string paths like "Production/EU" with proper tree structure.
@DataClassName('DbFolder')
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId =>
      text().nullable().references(Folders, #id, onDelete: KeyAction.setNull)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get collapsed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// SSH sessions — main entity, references [Folders] and [SshKeys].
@DataClassName('DbSession')
class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get label => text().withDefault(const Constant(''))();
  TextColumn get folderId =>
      text().nullable().references(Folders, #id, onDelete: KeyAction.setNull)();

  // Server address
  TextColumn get host => text()();
  IntColumn get port => integer().withDefault(const Constant(22))();
  TextColumn get user => text()();

  // Authentication
  TextColumn get authType => text().withDefault(const Constant('password'))();
  TextColumn get password => text().withDefault(const Constant(''))();
  TextColumn get keyPath => text().withDefault(const Constant(''))();
  TextColumn get keyData => text().withDefault(const Constant(''))();
  TextColumn get keyId =>
      text().nullable().references(SshKeys, #id, onDelete: KeyAction.setNull)();
  TextColumn get passphrase => text().withDefault(const Constant(''))();

  // New fields (not in file-based model)
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get lastConnectedAt => dateTime().nullable()();

  /// Free-form JSON bag for feature flags that don't justify their own
  /// columns (recording toggle, layout hints, agent-forwarding state,
  /// future per-session preferences). Always a JSON object — empty
  /// `{}` by default. Structured fields (auth, port forwards, proxy
  /// jump) keep their own columns; this is the escape hatch.
  TextColumn get extras => text().withDefault(const Constant('{}'))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// SSH keys from the key manager.
@DataClassName('DbSshKey')
class SshKeys extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()();
  TextColumn get privateKey => text()();
  TextColumn get publicKey => text()();
  TextColumn get keyType => text()();
  BoolColumn get isGenerated => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// TOFU host key database — replaces known_hosts file.
@DataClassName('DbKnownHost')
class KnownHosts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get host => text()();
  IntColumn get port => integer().withDefault(const Constant(22))();
  TextColumn get keyType => text()();
  TextColumn get keyBase64 => text()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {host, port},
  ];
}

/// App configuration — single-row JSON blob.
///
/// Stored as JSON text to avoid DB migrations on config changes.
/// The DAO serializes/deserializes [AppConfig] to/from JSON.
@DataClassName('DbConfig')
class AppConfigs extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get data => text()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Idle-timeout in minutes for automatic re-locking. Lives in the
  /// encrypted DB instead of `config.json` because it is a security
  /// control — an attacker with disk access could otherwise disable
  /// auto-lock by editing a plaintext file. Default `0` means disabled.
  IntColumn get autoLockMinutes => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Feature tables (tags, connection log, snippets, SFTP bookmarks)
// ---------------------------------------------------------------------------

/// User-defined tags for organizing sessions and folders.
@DataClassName('DbTag')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get color => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// M2M: sessions ↔ tags.
@DataClassName('DbSessionTag')
class SessionTags extends Table {
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {sessionId, tagId};
}

/// M2M: folders ↔ tags.
@DataClassName('DbFolderTag')
class FolderTags extends Table {
  TextColumn get folderId =>
      text().references(Folders, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {folderId, tagId};
}

/// Reusable command snippets.
@DataClassName('DbSnippet')
class Snippets extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get command => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// M2M: sessions ↔ snippets (pin snippets to specific sessions).
@DataClassName('DbSessionSnippet')
class SessionSnippets extends Table {
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get snippetId =>
      text().references(Snippets, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {sessionId, snippetId};
}

/// SFTP path bookmarks — saved remote paths per session.
@DataClassName('DbSftpBookmark')
class SftpBookmarks extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get remotePath => text()();
  TextColumn get label => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
