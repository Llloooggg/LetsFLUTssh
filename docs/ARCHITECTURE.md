# LetsFLUTssh — Architecture & Technical Reference

## Table of Contents

- [1. High-Level Overview](#1-high-level-overview)
- [2. Module Map](#2-module-map)
- [3. Core Modules](#3-core-modules)
  - [3.1 SSH (`core/ssh/`)](#31-ssh-coressh)
  - [3.2 SFTP (`core/sftp/`)](#32-sftp-coresftp)
  - [3.3 Transfer Queue (`core/transfer/`)](#33-transfer-queue-coretransfer)
  - [3.4 Session Management (`core/session/`)](#34-session-management-coresession)
  - [3.5 Connection Lifecycle (`core/connection/`)](#35-connection-lifecycle-coreconnection)
  - [3.6 Security & Encryption (`core/security/`)](#36-security--encryption-coresecurity)
  - [3.7 Configuration (`core/config/`)](#37-configuration-coreconfig)
  - [3.8 Deep Links (`core/deeplink/`)](#38-deep-links-coredeeplink)
  - [3.9 Import (`core/import/`)](#39-import-coreimport)
  - [3.10 Update (`core/update/`)](#310-update-coreupdate)
  - [3.11 Keyboard Shortcuts (`core/shortcut_registry.dart`)](#311-keyboard-shortcuts-coreshortcut_registrydart)
- [4. State Management — Riverpod](#4-state-management--riverpod)
  - [4.1 Provider Dependency Graph](#41-provider-dependency-graph)
  - [4.2 Provider Catalog](#42-provider-catalog)
- [5. Feature Modules](#5-feature-modules)
  - [5.1 Terminal with Tiling (`features/terminal/`)](#51-terminal-with-tiling-featuresterminal)
  - [5.2 File Browser (`features/file_browser/`)](#52-file-browser-featuresfile_browser)
  - [5.3 Session Manager UI (`features/session_manager/`)](#53-session-manager-ui-featuressession_manager)
  - [5.4 Tab System (`features/tabs/`)](#54-tab-system-featurestabs)
  - [5.5 Settings (`features/settings/`)](#55-settings-featuressettings)
  - [5.6 Mobile (`features/mobile/`)](#56-mobile-featuresmobile)
- [6. Widgets — Public API Reference](#6-widgets--public-api-reference)
- [7. Utilities — Public API Reference](#7-utilities--public-api-reference)
- [8. Theme System](#8-theme-system)
- [9. Data Flow Diagrams](#9-data-flow-diagrams)
  - [9.1 SSH Connection Flow](#91-ssh-connection-flow)
  - [9.2 SFTP Init Flow](#92-sftp-init-flow)
  - [9.3 Session CRUD Flow](#93-session-crud-flow)
  - [9.4 File Transfer Flow](#94-file-transfer-flow)
- [10. Data Models](#10-data-models)
- [11. Persistence & Storage](#11-persistence--storage)
- [12. Platform-Specific Behavior](#12-platform-specific-behavior)
- [13. Security Model](#13-security-model)
- [14. Testing Patterns & DI Hooks](#14-testing-patterns--di-hooks)
- [15. CI/CD Pipeline](#15-cicd-pipeline)
  - [15.1 Workflow Graph](#151-workflow-graph)
  - [15.2 Workflow Catalog](#152-workflow-catalog)
  - [15.3 Makefile Targets](#153-makefile-targets)
- [16. Design Decisions & Rationale](#16-design-decisions--rationale)
  - [16.1 Architecture Choices](#161-architecture-choices)
  - [16.2 API Gotchas](#162-api-gotchas)
  - [16.3 Security Decisions](#163-security-decisions)
  - [16.4 Platform Decisions](#164-platform-decisions)
- [17. Dependencies](#17-dependencies)

---

## 1. High-Level Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        main.dart                            │
│          Entry point, MaterialApp, theme, routing           │
│    isMobilePlatform → MobileShell  /  else → MainScreen     │
└──────────────────────────┬──────────────────────────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                 ▼
┌─────────────┐  ┌─────────────────┐  ┌──────────────┐
│  features/  │  │   providers/    │  │   widgets/   │
│  (UI + UX)  │◄─┤   (Riverpod)    │  │  (reusable)  │
│             │  │  global state   │  │              │
└──────┬──────┘  └────────┬────────┘  └──────────────┘
       │                  │
       │         ┌────────┴────────┐
       │         ▼                 ▼
       │  ┌────────────┐   ┌───────────┐
       └─►│   core/    │   │  theme/   │
          │ (no UI)    │   │  utils/   │
          │ SSH, SFTP  │   └───────────┘
          │ sessions   │
          │ security   │
          │ config     │
          └────────────┘
```

**Principle:** `core/` does not import Flutter. `features/` accesses `core/` through `providers/`. `widgets/` are reusable UI components with no business logic.

---

## 2. Module Map

```
lib/
├── main.dart                         # Entry point
├── core/                             # Business logic (no Flutter imports)
│   ├── ssh/                          # SSH client, config, TOFU, errors
│   ├── sftp/                         # SFTP operations, file models, FileSystem
│   ├── transfer/                     # File transfer queue
│   ├── session/                      # Session model, persistence, tree, QR, history
│   ├── connection/                   # Connection lifecycle, progress tracking
│   ├── security/                     # AES-256-GCM credential storage + master password
│   ├── config/                       # App configuration
│   ├── deeplink/                     # Deep link handling
│   ├── import/                       # Data import (.lfs, key files)
│   ├── single_instance/              # Single-instance lock (desktop)
│   ├── update/                       # Update checking
│   └── shortcut_registry.dart        # Centralized keyboard shortcut definitions
├── features/                         # UI modules
│   ├── terminal/                     # Terminal with tiling
│   ├── file_browser/                 # Dual-pane SFTP browser
│   ├── session_manager/              # Session management panel
│   ├── tabs/                         # Tab model (TabEntry, TabKind)
│   ├── workspace/                    # Workspace tiling (panels, tab bars, drop zones)
│   ├── settings/                     # Settings + export/import
│   └── mobile/                       # Mobile version (bottom nav)
├── l10n/                             # Internationalization (15 languages: en, ru, zh, de, ja, pt, es, fr, ko, ar, fa, tr, vi, id, hi)
├── providers/                        # Riverpod providers (global state)
├── widgets/                          # Reusable UI components
│   ├── app_dialog.dart              # Unified dialog shell, header, footer, action buttons, progress dialog
│   ├── app_icon_button.dart         # Rectangular hover button (replaces Material IconButton)
│   ├── app_bordered_box.dart        # Bordered container with guaranteed radius
│   ├── app_divider.dart             # Standardized 1px divider
│   ├── app_shell.dart               # Desktop layout shell (toolbar, sidebar, body, status bar)
│   ├── clipped_row.dart             # Overflow-clipping Row replacement
│   ├── column_resize_handle.dart    # Draggable column-resize handle for table headers
│   ├── confirm_dialog.dart          # Confirmation dialog (delete, destructive actions)
│   ├── connection_progress.dart     # Terminal-styled progress for non-terminal tabs
│   ├── context_menu.dart            # Custom context menu with keyboard nav
│   ├── cross_marquee_controller.dart # Cross-widget marquee selection notifier
│   ├── error_state.dart             # Error display with retry/secondary actions
│   ├── host_key_dialog.dart         # TOFU dialogs (new host / key changed)
│   ├── passphrase_dialog.dart      # Interactive SSH key passphrase prompt
│   ├── unlock_dialog.dart          # Master password unlock dialog (startup)
│   ├── hover_region.dart            # MouseRegion + GestureDetector replacement
│   ├── lfs_import_dialog.dart       # .lfs import password + mode dialog
│   ├── marquee_mixin.dart           # Drag-select mixin for list/table widgets
│   ├── mobile_selection_bar.dart    # Mobile bulk-action toolbar
│   ├── mode_button.dart             # Shared pill-shaped toggle button (import mode)
│   ├── readonly_terminal_view.dart  # Read-only terminal display widget
│   ├── sortable_header_cell.dart    # Column header with sort indicator
│   ├── split_view.dart              # Horizontal resizable split
│   ├── status_indicator.dart        # Icon + count indicator with tooltip
│   ├── styled_form_field.dart       # Shared form field (StyledFormField, FieldLabel, StyledInput)
│   ├── threshold_draggable.dart     # Draggable with minimum distance threshold
│   └── toast.dart                   # Stacked notification toasts
├── theme/                            # OneDark / One Light palettes
└── utils/                            # Utilities: logger, format, platform
```

---

## 3. Core Modules

### 3.1 SSH (`core/ssh/`)

#### Files and responsibilities

| File | Class/Function | Purpose |
|------|---------------|---------|
| `ssh_client.dart` | `SSHConnection` | Wrapper over dartssh2: connect, auth, openShell, resize, keepalive, disconnect |
| `ssh_config.dart` | `SSHConfig` | Config model (host, port, user, password, keyPath, keyData, passphrase, keepAliveSec, timeoutSec) |
| `known_hosts.dart` | `KnownHostsManager` | TOFU: host key verification, fingerprint storage, callback on unknown/changed, CRUD management (remove/import/export/clear) |
| `shell_helper.dart` | `openShellWithRetry()`, `ShellConnection` | Shared SSH shell open logic with retry; `ShellConnection` wraps shell + terminal callbacks, clears them on `close()` |
| `errors.dart` | `ConnectError`, `AuthError`, `HostKeyError` | Typed SSH error hierarchy with structured fields (host, port, user) for localization |

#### SSHConnection — lifecycle

```dart
class SSHConnection {
  SSHConnection({
    required SSHConfig config,
    required KnownHostsManager knownHosts,
    SSHSocketFactory? socketFactory,   // DI hook for testing
    SSHClientFactory? clientFactory,   // DI hook for testing
  });

  Future<void> connect({ConnectionProgressCallback? onProgress});
  // 1. TCP socket (via socketFactory)
  // 2. SSH handshake (via clientFactory)
  // 3. Auth chain: keyFile → keyText → password → interactive
  // 4. Host key verification (via knownHosts)
  // 5. Keep-alive if keepAliveSec > 0

  Future<SSHSession> openShell({int cols, int rows});
  void resizeTerminal(int cols, int rows);
  void disconnect();

  SSHClient? get client;        // dartssh2 client
  bool get isConnected;

  PassphraseCallback? onPassphraseRequired;  // interactive passphrase prompt
  static const maxPassphraseAttempts = 3;
}
```

#### Auth chain — attempt order

```
1. keyPath → read file, resolve passphrase → SSHKeyPair
2. keyData → resolve passphrase, parse PEM → SSHKeyPair
3. password → SSHPasswordAuth
4. interactive → keyboard-interactive prompt (fallback)
Each step is skipped if the parameter is empty.
On failure of any step → AuthError.

Passphrase resolution (for encrypted keys):
  1. If config.passphrase is set → use it (stored or cached)
  2. Try SSHKeyPair.fromPem(pem, null) → if unencrypted, succeed
  3. If encrypted + no callback → AuthError
  4. Invoke onPassphraseRequired(host, attempt) up to 3 times
  5. User cancel (null) → AuthError; wrong passphrase → retry
  6. Correct passphrase → use it; cached via Connection.cachedPassphrase
```

#### KnownHostsManager

```dart
class KnownHostsManager {
  KnownHostsManager(String knownHostsPath);

  Future<void> load();  // safe to call concurrently — first call does I/O, subsequent await same future
  FutureOr<bool> verify(String host, int port, String type, Uint8List fingerprint);
  // → true: key matches / user accepted
  // → false: user rejected / key changed and rejected

  // Callbacks (invoked via global navigatorKey):
  // onUnknownHost → HostKeyDialog.showNewHost()
  // onHostKeyChanged → HostKeyDialog.showKeyChanged()

  // Public read access:
  Map<String, String> get entries;  // unmodifiable {hostPort → "keyType base64Key"}
  int get count;
  static String fingerprint(List<int> keyBytes);  // SHA256 fingerprint

  // CRUD operations (each persists to file via _saveAll):
  Future<void> removeHost(String hostPort);
  Future<void> removeMultiple(Set<String> hostPorts);
  Future<void> clearAll();
  Future<int> importFromFile(String path);  // merge from OpenSSH file, returns added count
  String exportToString();                  // serialize to OpenSSH format

  // Concurrency: _loadFuture pattern (first call loads, later calls reuse).
  // Write lock: _withWriteLock() serializes file writes via chained futures.
}
```

**Why global `navigatorKey`:** dartssh2 callback arrives from async context without BuildContext. Global key allows showing a dialog from anywhere.

---

### 3.2 SFTP (`core/sftp/`)

#### Files and responsibilities

| File | Class | Purpose |
|------|-------|---------|
| `sftp_client.dart` | `SFTPService` | Operations: list, stat, mkdir, remove, removeDir, upload, download, chmod |
| `sftp_models.dart` | `FileEntry` | File/directory model (name, path, size, mode, modTime, isDir, owner) |
| `file_system.dart` | `FileSystem`, `LocalFS`, `RemoteFS` | File system interface (local/remote abstraction) |

#### SFTPService API

```dart
class SFTPService {
  SFTPService(SftpClient client);

  Future<List<FileEntry>> list(String path);       // sorted: dirs first
  Future<FileEntry> stat(String path);
  Future<void> mkdir(String path);
  Future<void> remove(String path);                // files only
  Future<void> removeDir(String path);             // recursive, depth limit 100
  Future<void> chmod(String path, int mode);
  Future<void> downloadFile(String remote, String local, ProgressCallback? cb);
  Future<void> uploadFile(String local, String remote, ProgressCallback? cb);
  // upload: 64 KiB chunks via RandomAccessFile + try/finally
}
```

#### FileSystem interface

```dart
abstract class FileSystem {
  Future<List<FileEntry>> list(String path);
  Future<void> mkdir(String path);
  Future<void> delete(String path, {bool recursive = false});
  Future<void> rename(String oldPath, String newPath);
  Future<int> dirSize(String path);  // recursive size in bytes
  String get separator;
}

class LocalFS implements FileSystem { ... }   // dart:io
class RemoteFS implements FileSystem { ... }  // SFTPService wrapper, dirSize capped at 64 levels
```

**Why an interface:** Allows FilePaneController to work identically with local and remote panes. Simplifies testing — mocks can be substituted.

---

### 3.3 Transfer Queue (`core/transfer/`)

#### Files and responsibilities

| File | Class | Purpose |
|------|-------|---------|
| `transfer_manager.dart` | `TransferManager` | Task queue, parallel workers, history, cancellation |
| `transfer_task.dart` | `TransferTask`, `TransferDirection`, `HistoryEntry` | Task model, direction enum, history entry |

#### TransferManager — architecture

```
┌──────────────────────────────────────────┐
│             TransferManager              │
│                                          │
│  Queue: [task1, task2, task3, ...]       │
│  Workers: 2 (configurable)               │
│  Max history: 500 entries                │
│  Timeout: 30 min per task                │
│                                          │
│  States: queued → running → completed    │
│                          └→ failed       │
│                          └→ cancelled    │
│                                          │
│  Streams:                                │
│    onChange → UI updates                 │
│    onHistoryChange → history             │
└──────────────────────────────────────────┘
```

```dart
class TransferManager {
  TransferManager({int parallelism = 2, int maxHistory = 500, Duration taskTimeout = 30 min});

  String enqueue(TransferTask task);          // returns task ID
  void cancel(String taskId);
  void cancelAll();
  void clearHistory();

  Stream<void> get onChange;                  // broadcasts on any state change
  List<ActiveEntry> get activeEntries;        // running + queued tasks with progress
  List<HistoryEntry> get history;             // completed/failed/cancelled
  ({int running, int queued}) get status;
}
```

**Cancellation:** Marks the task as cancelled via `_cancelledIds` set; on the next progress callback invocation the flag is checked and CancelException is thrown. Timeout also adds to `_cancelledIds` for cooperative cancellation.

**Queue processing:** `_processQueue` returns void and fires tasks via `unawaited()` — errors are caught internally per-task.

#### TransferPanel — UI

The `TransferPanel` (`features/file_browser/transfer_panel.dart`) is a collapsible bottom panel unified with the file browser table pattern:

- **Resizable columns** — Local, Remote, Size, and Time columns have drag handles (shared `ColumnResizeHandle` widget, same as `FilePane`)
- **Column dividers** — Vertical 1px dividers between columns (same `_colDivider` as `FileRow`)
- **Sorting** — Click column headers to sort history entries. Default: Time descending. Enum: `TransferSortColumn` (name, local, remote, size, time)
- **Time column** — Replaces old Duration column. Shows `formatTimestamp` + `(formatDuration)` for completed entries. Tooltip shows created/started/ended/duration breakdown
- **Left-aligned sizes** — Size column uses default left alignment (no `textAlign: TextAlign.right`)

---

### 3.4 Session Management (`core/session/`)

#### Files and responsibilities

| File | Class | Purpose |
|------|-------|---------|
| `session.dart` | `Session`, `ServerAddress`, `SessionAuth`, `AuthType` | Session model with all fields |
| `session_store.dart` | `SessionStore` | CRUD, JSON persistence, search, folders, plaintext→encrypted migration |
| `session_tree.dart` | `SessionTree`, `TreeNode` | Hierarchical tree built from flat session list |
| `session_history.dart` | `SessionHistory` | Undo/redo snapshots (stores credentials separately) |
| `qr_codec.dart` | `QrCodec` | Session encoding/decoding for QR (no secrets, max ~2000 bytes) |

#### Session model

```dart
class Session {
  final String id;            // UUID
  final String label;         // display name
  final String folder;        // folder path: "Production/Web" (separator /)
  final ServerAddress server; // host, port, user
  final SessionAuth auth;     // authType, password, keyPath, keyData, passphrase
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool incomplete;      // true when imported via QR without credentials

  SSHConfig toSSHConfig();    // conversion for connection
  Session copyWith({...});    // preserves id, updates updatedAt
  Session duplicate();        // new id, "(copy)" suffix, preserves authType
  Map<String, dynamic> toJson();
  factory Session.fromJson(Map<String, dynamic> json);
}
```

#### SessionStore — persistence

```
sessions.json  ← metadata (label, folder, host, port, user, timestamps)
                  Does NOT contain passwords/keys
credentials.enc ← encrypted credentials (AES-256-GCM)
                  Keyed by session.id
```

```dart
class SessionStore {
  SessionStore(String dataDir, CredentialStore credentialStore);

  Future<void> load();           // reads both files, merges
  Future<void> save();           // atomic write of both

  void add(Session session);
  void update(Session session);
  void delete(String id);
  void bulkDelete(List<String> ids);
  List<Session> search(String query);  // by label, folder, host, user

  List<String> get folders;       // all unique folders
  List<String> get emptyFolders;  // folders without sessions
  void addEmptyFolder(String path);
  void renameFolder(String oldPath, String newPath);
  void deleteFolder(String path);
}
```

**Concurrent load guard:** `load()` uses a `_loadFuture` guard — if a load is already in progress, concurrent callers await the same future instead of starting a second load. Prevents race conditions where multiple lifecycle events (e.g., `onResume`/`onRestart`) clear and repopulate `_sessions` simultaneously, causing credential loss.

**Safety on load:** If CredentialStore fails to decrypt — skips credential merge and sets `_credentialsMerged = false`. Subsequent `_saveCredentials()` calls are skipped entirely to prevent overwriting valid encrypted data with empty in-memory credentials.

**Save order:** `_save()` writes credentials (encrypted) FIRST, then session metadata (JSON). This prevents a crash from leaving sessions.json ahead of credentials.enc. If credential save fails, session file is still persisted and credentials retry on next save.

#### SessionTree

```dart
class SessionTree {
  static List<SessionTreeNode> build(List<Session> sessions, List<String> emptyFolders);
  // Builds hierarchy: "Production/Web/nginx" → [Production] → [Web] → [nginx]
  // Empty folders are included in the tree
}

class SessionTreeNode {
  final String name;
  final String path;         // full path from root
  final Session? session;    // null for folders
  final List<SessionTreeNode> children;

  bool get isGroup => session == null;
  bool get isSession => session != null;
}
```

---

### 3.5 Connection Lifecycle (`core/connection/`)

#### Files and responsibilities

| File | Class | Purpose |
|------|-------|---------|
| `connection.dart` | `Connection` | Connection model (id, label, sshConnection, state, error, ready completer, progress stream) |
| `connection_step.dart` | `ConnectionStep` | Progress step model — phase (`socketConnect` / `hostKeyVerify` / `authenticate` / `openChannel`) × status (`inProgress` / `success` / `failed`) |
| `progress_tracker.dart` | `ProgressTracker` | Subscribes to `Connection.progressStream`, replays history for late subscribers, notifies listeners |
| `progress_writer.dart` | `ProgressWriter` | Writes ANSI-styled progress steps to an xterm `Terminal` (shared by desktop and mobile terminal views) |
| `connection_manager.dart` | `ConnectionManager` | Active connection management, creation, disconnection, stream |
| `foreground_service.dart` | `ForegroundServiceManager` | Android: foreground service for SSH keep-alive on screen lock |

#### Connection model

```dart
class Connection {
  final String id;           // UUID (tab-specific)
  final String label;
  SSHConfig sshConfig;       // mutable — refreshed from session store on reconnect
  final String? sessionId;   // links back to saved Session (null for quick-connect)
  final KnownHostsManager knownHosts;  // for host key verification
  SSHConnection? sshConnection;
  SSHConnectionState state;  // disconnected | connecting | connected
  Object? connectionError;
  String? cachedPassphrase;  // interactively entered, reused on reconnect

  Stream<ConnectionStep> progressStream;  // broadcasts steps during connect
  List<ConnectionStep> progressHistory;   // buffered for late subscribers

  Future<void> waitUntilReady();   // waits for connect attempt to finish (success or error)
  void completeReady();            // called by ConnectionManager — also closes progressStream
  void addProgressStep(step);      // buffers + broadcasts a progress step
  void resetForReconnect();        // closes old progress controller, then fresh completer + stream, clears history/error
}
```

**Deferred Init pattern:** Connection is created instantly in state=`connecting`. The actual SSH handshake runs in the background. UI immediately opens a tab and shows a connecting indicator.

#### ConnectionManager

```dart
class ConnectionManager {
  ConnectionManager({
    required KnownHostsManager knownHosts,
    SSHConnectionFactory? connectionFactory,
    ActiveCountCallback? onActiveCountChanged,  // notifies foreground service
  });

  PassphrasePromptCallback? onPassphraseRequired;  // set by UI layer (main.dart)

  Connection connectAsync(SSHConfig config, {String? label, String? sessionId});
  // Returns Connection immediately in state=connecting. SSH handshake runs in background.
  // _doConnect injects cachedPassphrase into config and wires onPassphraseRequired
  // onto the SSHConnection before connect(). If user checks "remember", the passphrase
  // is stored in Connection.cachedPassphrase for automatic reuse on reconnect.
  void disconnect(String connectionId);
  void disconnectAll();  // also completes pending ready futures for in-progress connections

  List<Connection> get connections;
  Stream<List<Connection>> get onChange;

  // Reconnect race prevention: per-connection generation counter (_connectGeneration).
  // _doConnect checks its generation is still current before applying results.
  // Rapid reconnects increment the counter, making in-flight results stale.
}
```

#### ForegroundServiceManager (Android only)

```dart
class ForegroundServiceManager {
  ForegroundServiceManager({
    @visibleForTesting ForegroundServiceBinding? binding,
  });
  // Android → real foreground service via binding
  // Other platforms → no-op internally

  void onConnectionCountChanged(int count);
  // count > 0 → starts foreground service with notification
  // count == 0 → stops service
}
```

**Why foreground service:** Android kills background processes. Without a foreground service, SSH connections drop on screen lock or app switch.

---

### 3.6 Security & Encryption (`core/security/`)

#### Three-Level Security Model

All data stores (SessionStore, KeyStore, KnownHostsManager) support three security levels:

| Level | When | Files on disk | Key source |
|-------|------|---------------|------------|
| **Plaintext** | No keychain AND no master password | `sessions.json`, `keys.json`, `known_hosts` | None |
| **Keychain** | OS keychain available, no master password | `sessions.enc`, `keys.enc`, `known_hosts.enc` | OS keychain via `flutter_secure_storage` |
| **Master Password** | User set master password | `sessions.enc`, `keys.enc`, `known_hosts.enc` + `credentials.salt` + `credentials.verify` | PBKDF2-derived |

First-launch wizard (`SecuritySetupDialog`) probes the OS keychain and offers the user a choice. First launch is detected by the absence of any data files (no master password salt, no keychain key, no session files).

#### AesGcm

Shared AES-256-GCM utility used by all encrypted stores.

```dart
class AesGcm {
  static Uint8List encrypt(String plaintext, Uint8List key);
  static String decrypt(Uint8List data, Uint8List key);
  static Uint8List generateKey(); // 32-byte random key
  // Wire format: [IV (12 bytes)] [ciphertext + GCM authentication tag]
}
```

**Why pointycastle:** `encrypt` package has version conflicts with dartssh2. pointycastle is pure Dart, transitive dependency via dartssh2.

#### SecureKeyStorage

Thin wrapper around `flutter_secure_storage` for OS keychain access. All methods catch exceptions and return null/false — graceful fallback to plaintext or master-password mode.

```dart
class SecureKeyStorage {
  Future<bool> isAvailable();      // write+read+delete probe
  Future<Uint8List?> readKey();    // null on failure
  Future<bool> writeKey(Uint8List key); // false on failure
  Future<void> deleteKey();
}
```

OS keychain backends: Keychain (macOS/iOS), Credential Manager (Windows), libsecret (Linux), EncryptedSharedPreferences (Android). All are **optional** — the app works without them.

#### KeyStore

Central SSH key store with three-level encryption.

```dart
class KeyStore {
  // Storage: keys.json (plaintext) or keys.enc (encrypted)
  void setEncryptionKey(Uint8List key, SecurityLevel level);
  void clearEncryptionKey();
  Future<void> reEncrypt(Uint8List? newKey, SecurityLevel newLevel);
  Future<Map<String, SshKeyEntry>> loadAll();
  Future<void> save(SshKeyEntry entry);
  Future<void> delete(String id);
  SshKeyEntry importKey(String pem, String label);
  static SshKeyEntry generateKeyPair(SshKeyType, label); // Ed25519 or RSA
}

class SshKeyEntry {
  final String id, label, privateKey, publicKey, keyType;
  final DateTime createdAt;
  final bool isGenerated;
}

enum SshKeyType { ed25519, rsa2048, rsa4096 }
```

**Session integration:** `SessionAuth.keyId` references a key by ID. Resolved in `SessionConnect._resolveConfig()` — key's PEM injected into `SSHConfig.auth.keyData` before connecting. SSH layer receives plain PEM text, unchanged.

---

### 3.7 Configuration (`core/config/`)

#### AppConfig model

```dart
class AppConfig {
  final TerminalConfig terminal;
  //   fontSize: 6-72 (default 14.0, type double)
  //   theme: 'dark'|'light'|'system'
  //   scrollback: ≥100 (default 5000)

  final SshDefaults ssh;
  //   keepAliveSec: default 30
  //   defaultPort: default 22
  //   sshTimeoutSec: default 10

  final UiConfig ui;
  //   windowWidth/Height
  //   uiScale: 0.5-2.0
  //   showFolderSizes: bool
  //   toastDurationMs: int (default 4000)

  final int transferWorkers;      // 1+ (default 2)
  final int maxHistory;           // ≥0 (default 500)
  final bool enableLogging;
  final bool checkUpdatesOnStart;
  final String? skippedVersion;
  final String? locale;             // null = OS auto-detect, or any of 15 supported locale codes

  // copyWith uses sentinel pattern for nullable fields:
  // copyWith(skippedVersion: null) clears, omitting preserves
  // copyWith(locale: null) clears, omitting preserves
}
```

#### ConfigStore

```dart
class ConfigStore {
  ConfigStore(String dataDir);

  Future<AppConfig> load();       // JSON → AppConfig + sanitize
  Future<void> save(AppConfig config);  // atomic write

  // Sanitize: clamps values to valid ranges
  // e.g.: fontSize < 6 → 6, fontSize > 72 → 72
}
```

---

### 3.8 Deep Links (`core/deeplink/`)

```dart
class DeepLinkHandler {
  // Scheme: letsflutssh://connect?host=X&user=Y&port=Z
  // Scheme: letsflutssh://import?d=BASE64URL (QR import)
  // .lfs files: app_links file open intent
  // .pem/.key files: file open intent

  // Validation:
  // - path traversal rejection (../)
  // - scheme whitelist
  // - host/port validation

  // Deduplication: time-limited (2 s) to cover the cold-start race
  // (getInitialLink + uriLinkStream). After the window, the same URI
  // is processed again (e.g. re-scanning the same QR from background).

  // Background safety: all callbacks in _MainScreenState use
  // addPostFrameCallback to defer UI-dependent work. Data-only
  // operations (QR session import) run immediately without context.

  void dispose(); // cancels subscription, nulls all callbacks
}
```

---

### 3.9 Import (`core/import/`)

| File | Purpose |
|------|---------|
| `import_service.dart` | Import .lfs archives (ZIP + AES-256-GCM, PBKDF2 600k iterations). `applyConfig` callback is typed `AppConfig` (not `dynamic`) |
| `key_file_helper.dart` | SSH key file parsing (PEM, OpenSSH formats) |

#### .lfs format

```
[salt 32B] [IV 12B] [encrypted payload + GCM tag 16B]

payload = ZIP archive:
  sessions.json    ← session metadata
  credentials.json ← credentials in plaintext (inside the encrypted zip)

Encryption: AES-256-GCM
Key: PBKDF2-SHA256(password, salt, 600000 iterations)
```

#### Import modes

| Mode | Behavior |
|------|----------|
| **Merge** | Adds new sessions, skips existing ones (by id) |
| **Replace** | Full replacement of all sessions from archive |

---

### 3.10 Update (`core/update/`)

```dart
class UpdateService {
  // Checks GitHub Releases API
  // Compares current version with latest release
  // User can skip a version (skippedVersion in config).
  // Stale skip auto-clears when a newer version supersedes the skipped one.
  //
  // DI: HttpFetcher, FileDownloader, ProcessRunner — all injectable for testing.
  // Download: follows redirects (max 10), validates trusted hosts.
  // openFile(): platform launcher, validates Windows paths against shell metacharacters.
  // Progress: throttled to 1% increments in UpdateNotifier to reduce state churn.
  //
  // Changelog: fetched once during check(), stored in UpdateInfo.changelog,
  // preserved across state transitions (downloading → downloaded) via copyWith.
  // Displayed in startup dialog (inline) and settings (via "Release Notes" button → AppDialog).
  // Available in both updateAvailable and downloaded states on all platforms.
}
```

### 3.11 Keyboard Shortcuts (`core/shortcut_registry.dart`)

Central registry for all app keyboard shortcuts. Every shortcut is an `AppShortcut` enum value with a default `SingleActivator` binding.

```dart
enum AppShortcut {
  newSession(SingleActivator(LogicalKeyboardKey.keyN, control: true)),
  terminalCopy(SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true)),
  // ... 29 shortcuts total (global, terminal, file browser, session panel, dialog)
  ;
  const AppShortcut(this.defaultBinding);
  final SingleActivator defaultBinding;
}

class AppShortcutRegistry {
  static final instance = AppShortcutRegistry._();

  SingleActivator binding(AppShortcut shortcut);

  // For CallbackShortcuts widgets:
  Map<ShortcutActivator, VoidCallback> buildCallbackMap(Map<AppShortcut, VoidCallback> actions);

  // For onKeyEvent handlers (e.g. inside xterm where CallbackShortcuts can't intercept):
  bool matches(AppShortcut shortcut, KeyEvent event);
}
```

**Usage patterns:**
- `CallbackShortcuts` widgets → `AppShortcutRegistry.instance.buildCallbackMap({...})`
- `onKeyEvent` handlers (xterm, file browser, session panel) → `reg.matches(AppShortcut.x, event)`
- Dialogs → `buildCallbackMap({AppShortcut.dismissDialog: ...})`

**Note:** `matches()` only checks ctrl/shift modifiers (not alt/meta) to tolerate phantom modifier flags on some platforms (e.g. WSLg).

---

## 4. State Management — Riverpod

### 4.1 Provider Dependency Graph

```
                    ┌─────────────────────┐
                    │   UI (features/)    │
                    └─────────┬───────────┘
                              │ watches
        ┌─────────────────────┼──────────────────────┐
        ▼                     ▼                      ▼
┌───────────────┐  ┌──────────────────┐  ┌────────────────────┐
│sessionProvider│  │  configProvider  │  │ workspaceProvider  │
│  (Notifier)   │  │   (Notifier)     │  │    (Notifier)      │
└───────┬───────┘  └────────┬─────────┘  └────────────────────┘
        │                   │
        ▼                   ▼
┌───────────────┐  ┌──────────────────┐
│sessionStore   │  │  configStore     │
│  Provider     │  │   Provider       │
└───────┬───────┘  └────────┬─────────┘
        │                   │
        ▼                   ▼
   SessionStore        ConfigStore          ← core/ (pure Dart)
   CredentialStore

┌─────────────────────────┐     ┌──────────────────────────┐
│connectionManagerProvider│     │ transferManagerProvider  │
│                         │     │                          │
│ → connectionsProvider   │     │ → activeTransfersProvider│
│   (StreamProvider)      │     │ → transferHistoryProvider│
│                         │     │ → transferStatusProvider │
└─────────────────────────┘     └──────────────────────────┘

┌─────────────────────┐     ┌────────────────────┐
│ sessionTreeProvider │     │ themeModeProvider  │
│ (computed from      │     │ (computed from     │
│  sessionProvider)   │     │  configProvider)   │
└─────────────────────┘     └────────────────────┘

┌──────────────────────────┐
│ filteredSessionsProvider │
│ (computed from           │
│  sessionProvider +       │
│  sessionSearchProvider)  │
└──────────────────────────┘
```

### 4.2 Provider Catalog

| Provider | Type | Depends on | Description |
|----------|------|-----------|-------------|
| `credentialStoreProvider` | Provider | — | Singleton CredentialStore (shared with SessionStore + master password flow) |
| `masterPasswordProvider` | Provider | — | MasterPasswordManager singleton |
| `sessionStoreProvider` | Provider | credentialStoreProvider | Singleton SessionStore |
| `sessionProvider` | NotifierProvider | sessionStoreProvider | Session CRUD + undo/redo |
| `sessionTreeProvider` | Provider | sessionProvider | Hierarchical tree |
| `filteredSessionsProvider` | Provider | sessionProvider, sessionSearchProvider | Filtered session list |
| `sessionSearchProvider` | NotifierProvider<SessionSearchNotifier, String> | — | Search query string |
| `configStoreProvider` | Provider | — | Singleton ConfigStore |
| `configProvider` | NotifierProvider | configStoreProvider | Configuration + sync logger (sequential save lock via `_pendingSave`) |
| `themeModeProvider` | Provider | configProvider | ThemeMode (dark/light/system) |
| `localeProvider` | Provider | configProvider | Locale? (null = system default) |
| `knownHostsProvider` | Provider | — | KnownHostsManager |
| `keyStoreProvider` | Provider | — | KeyStore |
| `sshKeysProvider` | FutureProvider | — | List\<SshKeyEntry\> |
| `connectionManagerProvider` | Provider | knownHostsProvider | ConnectionManager singleton |
| `connectionsProvider` | StreamProvider | connectionManagerProvider | Real-time connection list |
| `transferManagerProvider` | Provider | — | TransferManager singleton |
| `activeTransfersProvider` | StreamProvider | transferManagerProvider | Active/queued tasks |
| `transferHistoryProvider` | StreamProvider | transferManagerProvider | Completed transfer history |
| `transferStatusProvider` | StreamProvider<ActiveTransferState> | transferManagerProvider | Active tasks + progress state |
| `workspaceProvider` | NotifierProvider<WorkspaceNotifier, WorkspaceState> | connectionManagerProvider | Workspace tiling tree + tabs (defined in `features/workspace/workspace_controller.dart`) |
| `foregroundServiceProvider` | Provider | — | ForegroundServiceManager singleton |
| `filteredSessionTreeProvider` | Provider | sessionProvider, sessionSearchProvider | Filtered + hierarchical session tree |
| `updateProvider` | NotifierProvider<UpdateNotifier, UpdateState> | — | Update check state + actions |
| `appVersionProvider` | NotifierProvider<AppVersionNotifier, String> | — | Current version from package_info_plus |

**Data flow pattern:**
```
UI watches provider → Provider reads/watches other providers →
Notifier.state updated → all dependent providers recompute → UI rebuilds
```

---

## 5. Feature Modules

### 5.1 Terminal with Tiling (`features/terminal/`)

#### Files

| File | Class | Purpose |
|------|-------|---------|
| `terminal_tab.dart` | `TerminalTab` | Container: manages split tree, reconnect, shortcuts |
| `terminal_pane.dart` | `TerminalPane` | Single terminal: xterm widget + SSH shell pipe |
| `cursor_overlay.dart` | `CursorTextOverlay` | Paints inverted character on block cursor (xterm overlay) |
| `tiling_view.dart` | `TilingView` | Recursive split tree renderer |
| `split_node.dart` | `SplitNode`, `LeafNode`, `BranchNode` | Sealed class for split tree |

#### Split tree (tiling)

```dart
sealed class SplitNode {}

class LeafNode extends SplitNode {
  final String id;   // unique pane ID
}

class BranchNode extends SplitNode {
  final SplitDirection direction;  // horizontal | vertical
  final double ratio;              // 0.0-1.0, divider position
  final SplitNode first;
  final SplitNode second;
}
```

**Example:**

```
BranchNode(horizontal, 0.5)
├── LeafNode("pane-1")           ← left half
└── BranchNode(vertical, 0.5)   ← right half
    ├── LeafNode("pane-2")      ← top right
    └── LeafNode("pane-3")      ← bottom right
```

**Operations:**
- `replaceNode(oldId, newNode)` — split a pane (leaf → branch)
- `removeNode(id)` — remove a pane (branch → remaining child)
- `collectLeafIds()` — all pane IDs (for iteration)

#### TerminalPane — internals

```
TerminalPane(connection, paneId)
  ├── ProgressWriter subscribes to connection.progressStream
  │   └── writes ANSI-styled steps to terminal: [*] → [✓] / [✗]
  ├── await connection.waitUntilReady()
  ├── on success: clear terminal → ShellHelper.openShell()
  │   ├── xterm Terminal() ← pipe ← shell.stdout
  │   │                    → pipe → shell.stdin
  │   └── resize → connection.resizeTerminal(cols, rows)
  ├── on error: progress log stays visible with error text
  └── hardwareKeyboardOnly: true (on desktop)
```

**Connection progress:** Instead of a spinner, TerminalPane writes structured progress steps directly into the xterm buffer using ANSI color codes (yellow `[*]` for in-progress, green `[✓]` for success, red `[✗]` for failure). On successful connection the terminal clears and the shell appears; on failure the log stays visible. Cursor is hidden during progress display via `\x1B[?25l` and restored on clear/error.

**Why `hardwareKeyboardOnly: true` on desktop:** xterm TextInputClient is broken on Windows — causes input duplication.

**Focus indicator:** No border is drawn on panes — the 4 px divider in `TilingView` already separates them visually. The focused pane is identifiable by the active cursor and toolbar highlight.

**Context menu:** Right-click is handled by a `Listener(onPointerDown:)` wrapping `TerminalView`, not by xterm's `onSecondaryTapUp`. This ensures the context menu works even when the terminal is in mouse mode (htop, vim, etc.), because `Listener` operates at the raw pointer level before xterm's gesture detector can consume the event.

**Shift-bypass for mouse mode (desktop):** When a TUI app enables mouse mode (htop, vim, mc, etc.), all mouse events are forwarded to the app. Holding **Shift** temporarily suspends pointer-input forwarding via `TerminalController.setSuspendPointerInput(true)`, letting the user drag-select text locally — standard behaviour matching xterm, GNOME Terminal, and other emulators. State is updated via a `HardwareKeyboard` handler registered in `TerminalPaneState`; the handler fires on every key event and recalculates based on current Shift state + `Terminal.mouseMode`.

#### Keyboard Shortcuts

Terminal uses `Ctrl+Shift+` prefix to avoid conflicts with terminal escape sequences (Ctrl+C = SIGINT). Other panels use classic shortcuts since they don't contain a terminal.

**Global** (`main.dart` — `CallbackShortcuts`):

| Shortcut | Action |
|----------|--------|
| Ctrl+N | New session dialog |
| Ctrl+W | Close active tab |
| Ctrl+Tab / Ctrl+Shift+Tab | Next / previous tab |
| Ctrl+B | Toggle sidebar |
| Ctrl+\\ / Ctrl+Shift+\\ | Duplicate tab right / down (any tab type) |
| Ctrl+Shift+M | Toggle panel maximize (zoom) |
| Ctrl+, | Toggle settings |

**Terminal** (`terminal_pane.dart`):

| Shortcut | Action |
|----------|--------|
| Ctrl+Shift+C | Copy selection |
| Ctrl+Shift+V | Paste clipboard |
| Ctrl+Shift+F | Toggle search bar |
| Escape | Close search bar |

**SFTP file browser** (`file_pane.dart` — `Focus.onKeyEvent`):

| Shortcut | Action |
|----------|--------|
| Ctrl+A | Select all files |
| Ctrl+C | Copy selected entries to SFTP clipboard |
| Ctrl+V | Paste — transfer clipboard entries to this pane |
| F2 | Rename (single selection) |
| F5 | Refresh |
| Delete | Delete selected files |

SFTP clipboard is managed by `FileBrowserTab` — stores entries + source pane ID. Ctrl+C in local pane → Ctrl+V in remote pane = upload (and vice versa). Separate from session clipboard.

**Session panel** (`session_panel.dart` — `Focus.onKeyEvent`):

| Shortcut | Action |
|----------|--------|
| Ctrl+C | Copy focused session to session clipboard |
| Ctrl+V | Paste — duplicate copied session |
| Ctrl+Z / Ctrl+Y | Undo / redo session changes |
| F2 | Edit focused session |
| Delete | Delete focused session |

Session clipboard stores a session ID. Ctrl+V duplicates that session via `SessionNotifier.duplicate()`. Independent from SFTP clipboard.

---

### 5.2 File Browser (`features/file_browser/`)

#### Files

| File | Class | Purpose |
|------|-------|---------|
| `file_browser_tab.dart` | `FileBrowserTab` | Dual-pane container: local + remote |
| `file_pane.dart` | `FilePane` | Single pane: table + path bar + navigation |
| `file_pane_dialogs.dart` | — | Dialogs: New Folder, Rename, Delete |
| `file_row.dart` | `FileRow` | Row in the file table |
| `breadcrumb_path.dart` | `BreadcrumbPath`, `parseBreadcrumbPath()`, `buildPathForSegment()` | Shared breadcrumb path parsing for desktop and mobile file browsers |
| `file_browser_controller.dart` | `FilePaneController` | Pane state: listing, navigation, selection, sort |
| `sftp_browser_mixin.dart` | `SftpBrowserMixin` | Shared mixin: SFTP init, upload, download — used by `FileBrowserTab` and `MobileFileBrowser` |
| `sftp_initializer.dart` | `SFTPInitializer` | SFTP initialization factory (injectable) |
| `transfer_panel.dart` | `TransferPanel` | Bottom panel: progress + history (resizable columns, sorting, column dividers) |
| `transfer_helpers.dart` | `TransferHelpers` | Upload/download helpers; `enqueueUpload`/`enqueueDownload` accept `required S loc` for localized status strings |

#### FilePaneController

```dart
class FilePaneController extends ChangeNotifier {
  FilePaneController(FileSystem fs, String initialPath);

  // Navigation
  Future<void> navigateTo(String path);
  void goBack();
  void goForward();
  void goUp();
  String get currentPath;

  // File listing
  List<FileEntry> get entries;        // current contents
  bool get isLoading;

  // Sorting
  SortColumn get sortColumn;          // name, size, mode, modified, owner
  SortOrder get sortOrder;            // asc, desc
  void sort(SortColumn column);

  // Selection
  Set<int> get selectedIndices;
  void select(int index, {bool ctrl, bool shift});
  void selectAll();
  void clearSelection();

  // Folder sizes
  Future<void> calculateFolderSizes(); // async, max 2 concurrent
}
```

**Why `ChangeNotifier` instead of Riverpod:** Lightweight per-pane state. Each pane creates its own controller. Riverpod adds overhead not justified for such local state.

#### Desktop vs Mobile file browser

| Aspect | Desktop | Mobile |
|--------|---------|--------|
| Layout | Dual-pane (local + remote) | Single-pane (toggle local/remote) |
| Selection | Marquee + click + Ctrl/Shift | Long-press → bulk mode |
| Drag & drop | Between panes + from OS | None |
| Navigation | Click + path bar | Tap + swipe |

---

### 5.3 Session Manager UI (`features/session_manager/`)

#### Files

| File | Class | Purpose |
|------|-------|---------|
| `session_panel.dart` | `SessionPanel` | Sidebar: tree view + search + actions + bulk select. Header has "New Folder" and "New Connection" buttons |
| `session_tree_view.dart` | `SessionTreeView` | Hierarchical list with drag & drop. Uses `FolderDrag` for folder drag data. Session icon color: green (connected), yellow (connecting), grey (disconnected) |
| `session_edit_dialog.dart` | `SessionEditDialog` | Create/edit session form. Auth tab: password, key file/PEM, or key from central store (via `keyId`). Key store selector shown when keys exist |
| `session_connect.dart` | `SessionConnect` | Connection logic: Session → resolve keyId → SSHConfig → ConnectionManager. Async to support key store lookup |
| `quick_connect_dialog.dart` | `QuickConnectDialog` | Quick connect without saving |
| `qr_display_screen.dart` | `QrDisplayScreen` | QR code display for session sharing (scan or copy link) |
| `qr_export_dialog.dart` | `QrExportDialog` | Session selection for QR export |

#### SessionConnect — flow

```dart
class SessionConnect {
  // Terminal:
  static Future<void> connectTerminal(Session session, WidgetRef ref) {
    // 1. Session → SSHConfig (with credentials from CredentialStore)
    // 2. connectionManager.connectAsync(config)
    // 3. workspaceProvider.addTerminalTab(connection)
  }

  // SFTP:
  static Future<void> connectSftp(Session session, WidgetRef ref) {
    // 1-2. Same as above
    // 3. workspaceProvider.addSftpTab(connection)
  }
}
```

---

### 5.4 Tab & Workspace System

#### Tab Model (`features/tabs/`)

| File | Class | Purpose |
|------|-------|---------|
| `tab_model.dart` | `TabEntry`, `TabKind` | Tab model (id, label, connection, kind) |
| `welcome_screen.dart` | `WelcomeScreen` | Minimal empty state — icon, heading, subtitle; no buttons or shortcuts |

```dart
class TabEntry {
  final String id;          // UUID
  final String label;
  final Connection connection;
  final TabKind kind;       // terminal | sftp

  TabEntry copyWith({String? label});  // same id
  TabEntry duplicate();                // new UUID, same connection/label/kind
}
```

#### Workspace Tiling (`features/workspace/`)

| File | Class | Purpose |
|------|-------|---------|
| `workspace_node.dart` | `WorkspaceNode`, `PanelLeaf`, `WorkspaceBranch` | Sealed split tree for screen-level tiling |
| `workspace_controller.dart` | `WorkspaceNotifier`, `WorkspaceState` | State management: add/close/move/split/copy/select tabs across panels |
| `workspace_view.dart` | `WorkspaceView`, `WorkspaceViewState` | Recursive renderer: panels with dividers, tab bars, connection bars |
| `panel_tab_bar.dart` | `PanelTabBar`, `TabDragData` | Per-panel tab bar with cross-panel drag-and-drop |
| `drop_zone_overlay.dart` | `PanelDropTarget`, `DropZone`, `buildDropZoneOverlay()` | Snap/dock zones for tab dragging; shared overlay builder used by both panel and workspace edge targets |

#### Two-level tiling architecture

```
WorkspaceNode (screen-level — splits panels on screen)
  ├── WorkspaceBranch (direction + ratio)
  │     ├── PanelLeaf (tab stack A — own tab bar, own IndexedStack)
  │     └── PanelLeaf (tab stack B — own tab bar, own IndexedStack)
  └── ...recursive...

PanelLeaf → TabEntry → TerminalTab → SplitNode (internal pane tiling — unchanged)
```

**Screen-level split:** `WorkspaceNode` tree divides the screen into panels. Each `PanelLeaf` holds its own `List<TabEntry>` with an active index and renders its own `PanelTabBar` + `IndexedStack`.

**Terminal-level split:** `SplitNode` tree inside each `TerminalTab` divides a single terminal tab into panes. These two tiling levels are independent.

**Duplicate Right / Duplicate Down:** Toolbar buttons and Ctrl+\\ / Ctrl+Shift+\\ duplicate the active tab (any type) into a new adjacent panel via `WorkspaceNotifier.copyToNewPanel()`. The duplicate reuses the same `Connection` object (no new SSH connection), getting its own shell/SFTP channel.

**Panel maximize (zoom):** `WorkspaceState.maximizedPanelId` temporarily renders a single panel full-screen while preserving the workspace tree. Toggle via Ctrl+Shift+M, the connection bar button, or the tab context menu. Maximize is cleared automatically when the maximized panel is closed or the tree collapses to a single panel. Edge drop zones are disabled while maximized.

**Drag-and-drop:** Tabs can be dragged between panels. Dropping on a panel's tab bar inserts the tab. Dropping on a panel's content area shows drop zone overlays (center = add to panel, edges = split panel in that direction).

**IndexedStack:** Each panel uses its own `IndexedStack` — all tabs in a panel stay in memory, only the current one is visible. This preserves terminal state when switching tabs.

**GlobalKey for cross-panel moves:** Both `TerminalTab` and `FileBrowserTab` use `GlobalKey` (managed by `WorkspaceViewState._terminalKeys` / `_fileBrowserKeys`). When a tab is dragged to a new panel, `GlobalKey` lets Flutter reparent the widget state instead of destroying and recreating it. Without this, SFTP tabs would re-run `_initSftp()` and show connection progress on every tiling split.

**Tab styling:** Active tab has `AppTheme.bg2` background with a 2 px `AppTheme.accent` top bar. Inactive tabs have `AppTheme.bg1` background. Icons are colored by kind (blue = terminal, yellow = SFTP) when active, `AppTheme.fgFaint` when inactive. Height: `AppTheme.barHeightSm` (34 px).

**Connection lifecycle:** When all tabs referencing a connection are closed across **all** panels, `WorkspaceNotifier` automatically disconnects the orphaned connection via `ConnectionManager.disconnect()`.

**Panel collapse:** When the last tab in a panel is closed (or moved out), the panel is removed from the workspace tree and its sibling is promoted up.

---

### 5.5 Settings (`features/settings/`)

| File | Class | Purpose |
|------|-------|---------|
| `settings_screen.dart` | `SettingsScreen` | Mobile-only route (collapsible sections in a scrollable list) |
| `settings_screen.dart` | `SettingsSidebar` | Desktop nav panel — embedded in `AppShell`'s sidebar slot |
| `settings_screen.dart` | `SettingsContent` | Desktop content pane — embedded in `AppShell`'s body slot |
| `settings_dialogs.dart` | — | Dialog helpers (part of `settings_screen.dart`) |
| `settings_logging.dart` | — | Logging section widgets (part of `settings_screen.dart`) |
| `settings_widgets.dart` | — | Shared settings tiles/controls (part of `settings_screen.dart`) |
| `settings_sections.dart` | — | Section-specific build methods (part of `settings_screen.dart`) |
| `known_hosts_manager.dart` | `KnownHostsManagerDialog` | Known hosts management dialog (search, delete, import, export, clear) |
| `key_manager/key_manager_dialog.dart` | `KeyManagerDialog` | SSH key management dialog (list, generate, import, delete, copy public key) |
| `export_import.dart` | — | Export/import .lfs archives (UI + logic) |

**Sections:** Appearance (language picker, theme, UI scale, font size), Terminal, Connection, Transfers, Security (known hosts manager), SSH Keys (key manager), Data (export/import, QR, path), Logging, Updates, About. Language picker uses `PopupMenuButton` with native language names + English secondary labels. Theme selector labels (Dark/Light/System) are localized via `S.of(context)`.

**Desktop:** Settings are embedded directly in `MainScreen` via `ShellMode`. The toolbar settings button toggles between `ShellMode.sessions` and `ShellMode.settings` — no route navigation. `SettingsSidebar` + `SettingsContent` replace the session panel and tab area while sharing the same `AppShell` frame (sidebar width preserved).

**Mobile:** `SettingsScreen` is pushed as a route with collapsible `ExpansionTile` sections.

---

### 5.6 Mobile (`features/mobile/`)

| File | Class | Purpose |
|------|-------|---------|
| `mobile_shell.dart` | `MobileShell` | Bottom navigation: Sessions / Terminal / SFTP |
| `mobile_terminal_view.dart` | `MobileTerminalView` | Full-screen terminal + keyboard bar |
| `mobile_file_browser.dart` | `MobileFileBrowser` | Single-pane SFTP (toggle local/remote) |
| `ssh_keyboard_bar.dart` | `SshKeyboardBar` | Quick access panel: Ctrl, Alt, arrows, Fn, Paste, Select. Main row is horizontally scrollable (`ListView`); Paste + Select + Fn buttons are fixed at right edge |
| `ssh_key_sequences.dart` | — | Escape sequences for keys |

**Text selection (mobile):** The Select button (📋 icon, fixed at right edge of keyboard bar) toggles text-select mode. When active, `TerminalController.setSuspendPointerInput(true)` prevents mouse events from reaching the TUI app, so the user can drag-select text for copying. Long-press word selection (built into xterm's `TerminalGestureHandler`) works independently of select mode. When text is selected (via either method), a floating **selection toolbar** with Copy/Paste buttons appears between the terminal and the keyboard bar. Copying auto-exits select mode (`exitSelectMode()`). A dedicated **Paste button** in the keyboard bar provides always-available paste access. Note: the outer `GestureDetector` does NOT handle `onLongPressStart` — xterm handles long-press internally for word selection, and the `TerminalController` (a `ChangeNotifier`) listener detects selection changes to show/hide the toolbar.

**Architectural difference:** Mobile is NOT a responsive version of desktop. It's a separate `features/mobile/` module with different interaction patterns (bottom nav instead of sidebar+tabs, long-press instead of right-click, swipe navigation).

**Mobile session panel interactions:**
- **Single tap** on session → connects immediately (no double-tap needed)
- **Long-press** on session → bottom sheet context menu: Terminal, Files, Edit, Duplicate, Move, Delete, **Select**
- **Long-press** on folder → bottom sheet: New Connection, New Folder, Rename, Delete, **Select**
- **Select** action in bottom sheet → enters multi-select mode with that item pre-checked. Further taps toggle items. Bulk actions (Select All, Move, Delete, Cancel) in `_SelectActionBar` (height: 36 px, matching `_PanelHeader`). No checklist icon in header — multi-select is entered exclusively through the bottom sheet.

**Nav guard:** Terminal and Files destinations are disabled (dimmed, tap blocked) when no tabs of that type exist. If the user is on Terminal/Files and the last tab closes, auto-switches to Sessions.

**Shared styling with desktop:** Mobile tab chips match desktop's rectangular tab style (top accent bar, colored icons — blue for terminal, yellow for SFTP, connection status dot). SSH↔SFTP companion buttons (`_MobileCompanionButton`) mirror desktop's `_companionButton` styling (colored background, border, icon + label). Saved-sessions, active-connections, and open-tabs counts use `StatusIndicator` icons in the global header bar (matching desktop's sidebar footer style), not duplicated in the session panel footer. Bottom nav items are plain icons without badges — the total tab count lives in the header bar. The tab chip bar and companion button share a parent `Container` with `AppTheme.bg1` background (no border), ensuring consistent background across both elements.

```dart
// main.dart
if (isMobilePlatform) {
  return const MobileShell();    // bottom nav, one tab
} else {
  return const MainScreen();     // sidebar + tab bar
}
```

---

## 6. Widgets — Public API Reference

### AppShell

```dart
AppShell({
  required Widget toolbar,        // content inside the decorated toolbar container
  double toolbarHeight = 34,      // toolbar container height
  Widget? sidebar,                // left panel content (null → no sidebar)
  double initialSidebarWidth = 220,
  double minSidebarWidth = 140,
  double maxSidebarWidth = 400,
  bool sidebarOpen = true,        // inline visibility toggle
  bool useDrawer = false,         // true → sidebar becomes a Drawer (narrow viewports)
  double drawerWidth = 280,
  required Widget body,           // main content between toolbar and status bar
  Widget? statusBar,              // optional bottom bar
})
```
Desktop layout shell shared by the main screen and settings. Provides the consistent visual frame: toolbar (surfaceContainerLow, no border), main body area, and optional status bar. Sidebar resize uses a `Stack` overlay — panels sit flush, a 6 px invisible hit zone with a 1 px `dividerColor` line overlays the boundary. On narrow viewports, set `useDrawer: true` to render the sidebar as a pull-out `Drawer` instead of an inline panel.

**Toolbar layout:** `[sidebar toggle | AppTabBar (embedded) | copy right / copy down | settings]`. Tabs are embedded directly in the toolbar row via `AppTabBar(embedded: true)` to save vertical space. When no tabs are open or in settings mode, the tab area is replaced by a `Spacer`.

State class `AppShellState` exposes `sidebarWidth` getter. Sidebar width is managed internally and persists as long as the widget stays mounted.

### ClippedRow

Drop-in `Row` replacement that clips overflowing children **and** suppresses Flutter's debug overflow indicator (yellow-and-black stripes). Extends `Flex` and uses a custom `RenderFlex` subclass (`_ClippedRenderFlex`) that overrides `paint()` to always clip via `pushClipRect` and skip `paintOverflowIndicator` entirely. The built-in `Flex.clipBehavior: Clip.hardEdge` only clips children painting — the debug indicator is still painted unconditionally by `RenderFlex`. Use in any row whose parent can be resized (sidebar, split panes, column headers, status bars).

### AppIconButton

```dart
AppIconButton({
  required IconData icon,
  VoidCallback? onTap,         // null → disabled (30% opacity)
  String? tooltip,
  double size = 14,
  double boxSize = 26,
  Color? color,
  Color? hoverColor,
  Color? backgroundColor,      // permanent bg (e.g. mobile buttons)
  bool active = false,         // active state highlight
  BorderRadius? borderRadius,
})
```
Rectangular hover, no splash/ripple. **Replaces Material `IconButton` everywhere.**
When `tooltip` is set, `Tooltip` provides semantics. When absent, `Semantics(button: true)` is added for screen readers.

### HoverRegion

```dart
HoverRegion({
  required Widget Function(bool hovered) builder,
  VoidCallback? onTap,
  VoidCallback? onDoubleTap,
  void Function(TapUpDetails)? onSecondaryTapUp,
  void Function(LongPressStartDetails)? onLongPressStart,
  MouseCursor cursor = SystemMouseCursors.basic,
})
```
**Replaces `MouseRegion` + `GestureDetector` + `setState(_hovered)`.** Skips `MouseRegion` on mobile platforms (Android/iOS) — no pointer, saves an unnecessary widget. Exception: `context_menu.dart` (keyboard nav state).

### ModeButton

```dart
ModeButton({
  required String label,
  required IconData icon,
  required bool selected,
  required VoidCallback onTap,
})
```
Pill-shaped toggle button for import mode selection (merge/replace). Accent-colored when selected, neutral when not. Used in `settings_dialogs.dart` and `lfs_import_dialog.dart`.

### AppDialog

```dart
AppDialog({
  required String title,
  double maxWidth = 460,
  required Widget content,
  List<Widget> actions = const [],
  EdgeInsets contentPadding = const EdgeInsets.all(16),
  bool scrollable = true,
  bool dismissible = true,
})
```
Unified dialog shell matching the app's dark visual language. Background `AppTheme.bg1`, 24 px inset padding, constrained width, header bar with title + close button, optional footer with action buttons. **Replaces Material `AlertDialog` everywhere.** Exception: mobile keyboard buttons (`ssh_keyboard_bar.dart`, `mobile_file_browser.dart`) keep `Material` + `InkWell` for touch ripple feedback.

For complex dialogs (e.g. with tabs between header and content), compose from the building blocks directly:
- `AppDialogHeader({title, onClose})` — header bar
- `AppDialogFooter({actions})` — footer bar (uses `Wrap` layout — actions flow to the next line on narrow mobile screens)
- `AppDialogAction` — compact button (`.cancel()`, `.primary()`, `.secondary()`, `.destructive()`)
- `AppProgressDialog.show(context)` — non-dismissible loading spinner

Static helper: `AppDialog.show<T>(context, builder:)` wraps `showDialog` with `AnimationStyle.noAnimation` and consistent barrier settings.

### AppBorderedBox

```dart
AppBorderedBox({
  required Widget child,
  Color? borderColor,           // default: AppTheme.borderLight
  Color? color,                 // background color
  BorderRadius? borderRadius,   // default: AppTheme.radiusSm
  double borderWidth = 1,
  EdgeInsetsGeometry? padding,
  double? height,
  double? width,
  BoxConstraints? constraints,
  AlignmentGeometry? alignment,
})
```
**Replaces manual `BoxDecoration(border: Border.all(...))` patterns.** Guarantees `borderRadius` is always applied — prevents sharp-corner containers. Use this instead of hand-coded `Container` + `BoxDecoration` with `Border.all`.

### AppDivider

```dart
AppDivider({
  double indent = 0,
  double endIndent = 0,
  Color? color,                  // default: AppTheme.border
})
AppDivider.indented({Color? color})  // indent = 8, endIndent = 8
```
**Replaces bare `Divider(height: 1)` everywhere.** Standardises height (1 px), thickness (1 px), and color. Use `.indented()` for folder separators in menus.

### ColumnResizeHandle

```dart
ColumnResizeHandle({required void Function(double dx) onDrag})
```
Draggable column-resize handle for table headers. Place between a flexible column and a fixed-width column. The `onDrag` callback receives the raw horizontal delta (positive = right). Callers negate the delta when the fixed column is to the right of the handle. Used in `FilePane` and `TransferPanel` column headers.

### StyledFormField / FieldLabel / StyledInput

```dart
StyledFormField({
  required String label,               // uppercase label above the input
  required TextEditingController controller,
  String? hint,
  bool obscure = false,
  Widget? suffixIcon,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
  bool fixedHeight = false,            // wrap in SizedBox(controlHeightMd)
  bool autofocus = false,
  ValueChanged<String>? onSubmitted,
})
```
Reusable styled form field combining `FieldLabel` + `StyledInput`. Eliminates duplication across `SessionEditDialog`, `QuickConnectDialog`, and `LfsImportDialog`. Uses `AppFonts.mono()` for input text, `AppTheme.bg3` fill, `AppTheme.radiusSm` borders. Set `fixedHeight: true` for compact bottom-sheet layouts (wraps input in `SizedBox(height: controlHeightMd)` with zero vertical padding).

`FieldLabel(text)` — standalone uppercase label widget. `StyledInput(controller, ...)` — standalone text input with full decoration, accepts `labelText` and `contentPadding` overrides for non-standard layouts (e.g. `.lfs` import dialog).

### SplitView

```dart
SplitView({
  required Widget left,
  required Widget right,
  double initialLeftWidth = 220,
  double minLeftWidth = 150,
  double maxLeftWidth = 400,
})
```
Horizontal resizable split. Draggable divider 4px.

### Toast

```dart
Toast.show(context, {
  required String message,
  ToastLevel level,      // info | success | warning | error
  Duration duration,     // default 3s
});
```
Stacked notifications, fade + slide animation, auto-dismiss.

### ContextMenu

```dart
showAppContextMenu({
  required BuildContext context,
  required Offset position,
  required List<ContextMenuItem> items,
});

ContextMenuItem({
  String? label,
  IconData? icon,
  Color? color,
  String? shortcut,
  bool divider = false,
  VoidCallback? onTap,
});
ContextMenuItem.divider()
```
Keyboard nav (arrows, enter, esc), hover highlighting, repositioning.
Re-entrant: right-clicking a new location auto-dismisses the previous menu and opens a new one.
Styled with `AppTheme` colors directly (no Material surface tint).
Each item is wrapped in `Semantics(button: true, label: item.label)` for accessibility.

### HostKeyDialog

```dart
HostKeyDialog.showNewHost(context, {host, port, keyType, fingerprint})    → Future<bool>
HostKeyDialog.showKeyChanged(context, {host, port, keyType, fingerprint}) → Future<bool>
```
TOFU dialogs: new host / key changed.

### PassphraseDialog

```dart
PassphraseDialog.show(context, {required String host, int? attempt}) → Future<PassphraseResult?>
class PassphraseResult { String passphrase; bool remember; }
```
Interactive prompt for encrypted SSH key passphrase. Shows "wrong passphrase" on retry (attempt > 1).
Checkbox "Remember for this session" (default: checked). Returns null on cancel.
Wired via `ConnectionManager.onPassphraseRequired` → `SSHConnection.onPassphraseRequired`.

### ConfirmDialog

```dart
ConfirmDialog.show(context, {
  required String title,
  required Widget content,
  String? confirmLabel,  // null → S.of(context).delete
  bool destructive = true,
}) → Future<bool>
```

### ErrorState

```dart
ErrorState({
  required String message,
  VoidCallback? onRetry,
  String retryLabel = 'Retry',
  IconData retryIcon = Icons.refresh,
  VoidCallback? onSecondary,
  String? secondaryLabel,
  IconData? secondaryIcon,
})
```

### ConnectionProgress

```dart
ConnectionProgress({
  required Connection connection,
  String? channelLabel,   // e.g. "Opening SFTP channel"
})
```
Terminal-styled progress display for non-terminal tabs (SFTP file browser). Dark background (`AppTheme.bg2`), monospace font, text markers `[*]`/`[✓]`/`[✗]` — visually identical to the terminal progress output. Subscribes to `connection.progressStream` with history replay. Exposes `ConnectionProgressState.addStep()` for channel-specific steps (e.g. SFTP channel open) not covered by the SSH connection progress.

### LfsImportDialog

```dart
LfsImportDialog.show(context, {required String filePath})
  → Future<({String password, ImportMode mode})?>
```

### CrossMarqueeController

```dart
class CrossMarqueeController extends ChangeNotifier {
  Offset? globalPosition;
  CrossMarqueePhase phase;     // start | move | end
  bool get active;

  void start(Offset globalPos);
  void move(Offset globalPos);
  void end();
}
```
Notifier for cross-widget marquee selection.

### MarqueeMixin

```dart
mixin MarqueeMixin<T extends StatefulWidget> on State<T> {
  // Abstract methods (implement in host):
  double get marqueeRowHeight;
  int get marqueeItemCount;
  bool isMarqueeItemSelected(int index);
  void applyMarqueeSelection(int firstIndex, int lastIndex, {required bool ctrlHeld});

  // Ready-made handlers:
  void handleMarqueePointerDown(PointerDownEvent e);
  void handleMarqueePointerMove(PointerMoveEvent e);
  void handleMarqueePointerUp(PointerUpEvent e);
  Widget buildMarqueeOverlay(Color color);
}
```

### StatusIndicator

```dart
StatusIndicator({
  required IconData icon,     // Icon to display
  required int count,         // Numeric count next to the icon
  required String tooltip,    // Tooltip text on hover
  Color? iconColor,           // Override icon color (default: dim)
})
```

Compact icon + number indicator with tooltip. Used in sidebar footer to display session/connection/tab counts. Connection indicator counts both `connecting` and `connected` states; icon is green when any connection is established, yellow when all are still connecting. Reusable for any status bar needing icon + count pairs.

**File:** `lib/widgets/status_indicator.dart`

### ReadOnlyTerminalView

```dart
ReadOnlyTerminalView({
  required Terminal terminal,
  double fontSize = 14.0,
})
```
Read-only xterm `TerminalView` wrapper — no keyboard input, no context menu, cursor hidden. Used by `ConnectionProgress` for SFTP tab progress/error display. Wraps in `FocusScope(canRequestFocus: false)`.

### ThresholdDraggable

```dart
ThresholdDraggable<T extends Object>({
  // All standard Draggable params +
  double moveThreshold = 8.0,   // min pixels before drag begins
})
```
`Draggable` variant that requires `moveThreshold` pixels of pointer movement before initiating a drag. Prevents accidental drags when clicking close buttons or double-clicking items. Uses a custom `MultiDragGestureRecognizer`.

### MobileSelectionBar

```dart
MobileSelectionBar({
  required int selectedCount,
  required int totalCount,
  required VoidCallback onCancel,
  required VoidCallback onSelectAll,
  required VoidCallback onDeselectAll,
  required VoidCallback? onDelete,
  List<Widget> actions = const [],
})
```
Shared selection-mode action bar for mobile screens. Used by both the file browser and session panel. Shows: close button, count, select/deselect all toggle, custom action buttons, and delete.

### SortableHeaderCell

```dart
SortableHeaderCell({
  required String label,
  required bool isActive,
  required bool sortAscending,
  required VoidCallback onTap,
  required TextStyle style,
  double? width,
  TextAlign? textAlign,
})
```
Reusable sortable column-header cell for table views. Shows a label with optional sort-direction arrow (↑/↓). Highlights on hover and when active. Used in `FilePane` and `TransferPanel`.

Also provides `columnDivider()` — thin vertical divider between table columns (for data rows, not headers).

---

## 7. Utilities — Public API Reference

### AppLogger

```dart
class AppLogger {
  static AppLogger get instance;

  static const maxLogSizeBytes = 5 * 1024 * 1024;  // 5 MB
  static const _maxRotatedFiles = 3;

  String? get logPath;
  bool get enabled;

  Future<void> setEnabled(bool value);
  Future<void> init();
  void log(String message, {String? name, Object? error, StackTrace? stackTrace});
  Future<String> readLog();
  Future<void> dispose();   // sets enabled=false, closes sink
  Future<void> clearLogs(); // deletes all log files, reopens if enabled
}
```
File: `<appSupportDir>/logs/letsflutssh.log`. Rotation: 5 MB, 3 files.
`dispose()` sets `_enabled = false` so no writes occur after disposal.

**Rule:** `AppLogger.instance.log(message, name: 'Tag')` everywhere. Never `print()` / `debugPrint()`. Never log sensitive data. Use `stackTrace` parameter for full stack traces.

### Sanitize

```dart
String sanitizeErrorMessage(String message);
// Redacts: user@host → <user>@host, IPv4 → <ip>, port → :<port>,
// file paths with usernames → <path>/ or /<user>/
```

Use `sanitizeErrorMessage()` before logging any error message that may contain connection details, usernames, IPs, or file paths. The global error handler in `main.dart` applies this automatically.

**Rule:** Always sanitize error messages that may contain user data, server addresses, or file paths.

### FileUtils

```dart
Future<void> writeFileAtomic(String path, String content);
Future<void> writeBytesAtomic(String path, List<int> bytes);
Future<void> restrictFilePermissions(String path);  // async chmod 600
```

### Platform

```dart
String get homeDirectory;
  // Desktop: HOME or USERPROFILE
  // Android: EXTERNAL_STORAGE or /storage/emulated/0

bool get isMobilePlatform;     // Android || iOS
bool get isDesktopPlatform;    // Linux || macOS || Windows

// Testing:
@visibleForTesting bool? debugMobilePlatformOverride;
@visibleForTesting bool? debugDesktopPlatformOverride;
```

### TerminalClipboard

```dart
static void copy(Terminal terminal, TerminalController controller);
static Future<void> paste(Terminal terminal);
```

### Format

```dart
String formatSize(int bytes);         // "1.5 MB"
String formatTimestamp(DateTime dt);   // "2024-01-15 14:30"
String formatDuration(Duration d);    // "2m 15s"
String sanitizeError(Object error);   // strips OS-locale text, handles SSHError chain, 43 errno codes (POSIX + Winsock) — for logging only
String localizeError(S l10n, Object error); // maps errno/SSHError to localized strings via S — for UI display
```

---

## 8. Theme System

### AppTheme

Dark theme: **OneDark Pro** (binaryify/OneDark-Pro) exact hex values.
Light theme: **Atom One Light** (official) exact hex values.

Brightness-aware: all getters return the appropriate color based on current `_brightness`.
Every color in the UI MUST come from this class — no hardcoded hex or `Colors.*` outside `app_theme.dart`.

```dart
abstract final class AppTheme {
  static void setBrightness(Brightness brightness);
  static bool get isDark;

  // Backgrounds (dark / light)
  static Color get bg0;     // deepest surface           (#1B1D23 / #DBDBDC)
  static Color get bg1;     // sidebar, status bar       (#21252B / #EAEBEB)
  static Color get bg2;     // main content              (#282C34 / #FAFAFA)
  static Color get bg3;     // inputs, selection         (#2C313A / #E5E5E6)
  static Color get bg4;     // hover, inactive selection (#323842 / #DBDBDC)

  // Foreground
  static Color get fg;       // main text                (#ABB2BF / #383A42)
  static Color get fgDim;    // secondary text           (#7F848E / #696C77)
  static Color get fgFaint;  // disabled text            (#5C6370 / #A0A1A7)
  static Color get fgBright; // emphasized text          (#D7DAE0 / #232424)

  // Accent & syntax hues
  static Color get accent, blue, green, red, yellow, orange, cyan, purple;
  static Color get border;      // hard dividers         (#181A1F / #DBDBDC)
  static Color get borderLight; // panel borders         (#3E4452 / #DBDBDC)
  static Color get selection, hover, active;
  static Color get onAccent;    // text on accent bg     (#F8FAFD / #FFFFFF)

  // Terminal ANSI colors (OneDark Pro terminal palette / One Light syntax)
  static Color get termBlack, termRed, termGreen, termYellow;
  static Color get termBlue, termMagenta, termCyan, termWhite;
  static Color get termBrightBlack, termBrightRed, termBrightGreen, termBrightYellow;
  static Color get termBrightBlue, termBrightMagenta, termBrightCyan, termBrightWhite;
  static Color get termCursor;     // block cursor color (#528BFF / #526FFF)
  static Color get termSelection;  // mouse selection    (#677696 @ 38% / #4078F2 @ 38%)

  // Semantic colors (brightness-aware getters)
  static Color get connected;      // green  (#98C379 / #50A14F)
  static Color get connecting;     // yellow (#E5C07B / #C18401)
  static Color get disconnected;   // red    (#E06C75 / #E45649)
  static Color get info;           // cyan   (#56B6C2 / #0184BC)
  static Color get folderIcon;     // yellow (#E5C07B / #C18401)
  static Color get searchHighlight;// terminal search bg (#FFFF2B / #FFD700)
  static Color get searchHitFg;    // search hit text

  // Section border helpers (brightness-aware)
  static BorderSide get borderSide;  // BorderSide(color: border)
  static Border get borderTop;       // Border(top: borderSide)
  static Border get borderBottom;    // Border(bottom: borderSide)

  // Bar height scale
  static const double barHeightSm;  // 34 px — toolbars, headers, footers, status bars
  static const double barHeightMd;  // 40 px — dialog title bars, mobile breadcrumbs
  static const double barHeightLg;  // 44 px — mobile app bars, selection toolbars

  // Control height scale
  static const double controlHeightXs; // 26 px — compact buttons, file rows, settings items
  static const double controlHeightSm; // 28 px — context menu items, search inputs
  static const double controlHeightMd; // 30 px — input fields, auth-type selectors
  static const double controlHeightLg; // 32 px — tab selectors, mode selectors
  static const double controlHeightXl; // 38 px — dialog action buttons

  // Item height scale
  static const double itemHeightXs;  // 22 px — compact rows (path editors, transfer details)
  static const double itemHeightSm;  // 24 px — small items (resize handles, transfer entries)
  static const double itemHeightLg;  // 48 px — icon containers, mobile list items, drag targets
  static const double itemHeightXl;  // 56 px — mobile bottom navigation bar

  // Border radius scale
  static const radiusSm;  // 4 px — inputs, buttons, small elements
  static const radiusMd;  // 6 px — cards, containers, default rounding
  static const radiusLg;  // 8 px — toasts, mobile elements, larger containers

  // Shared builders — eliminate duplication across dialogs and terminal views
  static InputDecoration inputDecoration({
    String? labelText, String? hintText, TextStyle? hintStyle,
    EdgeInsetsGeometry contentPadding,
  });
  static TerminalTheme get terminalTheme; // xterm color theme from current brightness

  // Theme factory — both delegate to shared _buildTheme()
  static ThemeData dark();
  static ThemeData light();
}
```

### AppFonts

```dart
abstract final class AppFonts {
  // Platform-aware size scale (desktop / mobile)
  static double get tiny;  // 10 / 10 — transfer errors, smallest fine print
  static double get xxs;   // 11 / 11 — keyboard shortcuts, status badges
  static double get xs;    // 12 / 13 — captions, subtitles, metadata
  static double get sm;    // 13 / 14 — body text, inputs, default UI text
  static double get md;    // 14 / 14 — section headers, form labels
  static double get lg;    // 16 / 15 — dialog titles, sub-headings, toasts
  static double get xl;    // 19 / 18 — page headings

  static TextStyle inter({fontSize, fontWeight, color, height});  // UI text
  static TextStyle mono({fontSize, fontWeight, color});            // Code/data
}
```

Fonts: **Inter** (UI), **JetBrains Mono** (terminal, data). Assets: `assets/fonts/`.

**CJK & non-Latin in language picker:** Native language names (中文, 日本語, 한국어, العربية, فارسی, हिन्दी) rely on system fonts. Each entry has an English secondary label (Chinese, Japanese, Korean, Arabic, Persian, Hindi) as fallback for systems without those fonts. No bundled CJK/Arabic/Devanagari fonts — keeps the binary small.

**Rule:** Never use hardcoded `fontSize` numeric literals — always use `AppFonts.xs`, `AppFonts.sm`, etc. The constants are platform-aware: mobile gets +2 px automatically for touch readability.

**Rule:** Never use hardcoded `BorderRadius.circular(N)` or `BorderRadius.zero` — always use `AppTheme.radiusSm`, `radiusMd`, or `radiusLg`. Exception: pill-shaped elements (e.g. toggle tracks) that need full rounding.

**Rule:** Never hardcode height numeric literals for UI elements — always use `AppTheme` height constants. Three scales are available: `barHeight{Sm,Md,Lg}` for toolbars/headers/bars, `controlHeight{Xs..Xl}` for buttons/inputs/selectors, `itemHeight{Xs..Xl}` for rows/containers/list items. Panels sit flush without borders; resizable dividers use `Stack` overlays (6 px invisible hit zone, 1 px visible line where needed).

---

## 8.1 Internationalization (i18n)

All user-facing strings are externalized via Flutter's built-in `gen_l10n` system.

### Supported languages

| Code | Language | File |
|------|----------|------|
| `en` | English (template) | `app_en.arb` |
| `ru` | Russian | `app_ru.arb` |
| `zh` | Chinese (Simplified) | `app_zh.arb` |
| `de` | German | `app_de.arb` |
| `ja` | Japanese | `app_ja.arb` |
| `pt` | Portuguese | `app_pt.arb` |
| `es` | Spanish | `app_es.arb` |
| `fr` | French | `app_fr.arb` |
| `ko` | Korean | `app_ko.arb` |
| `ar` | Arabic (العربية) | `app_ar.arb` |
| `fa` | Persian (فارسی) | `app_fa.arb` |
| `tr` | Turkish | `app_tr.arb` |
| `vi` | Vietnamese | `app_vi.arb` |
| `id` | Indonesian | `app_id.arb` |
| `hi` | Hindi (हिन्दी) | `app_hi.arb` |

### Language selection

The user selects a language in **Settings → Appearance → Language**. Options: "System Default" (auto-detect from OS) or any of the 15 supported languages. Stored as `AppConfig.locale` (`null` = system default, `'ru'` = Russian, etc.). Wired via `localeProvider` → `MaterialApp.locale`.

iOS requires `CFBundleLocalizations` in `Info.plist` listing all supported locale codes for proper OS locale detection.

### Setup

| File | Purpose |
|------|---------|
| `l10n.yaml` | Config: ARB dir, template, output class `S`, non-nullable getter |
| `lib/l10n/app_en.arb` | English strings (template) — add new keys here |
| `lib/l10n/app_XX.arb` | Translations — one file per language |
| `lib/l10n/app_localizations.dart` | Generated — `S` class with all getters |
| `lib/l10n/app_localizations_XX.dart` | Generated — per-language implementations |

### Usage

```dart
import '../l10n/app_localizations.dart';

// In any widget with BuildContext:
Text(S.of(context).settings)
Text(S.of(context).nSessions(count))  // parameterized
```

`S.of(context)` is non-nullable — no `!` needed. `MaterialApp` in `main.dart` has `locale: ref.watch(localeProvider)`, `localizationsDelegates: S.localizationsDelegates` and `supportedLocales: S.supportedLocales`.

### Adding a new language

1. Copy `lib/l10n/app_en.arb` → `lib/l10n/app_XX.arb` (e.g., `app_it.arb`)
2. Set `"@@locale": "XX"` and translate all values (keep keys and placeholders intact)
3. Do NOT copy `@key` metadata entries — only the template needs them
4. Run `flutter gen-l10n` — generates `app_localizations_xx.dart` automatically
5. Add the locale code to `AppConfig.supportedLocales` list
6. Add the locale entry to `_LanguageTile._localeLabels` in `settings_screen.dart`
7. Add the locale code to `CFBundleLocalizations` in `ios/Runner/Info.plist`

### Adding a new string

1. Add the key + value to `lib/l10n/app_en.arb` (with `@key` metadata for placeholders)
2. Add the translated key to ALL `app_XX.arb` files
3. Run `flutter gen-l10n`
4. Use `S.of(context).newKey` in the widget

### Rules

- **Never hardcode user-facing strings** — always use `S.of(context).xxx`
- Constructor default parameters (e.g., `confirmLabel = 'Delete'`) stay hardcoded — no `context` available
- Strings only used in logs (`AppLogger`) stay hardcoded — not user-facing
- Tests must include `localizationsDelegates: S.localizationsDelegates` and `supportedLocales: S.supportedLocales` in every `MaterialApp`
- Generated files (`app_localizations*.dart`) are committed to the repo

---

## 9. Data Flow Diagrams

### 9.1 SSH Connection Flow

```
User clicks session
         │
         ▼
SessionConnect.connectTerminal(session)
         │
         ├── Session → SSHConfig (with credentials from CredentialStore)
         │
         ▼
connectionManager.connectAsync(config)
         │
         ├── Creates Connection (state: connecting)
         ├── Launches async _doConnect() in background
         └── Returns Connection → UI
                                      │
_doConnect():                         │
  1. SSHConnection.connect(onProgress) │
     ├── onProgress(socketConnect.inProgress)
     ├── TCP socket                   ▼
     ├── onProgress(socketConnect.success)
     ├── onProgress(hostKeyVerify.inProgress)
     ├── Host key verify     UI: tabProvider.addTerminalTab(connection)
     ├── onProgress(hostKeyVerify.success)         │
     ├── onProgress(authenticate.inProgress)       ▼
     ├── Auth chain          TerminalPane subscribes to progressStream
     └── onProgress(authenticate.success)          │
  2. Success:                          ▼
     ├── state = connected   TerminalPane: clear terminal → openShell()
     └── completeReady()                            → xterm pipe
  3. Failure:
     ├── connectionError     TerminalPane: progress log stays visible
     ├── state = disconnected         with error text in terminal buffer
     └── completeReady()
```

**Progress pipeline:** `SSHConnection.connect()` accepts an `onProgress` callback that emits `ConnectionStep` events at each phase boundary. `ConnectionManager._doConnect()` forwards these to `Connection.addProgressStep()`, which buffers them in `progressHistory` and broadcasts via `progressStream`. The UI subscribes to the stream (replaying history for late subscribers) and renders steps in real time.

**Reconnect flow:** When a terminal tab reconnects (user clicks "Reconnect" after disconnect), `TerminalTab._refreshConfig()` re-reads the `Session` from `sessionProvider` using `Connection.sessionId` and updates `Connection.sshConfig` before creating a new `SSHConnection`. This ensures reconnect picks up any session edits (e.g. added keys, changed password). Quick-connect tabs (`sessionId == null`) use the original config.

### 9.2 SFTP Init Flow

```
FileBrowserTab.initState()
         │
         ├── Shows ConnectionProgress widget (subscribes to progressStream)
         ├── await connection.waitUntilReady()
         │
         ▼
SFTPInitializer.init(connection)
         │
         ├── [Android] _requestStoragePermission()
         │     ├── Quick-check /storage/emulated/0
         │     └── MethodChannel → MainActivity.kt
         │           ├── API 30+: ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION
         │           └── API <30: READ/WRITE_EXTERNAL_STORAGE runtime dialog
         │
         ├── connection.sshConnection.client.sftp()  → SftpClient
         │
         ├── LocalFS(homeDirectory)  → FilePaneController (local)
         └── RemoteFS(SFTPService)   → FilePaneController (remote)
                                              │
                                              ▼
                                     FilePane(controller) × 2
```

### 9.3 Session CRUD Flow

```
UI → sessionProvider.add(session)
         │
         ├── SessionStore.add(session)
         │     ├── Adds to list
         │     └── SessionStore.save()
         │           ├── sessions.json (metadata, atomic write)
         │           └── credentials.enc (AES-256-GCM, atomic write)
         │
         ├── SessionHistory.push(snapshot)  ← undo support
         │
         └── state = [...state, session]
                      │
                      ▼
              sessionTreeProvider recomputes
              filteredSessionsProvider recomputes
              UI rebuilds
```

### 9.4 File Transfer Flow

```
User drags file between panes
         │
         ▼
FileActions.transfer(source, target, direction)
         │
         ├── Creates TransferTask(name, direction, paths, size, run)
         │     run = async (progressCallback) {
         │       SFTPService.uploadFile/downloadFile(from, to, progressCallback)
         │     }
         │
         ▼
transferManager.enqueue(task)
         │
         ├── Adds to queue
         ├── If workers < max → starts a worker
         │
         ▼
Worker:
  ├── task.state = running
  ├── task.run(progressCallback)
  │     progressCallback checks:
  │       - cancelled? → throw CancelException
  │       - timeout? → throw TimeoutException
  │       - updates progress %
  ├── Success → HistoryEntry(completed)
  └── Failure → HistoryEntry(failed, error)
         │
         ▼
Streams → UI updates (TransferPanel)
```

---

## 10. Data Models

### Session

```dart
Session {
  id: String              // UUID v4
  label: String           // display name
  folder: String           // folder path: "Production/Web" (/ separator)
  server: ServerAddress {
    host: String
    port: int             // default 22
    user: String
  }
  auth: SessionAuth {
    authType: AuthType    // password | key | keyWithPassword (Both)
    password: String      // empty if not used
    keyPath: String       // key file path (or ~)
    keyData: String       // PEM text (paste)
    passphrase: String    // for the key
  }
  createdAt: DateTime
  updatedAt: DateTime
  incomplete: bool        // QR import without credentials
}
```

### Connection

```dart
Connection {
  id: String              // UUID (bound to tab)
  label: String
  sshConfig: SSHConfig    // mutable — refreshed from session store on reconnect
  sessionId: String?      // links back to saved Session (null for quick-connect)
  knownHosts: KnownHostsManager  // for host key verification
  sshConnection: SSHConnection?
  state: SSHConnectionState  // disconnected | connecting | connected
  connectionError: Object?
  _readyCompleter: Completer // resolves after connect attempt
}
```

### TabEntry

```dart
TabEntry {
  id: String              // UUID
  label: String
  connection: Connection
  kind: TabKind           // terminal | sftp

  copyWith({label})       // same id, updated label
  duplicate()             // new UUID, same connection/label/kind
}
```

### FileEntry

```dart
FileEntry {
  name: String
  path: String            // full POSIX path
  size: int               // bytes
  mode: int               // Unix permissions (octal)
  modTime: DateTime
  isDir: bool
  owner: String           // parsed from ls -l longname
}
```

### TransferTask

```dart
TransferTask {
  name: String            // display name
  direction: TransferDirection  // upload | download
  sourcePath: String
  targetPath: String
  sizeBytes: int
  run: Future<void> Function(ProgressCallback)
  // Note: id, state, progress are managed by TransferManager (ActiveEntry wrapper),
  // not stored on TransferTask itself
}
```

### AppConfig

```dart
AppConfig {
  terminal: TerminalConfig {
    fontSize: double      // 6-72, default 14.0
    theme: String         // 'dark'|'light'|'system'
    scrollback: int       // ≥100, default 5000
  }
  ssh: SshDefaults {
    keepAliveSec: int     // default 30
    defaultPort: int      // default 22
    sshTimeoutSec: int    // default 10
  }
  ui: UiConfig {
    windowWidth: double
    windowHeight: double
    uiScale: double       // 0.5-2.0
    showFolderSizes: bool
    toastDurationMs: int  // default 4000
  }
  transferWorkers: int    // 1+, default 2
  maxHistory: int         // ≥0, default 500
  enableLogging: bool
  checkUpdatesOnStart: bool
  skippedVersion: String?
  locale: String?           // null = OS auto-detect, or supported locale code
}
```

---

## 11. Persistence & Storage

| Data | File | Encryption | Format | Atomic write |
|------|------|-----------|--------|-------------|
| Sessions (metadata) | `sessions.json` | No | JSON | Yes |
| Credentials | `credentials.enc` | AES-256-GCM | JSON → encrypted | Yes |
| Encryption key | `credential.key` | No (file permissions) | 32 raw bytes | Yes |
| Config | `config.json` | No | JSON | Yes |
| Known hosts | `known_hosts` | No | SSH standard | Yes |
| Logs | `logs/letsflutssh.log` | No | Text | No |
| Transfer history | In-memory | N/A | — | — |
| Instance lock | `app.lock` | No | PID text | No (OS-managed) |

**Location:** `path_provider` → `getApplicationSupportDirectory()`
- Linux: `~/.local/share/letsflutssh/`
- macOS: `~/Library/Application Support/letsflutssh/`
- Windows: `%APPDATA%\letsflutssh\`
- Android: app internal storage
- iOS: app sandbox

**Atomic write pattern:** Writes to a temporary file, then `rename()`. Prevents data loss on crash.

**File permissions:** `restrictFilePermissions()` → chmod 600 on Unix platforms for credentials and known_hosts.

---

## 12. Platform-Specific Behavior

| Aspect | Desktop (Linux/macOS/Windows) | Mobile (Android/iOS) |
|--------|-------------------------------|---------------------|
| Entry point | `MainScreen` (sidebar + tabs) | `MobileShell` (bottom nav) |
| Navigation | Sidebar + tab bar | Bottom nav: Sessions / Terminal / SFTP |
| Terminal | Tiling (split panes) | Full screen, single pane |
| File browser | Dual-pane (local + remote) | Single-pane (toggle) |
| Selection | Click + Ctrl/Shift + marquee | Long-press → bulk mode |
| Context menu | Right-click | Long-press |
| Keyboard | Hardware only (`hardwareKeyboardOnly: true`) | SSH keyboard bar + system |
| SSH keep-alive | OS keeps process alive | Foreground service (Android) |
| Home directory | `HOME` / `USERPROFILE` | Android: `EXTERNAL_STORAGE` / `/storage/emulated/0`; iOS: app Documents dir + folder picker |
| Drag & drop | desktop_drop + inter-pane | None |
| Deep links | `app_links` (URL scheme) | `app_links` (URL scheme + file intents) |
| Single instance | File lock (`app.lock`) | OS-managed natively |
| Font scaling | UI scale in settings | Pinch-to-zoom terminal |

### Android specifics

- **Storage permission** — `MANAGE_EXTERNAL_STORAGE` for full file access. Requested via custom MethodChannel (`com.letsflutssh/permissions`) in `MainActivity.kt`. Android 11+ opens the system "All files access" settings page (`ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`); older versions use standard `READ_EXTERNAL_STORAGE`/`WRITE_EXTERNAL_STORAGE` runtime dialog. No external plugin (avoids permission_handler GPS side-effects). Dart side: `SFTPInitializer._requestStoragePermission()` — quick-checks `/storage/emulated/0` first, requests only if needed
- `flutter_foreground_task` for keep-alive on screen lock
- APK split per ABI: arm64-v8a, armeabi-v7a, x86_64

### iOS specifics

- `NSLocalNetworkUsageDescription` required for local TCP
- No foreground service (iOS background modes)
- **Local file browser** — starts in app's Documents directory (`getApplicationDocumentsDirectory()`), which is accessible via Files.app. Users can browse outside the sandbox via a "Pick Folder" button (iOS only, uses `file_picker` → `UIDocumentPickerViewController` in folder mode). Security-scoped access is granted for the session after the user picks a folder

### Desktop window constraints

All desktop platforms enforce a minimum window size of **480 × 360** logical pixels to prevent layout overflow:

| Platform | File | Mechanism |
|----------|------|-----------|
| Windows | `windows/runner/win32_window.cpp` | `WM_GETMINMAXINFO` with DPI scaling |
| Linux | `linux/runner/my_application.cc` | `gtk_window_set_geometry_hints` (`GDK_HINT_MIN_SIZE`) |
| macOS | `macos/Runner/MainFlutterWindow.swift` | `NSWindow.contentMinSize` |

Additionally, internal resizable elements (sidebar, file browser columns, split panes) use overflow-safe patterns:
- **`ClippedRow`** (`widgets/clipped_row.dart`): drop-in `Row` replacement with custom `_ClippedRenderFlex` that clips overflow and suppresses the debug overflow indicator entirely. Used in file browser rows, column headers, breadcrumb paths, connection bar, and transfer panel
- **Sidebar text** (`_SidebarFooter`, `_PanelHeader`, session tree rows): `Flexible` / `Expanded` with `TextOverflow.ellipsis`
- **Welcome screen**: `SingleChildScrollView` prevents vertical overflow on small windows

### Single-instance protection (desktop only)

Prevents multiple app instances from running simultaneously, which would corrupt shared config/session files.

**Mechanism:** exclusive file lock via `RandomAccessFile.lock(FileLock.exclusive)` on `app.lock` in the app data directory (`getApplicationSupportDirectory()`). The OS kernel automatically releases the lock when the process exits (even on crash), so there are no stale lock files.

**Flow:**
1. `main()` → `SingleInstance.acquire()` before `runApp()`
2. If lock acquired → proceed normally
3. If lock fails → show `_AlreadyRunningApp` (minimal dialog: "Another instance is already running" + OK button → `exit(0)`)

**Mobile:** skipped — Android/iOS manage single instance natively.

**File:** `core/single_instance/single_instance.dart`

### Windows specifics

- `hardwareKeyboardOnly: true` — xterm TextInputClient bug
- Inno Setup for EXE installer
- `USERPROFILE` for home directory

---

## 13. Security Model

### Three-level encryption

All data stores support three security levels (see §3.6):

| Level | Key source | Encrypted files |
|-------|-----------|----------------|
| Plaintext | None | `sessions.json`, `keys.json`, `known_hosts` |
| Keychain | OS keychain (`flutter_secure_storage`) | `sessions.enc`, `keys.enc`, `known_hosts.enc` |
| Master Password | PBKDF2-derived | `sessions.enc`, `keys.enc`, `known_hosts.enc` + `credentials.salt` + `credentials.verify` |

All encrypted files use AES-256-GCM via `AesGcm` utility. Wire format: `[IV 12B] [ciphertext + GCM tag]`.

No `credentials.key` file — the old pattern of storing a key next to the ciphertext is eliminated.

### First-launch wizard

`SecuritySetupDialog` shown on first launch (no data files on disk):
1. Probes OS keychain via `SecureKeyStorage.isAvailable()` (write+read+delete cycle)
2. Keychain found → offers "Continue with Keychain" or "Set Master Password"
3. Keychain not found → offers "Continue without Encryption" or "Set Master Password"

### Startup security flow

`_initSecurity()` in `main.dart`:
1. `credentials.salt` exists → show `UnlockDialog` → derive key
2. Keychain has key → read from keychain
3. Data files exist but no encryption → plaintext mode
4. No data at all → first launch → show `SecuritySetupDialog` wizard
5. Inject key into all three stores via `_injectKey()` + update `securityStateProvider`

### Master password

```
User password → PBKDF2-SHA256(600k iterations, random salt) → 256-bit key
                                                                   │
                               ┌───────────────┬──────────────────┤
                               ▼               ▼                  ▼
                        sessions.enc      keys.enc       known_hosts.enc
```

- **Detection:** `credentials.salt` exists = master password enabled
- **Verification:** `credentials.verify` = AES-256-GCM(known plaintext "LetsFLUTssh-verify")
- **Enable flow:** derive key → `reEncrypt()` all three stores → delete keychain key if present
- **Disable flow:** try keychain → generate random key → `reEncrypt()` all stores → delete salt/verifier. No keychain → plaintext fallback
- **Change flow:** verify old → derive new → `reEncrypt()` all three stores
- **Forgot password:** deletes all encrypted files (salt, verifier, all `.enc` files)

### .lfs export

```
[salt 32B] [IV 12B] [AES-256-GCM(ZIP(sessions.json + config.json + known_hosts))]

Key = PBKDF2-SHA256(password, salt, 600000 iterations)
```

Export decrypts known_hosts via `KnownHostsManager.exportToString()`. Import returns content for caller to import via `KnownHostsManager.importFromString()`.

### TOFU (Trust On First Use)

- New host → dialog with SHA256 fingerprint → user accepts/rejects
- Changed key → warning dialog → user accepts/rejects
- Without callback → reject (fail-safe)
- known_hosts encrypted when security level > plaintext

### Deep link validation

- URL scheme whitelist
- Path traversal rejection (`../`)
- Host/port sanitization

### Error sanitization & localization

- `sanitizeError()` translates OS-locale error text to English using errno codes — **for logging only**
- `localizeError(S l10n, Object error)` maps errno codes, `SSHError` subtypes, and `TimeoutException` to localized strings via `S` — **for UI display**
- Handles `SSHError` chain: preserves structured data (`host`, `port`, `user`), sanitizes `cause` recursively
- 43 errno codes mapped (30 POSIX/Linux + 13 Windows Winsock)
- `SSHError` subtypes carry structured fields: `AuthError(user, host)`, `ConnectError(host, port)`, `HostKeyError(host, port)`
- `SFTPError` (`core/sftp/errors.dart`) — typed SFTP error with `message`, `cause`, `path`, `statusCode`, `userMessage`. Factory `SFTPError.wrap(error, op, path)` for wrapping raw exceptions with operation context
- `Connection.connectionError` stores raw `Object?` — localized at display time with `localizeError`
- Unknown errno → original OS text preserved as-is
- Applied in: `ConnectionManager`, `TerminalTab.reconnect()`, `TransferManager` (+ path stripping, inline error in transfer panel)

---

## 14. Testing Patterns & DI Hooks

### Injectable factories

| Class | DI parameter | Purpose |
|-------|------------|---------|
| `SSHConnection` | `socketFactory`, `clientFactory` | Mock TCP/SSH |
| `ConnectionManager` | `connectionFactory` | Mock connection creation |
| `TerminalTab` | `reconnectFactory` | Mock reconnect logic |
| `FileBrowserTab` | `sftpInitFactory` | Mock SFTP initialization |
| `MobileFileBrowser` | `sftpInitFactory` | Mock SFTP initialization (mobile) |
| `ForegroundServiceManager` | `create()` factory | Platform-specific impl |

### Platform overrides

```dart
debugMobilePlatformOverride = true;    // force mobile layout in tests
debugDesktopPlatformOverride = true;   // force desktop layout in tests
```

### Shared test helpers (`test/helpers/`)

| File | Contents |
|------|----------|
| `test_notifiers.dart` | `TestConfigNotifier`, `PrePopulatedConfigNotifier`, `PrePopulatedSessionNotifier`, `PrePopulatedWorkspaceNotifier`, `PrePopulatedUpdateNotifier`, `FixedVersionNotifier` |
| `fake_session_store.dart` | `FakeSessionStore` (in-memory), `ThrowingSessionStore` |

### Test file mapping

Rule: **one test file per source file** (`lib/core/ssh/ssh_client.dart` → `test/core/ssh/ssh_client_test.dart`). No `_extra_test.dart` files.

### Mock generation

Uses `mockito` + `@GenerateMocks`. Generated mocks: `*.mocks.dart`.

### Fuzz testing

Two layers of fuzz testing:

**Dart property-based tests** (`test/fuzz/`): run as part of `make test` (included in `test/`). Generate random/malformed inputs for parsers and verify they never crash with unhandled exceptions. Targets:

| Test file | Fuzzed function | Input type |
|-----------|----------------|------------|
| `fuzz_session_json_test.dart` | `Session.fromJson()` | Random JSON maps |
| `fuzz_qr_codec_test.dart` | `decodeSessionsFromQr()`, `decodeImportUri()` | Random strings, URIs |
| `fuzz_app_config_test.dart` | `AppConfig.fromJson()` + sub-configs | Random JSON maps |
| `fuzz_deeplink_test.dart` | `DeepLinkHandler.parseConnectUri()` | Random URIs |
| `fuzz_format_test.dart` | `sanitizeError()`, `formatSize()`, `formatDuration()` | Random strings, errno patterns, objects |

**Standalone fuzz harnesses** (`fuzz/`): compiled to native via `dart compile exe` (`make fuzz-build`). Read from stdin, exercise parsing logic, used by ClusterFuzzLite/AFL++ in CI. Targets: `fuzz_json_parser`, `fuzz_known_hosts`, `fuzz_uri_parser`.

**CI integration**: `.github/workflows/cfl-fuzz.yml` runs ClusterFuzzLite on push to main and PRs to main. Detected by OpenSSF Scorecard's Fuzzing check.

---

## 15. CI/CD Pipeline

### 15.1 Branching Model

Two branches: **`dev`** (daily work) and **`main`** (releases only).

- All app development happens on `dev`. Push freely — CI and security scans run on PRs (not on every push). No tags, no builds, no releases.
- To release: merge `dev` → `main`. Everything is automatic: CI → auto-tag → build → release.
- Never push app changes directly to `main`. Dependabot PRs and CI/docs-only fixes are exceptions.
- **Contributors** work via forks → PR into `dev`. CI runs on PRs automatically. Maintainer reviews and merges.

**Branch Protection (GitHub Rulesets):**

| Ruleset | Branch | Rules | Bypass |
|---------|--------|-------|--------|
| `main` | `main` | No deletion, no force-push, PR required, all CI checks required | None |
| `dev-protect` | `dev` | No deletion, no force-push | None |
| `dev-checks` | `dev` | All CI checks required (`ci`, `osv-scan`, `semgrep-scan`, `codeql-scan`) | Admin — allows direct push |

### 15.2 Workflow Graph

```
push to dev/main or PR
  │
  ├─► ci.yml                 (always runs — no path filters)
  │     analyze + test + coverage
  │           │
  │           ├─► ci-sonarcloud.yml   (workflow_run[CI], non-fork only)
  │           │     quality + coverage scan
  │           │
  │           └─► ci-auto-tag.yml     (workflow_run[CI], main only)
  │                 reads version from pubspec.yaml
  │                 tag exists → skip / new version → create tag
  │                       │
  │                       └─► build-release.yml    "Build & Release"  (tags: v*)
  │                             build all platforms
  │                             → GitHub Release + SLSA attestation
  │
  ├─► cfl-fuzz.yml             (push main / PR to main)
  │     cfl-fuzz
  │
  ├─► osv.yml                 (main push + PR + weekly)
  ├─► codeql.yml              (main push + PR + weekly)
  ├─► semgrep.yml             (main push + PR + weekly)
  └─► scorecard.yml            (main push + weekly)

Dependabot PR (into main)
  │
  └─► dependabot-auto.yml → bump version in PR branch → auto-merge
        └─► ci.yml → ci-auto-tag.yml → build-release.yml → Release

Version bump (on dev, before PR)
  │
  └─► scripts/bump-version.sh → parse commits → bump pubspec.yaml → commit

Manual build
  │
  └─► gh workflow run build-release.yml
        CI not passed? → fail immediately (no polling)
```

### 15.3 Workflow Catalog

| Workflow | Trigger | Branches | Purpose | Blocks release? |
|----------|---------|----------|---------|-----------------|
| `ci.yml` | push main / PR (all) | main, dev | analyze + test + coverage | Yes (required) |
| `ci-auto-tag.yml` | workflow_run[CI] success | main only | Reads version, creates tag if new | — |
| `build-release.yml` | push tag v* / manual | — | Build all platforms + release | — |
| `ci-sonarcloud.yml` | workflow_run[CI] / manual | main, dev | Quality + coverage scan | No (warn-only) |
| `dependabot-auto.yml` | PR (dependabot) | main | Bump version in PR branch + auto-merge patch/minor | — |
| `osv.yml` | push main / PR (all) / weekly | main | CVE scan (pubspec.lock) | Yes on PR |
| `codeql.yml` | push main / PR (all) / weekly | main | GitHub Actions analysis | Yes on PR |
| `semgrep.yml` | push main / PR (all) / weekly | main | SAST scan (Dart code) | Yes on PR |
| `cfl-fuzz.yml` | push main / PR to main | main | cfl-fuzz | No |
| `scorecard.yml` | push main / weekly | main | OpenSSF supply chain assessment | No |

**External Integrations:**

| Service | Config | Purpose |
|---------|--------|---------|
| GitGuardian | `.gitguardian.yml` | Secret detection on PRs. Test files (`test/**`) and localization files (`lib/l10n/**`) are excluded — they contain fake credentials and translated "password" labels that trigger false positives |

### 15.4 Makefile Targets

#### Development

| Target | Command | Purpose |
|--------|---------|---------|
| `make run` | `flutter run` | Run (debug) |
| `make run-release` | `flutter run --release` | Run (release) |
| `make test` | `flutter test --coverage --timeout 30s` | Tests with coverage |
| `make analyze` | `flutter analyze --fatal-infos` | Lint + analyze |
| `make check` | analyze + test | Full check |
| `make format` | `dart format .` | Format code |
| `make gen` | `build_runner build` | Code generation |
| `make deps` | `flutter pub get` | Install dependencies |
| `make fuzz-build` | `dart compile exe fuzz/*.dart` | Compile native fuzz targets |

#### Build

| Target | Platform |
|--------|----------|
| `make build-linux` | Linux x64 |
| `make build-macos` | macOS universal |
| `make build-apk` | Android per-ABI |
| `make build-aab` | Android App Bundle |
| `make build-ios` | iOS |

#### Packaging

| Target | Format |
|--------|--------|
| `make package-linux` | tar.gz |
| `make package-appimage` | AppImage |
| `make package-deb` | .deb |
| `make package-windows` | .zip |
| `make package-exe` | Inno Setup EXE |

---

## 16. Design Decisions & Rationale

### 16.1 Architecture Choices

| Decision | Why |
|----------|-----|
| `pointycastle` instead of `encrypt` | Version conflict with dartssh2 |
| Three-level security (plaintext/keychain/master password) | Honest security: no key-file next to ciphertext. OS keychain optional with graceful fallback |
| `flutter_secure_storage` as optional dep | OS keychain for automatic encryption; app works without it (libsecret on Linux is optional) |
| `app_links` instead of `uni_links` | Desktop support |
| `FilePaneController` as `ChangeNotifier` | Lightweight per-pane state, Riverpod overhead not justified |
| Sealed class `SplitNode` | Recursive split tree with type safety |
| Each terminal pane → own SSH shell | Shared `SSHConnection`, independent shells |
| `Listener` for marquee | Raw pointer events don't conflict with `Draggable` |
| `IndexedStack` for tabs | Preserves terminal state when switching tabs |
| `GlobalKey` for tab widgets | Preserves widget state when tab is dragged to a new panel |
| Separate `features/mobile/` | Different interaction patterns, not a responsive adaptation |
| Global `navigatorKey` for host key dialog | SSH callback arrives without BuildContext |
| `AnimationStyle.noAnimation` | Animations disabled (Flutter 3.41+), design decision |
| `AppShortcutRegistry` singleton | Centralized shortcut definitions; all key combos in one place, ready for future user-override settings page |
| `matches()` checks only ctrl/shift | Original handlers didn't check alt/meta; WSLg can report phantom meta, causing false negatives |

### 16.2 API Gotchas

| Problem | Solution |
|---------|----------|
| `ConnectionState` conflict with Flutter async.dart | Use `SSHConnectionState` |
| dartssh2 host key callback: `FutureOr<bool> Function(String type, Uint8List fingerprint)` | Not SSHPublicKey — remember the signature |
| dartssh2 SFTP: `attr.mode?.value` | Not `.permissions?.mode` |
| dartssh2 SFTP: `remoteFile.writeBytes()` | Not `.write()` |
| xterm TextInputClient broken on Windows | `hardwareKeyboardOnly: true` on desktop |

### 16.3 Security Decisions

| Decision | Rationale |
|----------|-----------|
| PBKDF2 600k iterations | OWASP 2024 recommendation |
| chmod 600 | Minimal permissions on sensitive files |
| TOFU reject without callback | Fail-safe: if no UI → reject |
| `CredentialStoreException` with two types | Distinguish "no credentials" from "corrupt key" |
| SessionStore abort on credential load failure | Prevents overwriting encrypted store |
| SessionStore concurrent load guard | Prevents race condition when multiple lifecycle events fire simultaneously |
| `RandomAccessFile` + try/finally for upload | Guarantees file handle cleanup |
| Error sanitization | Don't expose file paths to user |
| Deep link path traversal rejection | URL handling security |

### 16.4 Platform Decisions

| Decision | Platform | Rationale |
|----------|----------|-----------|
| `EXTERNAL_STORAGE` env + fallback | Android | Not all devices set the env var |
| `MANAGE_EXTERNAL_STORAGE` permission | Android | Access files outside sandbox |
| `NSLocalNetworkUsageDescription` | iOS | Required for local TCP (SSH connections) |
| Foreground service | Android | Prevents SSH kill on screen lock |
| Per-ABI APK split | Android | Reduces APK size |
| Universal binary | macOS | Intel + Apple Silicon in one binary |

---

## 17. Dependencies

> **Versions are NOT listed here** — `pubspec.yaml` is the single source of truth.
> Run `flutter pub deps` to see the resolved dependency tree.

### Runtime

| Package | Purpose |
|---------|---------|
| `flutter_localizations` | Flutter i18n delegates (SDK package) |
| `intl` | ICU message formatting for l10n |
| `dartssh2` | SSH2 protocol (auth, shell, SFTP) |
| `xterm` | Terminal emulator widget |
| `flutter_riverpod` | State management |
| `pointycastle` | AES-256-GCM encryption (transitive via dartssh2) |
| `path_provider` | App data directories |
| `archive` | ZIP for .lfs export/import |
| `desktop_drop` | OS drag & drop |
| `flutter_foreground_task` | Android foreground service |
| `app_links` | Deep links + file intents |
| `qr_flutter` | QR code generation |
| `file_picker` | File selection |
| `package_info_plus` | App version at runtime |
| `url_launcher` | Open URLs |
| `uuid` | UUID generation |
| `path` | Cross-platform path utils |
| `json_annotation` | JSON serialization |

### Dev

| Package | Purpose |
|---------|---------|
| `flutter_lints` | Lint rules |
| `mockito` | Test mocking |
| `build_runner` | Code generation |
| `json_serializable` | JSON code gen |
| `build_verify` | Verifies build_runner output is up-to-date |
| `plugin_platform_interface` | Platform interface for plugin packages |
| `flutter_launcher_icons` | App icon gen |

### Bundled Fonts

| Font | Purpose | Location |
|------|---------|----------|
| Inter | UI text | `assets/fonts/` |
| JetBrains Mono | Terminal, monospaced data | `assets/fonts/` |

### SDK Constraints

- **Flutter** ≥ 3.41.0 (stable channel)
- **Dart** ≥ 3.11.3 (ships with Flutter ≥ 3.41.0)

See `pubspec.yaml` → `environment` section for the canonical constraint. Run `flutter --version` to check.

### Lint Rules

Base: `flutter_lints/flutter.yaml` + custom:
- `prefer_const_constructors`, `prefer_const_declarations`
- `prefer_final_locals`, `prefer_single_quotes`
- `sort_child_properties_last`, `use_key_in_widget_constructors`
- `avoid_print`, `prefer_relative_imports`
- Excludes: `*.g.dart`, `*.freezed.dart`
