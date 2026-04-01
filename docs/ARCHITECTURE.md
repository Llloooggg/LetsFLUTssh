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
│   ├── connection/                   # Connection lifecycle management
│   ├── security/                     # AES-256-GCM credential storage
│   ├── config/                       # App configuration
│   ├── deeplink/                     # Deep link handling
│   ├── import/                       # Data import (.lfs, key files)
│   └── update/                       # Update checking
├── features/                         # UI modules
│   ├── terminal/                     # Terminal with tiling
│   ├── file_browser/                 # Dual-pane SFTP browser
│   ├── session_manager/              # Session management panel
│   ├── tabs/                         # Tab system
│   ├── settings/                     # Settings + export/import
│   └── mobile/                       # Mobile version (bottom nav)
├── providers/                        # Riverpod providers (global state)
├── widgets/                          # Reusable UI components
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
| `known_hosts.dart` | `KnownHostsManager` | TOFU: host key verification, fingerprint storage, callback on unknown/changed |
| `shell_helper.dart` | `openShellWithRetry()` | Shared SSH shell open logic with retry (for desktop and mobile) |
| `errors.dart` | `ConnectError`, `AuthError`, `HostKeyError` | Typed SSH error hierarchy |

#### SSHConnection — lifecycle

```dart
class SSHConnection {
  // DI hooks for testing
  SSHConnection({socketFactory, clientFactory});

  Future<void> connect(SSHConfig config, {onHostKey});
  // 1. TCP socket (via socketFactory)
  // 2. SSH handshake (via clientFactory)
  // 3. Auth chain: keyFile → keyText → password → interactive
  // 4. Host key verification (callback)
  // 5. Keep-alive if keepAliveSec > 0

  Future<SSHSession> openShell({int cols, int rows});
  void resizeTerminal(int cols, int rows);
  void disconnect();

  SSHClient? get client;        // dartssh2 client
  bool get isConnected;
}
```

#### Auth chain — attempt order

```
1. keyPath → read file, parse PEM → SSHKeyPair
2. keyData → parse PEM string → SSHKeyPair
3. password → SSHPasswordAuth
4. interactive → keyboard-interactive prompt (fallback)
Each step is skipped if the parameter is empty.
On failure of any step → AuthError.
```

#### KnownHostsManager

```dart
class KnownHostsManager {
  KnownHostsManager(String knownHostsPath);

  FutureOr<bool> verify(String host, int port, String type, Uint8List fingerprint);
  // → true: key matches / user accepted
  // → false: user rejected / key changed and rejected

  // Callbacks (invoked via global navigatorKey):
  // onUnknownHost → HostKeyDialog.showNewHost()
  // onHostKeyChanged → HostKeyDialog.showKeyChanged()
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
  String get separator;
}

class LocalFS implements FileSystem { ... }   // dart:io
class RemoteFS implements FileSystem { ... }  // SFTPService wrapper
```

**Why an interface:** Allows FilePaneController to work identically with local and remote panes. Simplifies testing — mocks can be substituted.

---

### 3.3 Transfer Queue (`core/transfer/`)

#### Files and responsibilities

| File | Class | Purpose |
|------|-------|---------|
| `transfer_manager.dart` | `TransferManager` | Task queue, parallel workers, history, cancellation |
| `transfer_task.dart` | `TransferTask`, `TransferDirection` | Task model (name, direction, paths, size, run callback) |
| `transfer_history.dart` | `HistoryEntry` | History entry (name, direction, size, duration, error, timestamp) |

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
  TransferManager({int workers = 2, int maxHistory = 500});

  String enqueue(TransferTask task);          // returns task ID
  void cancel(String taskId);
  void cancelAll();
  void clearHistory();

  Stream<List<TransferTask>> get activeStream;
  Stream<List<HistoryEntry>> get historyStream;
  ({int running, int queued}) get status;
}
```

**Cancellation:** Marks the task as cancelled; on the next progress callback invocation the flag is checked and CancelException is thrown.

---

### 3.4 Session Management (`core/session/`)

#### Files and responsibilities

| File | Class | Purpose |
|------|-------|---------|
| `session.dart` | `Session`, `ServerAddress`, `SessionAuth`, `AuthType` | Session model with all fields |
| `session_store.dart` | `SessionStore` | CRUD, JSON persistence, search, groups, plaintext→encrypted migration |
| `session_tree.dart` | `SessionTree`, `TreeNode` | Hierarchical tree built from flat session list |
| `session_history.dart` | `SessionHistory` | Undo/redo snapshots (stores credentials separately) |
| `qr_codec.dart` | `QrCodec` | Session encoding/decoding for QR (no secrets, max ~2000 bytes) |

#### Session model

```dart
class Session {
  final String id;            // UUID
  final String label;         // display name
  final String group;         // folder path: "Production/Web" (separator /)
  final ServerAddress server; // host, port, user
  final SessionAuth auth;     // authType, password, keyPath, keyData, passphrase
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool incomplete;      // true when imported via QR without credentials

  SSHConfig toSSHConfig();    // conversion for connection
  Session copyWith({...});
  Map<String, dynamic> toJson();
  factory Session.fromJson(Map<String, dynamic> json);
}
```

#### SessionStore — persistence

```
sessions.json  ← metadata (label, group, host, port, user, timestamps)
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
  List<Session> search(String query);  // by label, group, host, user

  List<String> get groups;        // all unique groups
  List<String> get emptyGroups;   // groups without sessions
  void addEmptyGroup(String path);
  void renameGroup(String oldPath, String newPath);
  void deleteGroup(String path);
}
```

**Safety on load:** If CredentialStore fails to decrypt — skips credential merge instead of overwriting. Prevents loss of encrypted data.

#### SessionTree

```dart
class SessionTree {
  static List<TreeNode> build(List<Session> sessions, List<String> emptyGroups);
  // Builds hierarchy: "Production/Web/nginx" → [Production] → [Web] → [nginx]
  // Empty group folders are included in the tree
}

sealed class TreeNode {
  final String name;
  final String path;   // full path from root
}
class FolderNode extends TreeNode {
  List<TreeNode> children;
}
class SessionNode extends TreeNode {
  Session session;
}
```

---

### 3.5 Connection Lifecycle (`core/connection/`)

#### Files and responsibilities

| File | Class | Purpose |
|------|-------|---------|
| `connection.dart` | `Connection` | Connection model (id, label, sshConnection, state, error, ready completer) |
| `connection_manager.dart` | `ConnectionManager` | Active connection management, creation, disconnection, stream |
| `foreground_service.dart` | `ForegroundServiceManager` | Android: foreground service for SSH keep-alive on screen lock |

#### Connection model

```dart
class Connection {
  final String id;           // UUID (tab-specific)
  final String label;
  SSHConfig sshConfig;       // mutable — refreshed from session store on reconnect
  final String? sessionId;   // links back to saved Session (null for quick-connect)
  SSHConnection? sshConnection;
  SSHConnectionState state;  // disconnected | connecting | connected
  String? connectionError;

  Future<void> waitUntilReady();   // waits for connect attempt to finish (success or error)
  void completeReady();            // called by ConnectionManager
}
```

**Deferred Init pattern:** Connection is created instantly in state=`connecting`. The actual SSH handshake runs in the background. UI immediately opens a tab and shows a connecting indicator.

#### ConnectionManager

```dart
class ConnectionManager {
  ConnectionManager({KnownHostsManager? knownHosts, connectionFactory});

  Future<Connection> connectAsync(SSHConfig config, {String? label, String? sessionId});
  void disconnect(String connectionId);
  void disconnectAll();

  List<Connection> get connections;
  Stream<List<Connection>> get onChange;
  int get activeCount;   // connections in state connected
}
```

#### ForegroundServiceManager (Android only)

```dart
abstract class ForegroundServiceManager {
  static ForegroundServiceManager create();
  // Android → _AndroidForegroundService
  // Other platforms → _NoOpForegroundService

  void updateConnectionCount(int count);
  // count > 0 → starts foreground service with notification
  // count == 0 → stops service
}
```

**Why foreground service:** Android kills background processes. Without a foreground service, SSH connections drop on screen lock or app switch.

---

### 3.6 Security & Encryption (`core/security/`)

#### CredentialStore

```dart
class CredentialStore {
  CredentialStore(String dataDir);

  Future<Map<String, CredentialData>> load();
  Future<void> save(Map<String, CredentialData> data);

  // Internals:
  // - Encryption key: 32 bytes random, stored in separate file
  // - Algorithm: AES-256-GCM (pointycastle)
  // - File format: [IV 12B] [ciphertext] [GCM auth tag 16B]
  // - Guard: Completer prevents race condition during key generation
}

class CredentialData {
  final String? password;
  final String? keyData;      // PEM text
  final String? passphrase;
}

class CredentialStoreException {
  // Distinguishes "no credentials" from "corrupt key/file"
}
```

**Why pointycastle:** `encrypt` package has version conflicts with dartssh2. pointycastle is pure Dart, transitive dependency via dartssh2.

**Why not flutter_secure_storage:** Needs pure Dart (cross-platform). flutter_secure_storage depends on OS keychain — different behavior across platforms.

---

### 3.7 Configuration (`core/config/`)

#### AppConfig model

```dart
class AppConfig {
  final TerminalConfig terminal;
  //   fontSize: 6-72 (default 14)
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

  final int transferWorkers;      // 1+ (default 2)
  final int maxHistory;           // ≥0 (default 500)
  final bool enableLogging;
  final bool checkUpdatesOnStart;
  final String? skippedVersion;
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
  // .lfs files: app_links file open intent
  // .pem/.key files: file open intent

  // Validation:
  // - path traversal rejection (../)
  // - scheme whitelist
  // - host/port validation
}
```

---

### 3.9 Import (`core/import/`)

| File | Purpose |
|------|---------|
| `import_service.dart` | Import .lfs archives (ZIP + AES-256-GCM, PBKDF2 600k iterations) |
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
}
```

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
│sessionProvider│  │  configProvider  │  │    tabProvider     │
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
| `sessionStoreProvider` | Provider | — | Singleton SessionStore |
| `sessionProvider` | NotifierProvider | sessionStoreProvider | Session CRUD + undo/redo |
| `sessionTreeProvider` | Provider | sessionProvider | Hierarchical tree |
| `filteredSessionsProvider` | Provider | sessionProvider, sessionSearchProvider | Filtered session list |
| `sessionSearchProvider` | StateProvider | — | Search query string |
| `configStoreProvider` | Provider | — | Singleton ConfigStore |
| `configProvider` | NotifierProvider | configStoreProvider | Configuration + sync logger |
| `themeModeProvider` | Provider | configProvider | ThemeMode (dark/light/system) |
| `knownHostsProvider` | Provider | — | KnownHostsManager |
| `connectionManagerProvider` | Provider | knownHostsProvider | ConnectionManager singleton |
| `connectionsProvider` | StreamProvider | connectionManagerProvider | Real-time connection list |
| `transferManagerProvider` | Provider | — | TransferManager singleton |
| `activeTransfersProvider` | StreamProvider | transferManagerProvider | Active/queued tasks |
| `transferHistoryProvider` | StreamProvider | transferManagerProvider | Completed transfer history |
| `transferStatusProvider` | Provider | transferManagerProvider | (running, queued) counts |
| `tabProvider` | NotifierProvider | — | Open tabs |
| `updateProvider` | Provider | — | UpdateService |
| `versionProvider` | FutureProvider | — | Current version from package_info_plus |

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
  ├── await connection.waitUntilReady()
  ├── shell = connection.sshConnection.openShell(cols, rows)
  ├── xterm Terminal() ← pipe ← shell.stdout
  │                    → pipe → shell.stdin
  ├── resize → connection.resizeTerminal(cols, rows)
  └── hardwareKeyboardOnly: true (on desktop)
```

**Why `hardwareKeyboardOnly: true` on desktop:** xterm TextInputClient is broken on Windows — causes input duplication.

---

### 5.2 File Browser (`features/file_browser/`)

#### Files

| File | Class | Purpose |
|------|-------|---------|
| `file_browser_tab.dart` | `FileBrowserTab` | Dual-pane container: local + remote |
| `file_pane.dart` | `FilePane` | Single pane: table + path bar + navigation |
| `file_pane_dialogs.dart` | — | Dialogs: New Folder, Rename, Delete |
| `file_row.dart` | `FileRow` | Row in the file table |
| `file_browser_controller.dart` | `FilePaneController` | Pane state: listing, navigation, selection, sort |
| `sftp_initializer.dart` | `SFTPInitializer` | SFTP initialization factory (injectable) |
| `transfer_panel.dart` | `TransferPanel` | Bottom panel: progress + history |
| `transfer_helpers.dart` | — | Transfer helper functions |
| `file_actions.dart` | — | Upload/download/delete/rename/mkdir actions |

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
| `session_panel.dart` | `SessionPanel` | Sidebar: tree view + search + actions + bulk select |
| `session_tree_view.dart` | `SessionTreeView` | Hierarchical list with drag & drop |
| `session_edit_dialog.dart` | `SessionEditDialog` | Create/edit session form |
| `session_connect.dart` | `SessionConnect` | Connection logic: Session → SSHConfig → ConnectionManager |
| `quick_connect_dialog.dart` | `QuickConnectDialog` | Quick connect without saving |
| `qr_display_screen.dart` | `QrDisplayScreen` | QR code display for session |
| `qr_export_dialog.dart` | `QrExportDialog` | Session selection for QR export |

#### SessionConnect — flow

```dart
class SessionConnect {
  // Terminal:
  static Future<void> connectTerminal(Session session, WidgetRef ref) {
    // 1. Session → SSHConfig (with credentials from CredentialStore)
    // 2. connectionManager.connectAsync(config)
    // 3. tabProvider.addTerminalTab(connection)
  }

  // SFTP:
  static Future<void> connectSftp(Session session, WidgetRef ref) {
    // 1-2. Same as above
    // 3. tabProvider.addSftpTab(connection)
  }
}
```

---

### 5.4 Tab System (`features/tabs/`)

#### Files

| File | Class | Purpose |
|------|-------|---------|
| `tab_bar.dart` | `AppTabBar` | Custom tab bar with drag-reorder; end drop zone fills remaining space |
| `tab_controller.dart` | `TabNotifier` | State: open, close (+ disconnect orphaned), reorder, select |
| `tab_model.dart` | `TabEntry`, `TabKind` | Tab model (id, label, connection, kind) |
| `welcome_screen.dart` | `WelcomeScreen` | Minimal empty state — icon, heading, subtitle; no buttons or shortcuts |

#### TabEntry model

```dart
class TabEntry {
  final String id;          // UUID
  final String label;
  final Connection connection;
  final TabKind kind;       // terminal | sftp
}
```

**IndexedStack:** Tabs are rendered via `IndexedStack` — all tabs stay in memory, only the current one is visible. This preserves terminal state when switching tabs.

**Connection lifecycle:** When all tabs referencing a connection are closed, `TabNotifier` automatically disconnects the orphaned connection via `ConnectionManager.disconnect()`. This keeps the active session count accurate.

---

### 5.5 Settings (`features/settings/`)

| File | Class | Purpose |
|------|-------|---------|
| `settings_screen.dart` | `SettingsScreen` | Mobile-only route (collapsible sections in a scrollable list) |
| `settings_screen.dart` | `SettingsSidebar` | Desktop nav panel — embedded in `AppShell`'s sidebar slot |
| `settings_screen.dart` | `SettingsContent` | Desktop content pane — embedded in `AppShell`'s body slot |
| `export_import.dart` | — | Export/import .lfs archives (UI + logic) |

**Desktop:** Settings are embedded directly in `MainScreen` via `ShellMode`. The toolbar settings button toggles between `ShellMode.sessions` and `ShellMode.settings` — no route navigation. `SettingsSidebar` + `SettingsContent` replace the session panel and tab area while sharing the same `AppShell` frame (sidebar width preserved).

**Mobile:** `SettingsScreen` is pushed as a route with collapsible `ExpansionTile` sections.

---

### 5.6 Mobile (`features/mobile/`)

| File | Class | Purpose |
|------|-------|---------|
| `mobile_shell.dart` | `MobileShell` | Bottom navigation: Sessions / Terminal / SFTP |
| `mobile_terminal_view.dart` | `MobileTerminalView` | Full-screen terminal + keyboard bar |
| `mobile_file_browser.dart` | `MobileFileBrowser` | Single-pane SFTP (toggle local/remote) |
| `ssh_keyboard_bar.dart` | `SshKeyboardBar` | Quick access panel: Ctrl, Alt, arrows, Fn. Main row is horizontally scrollable (`ListView`); Fn button is fixed at right edge |
| `ssh_key_sequences.dart` | — | Escape sequences for keys |

**Architectural difference:** Mobile is NOT a responsive version of desktop. It's a separate `features/mobile/` module with different interaction patterns (bottom nav instead of sidebar+tabs, long-press instead of right-click, swipe navigation).

**Shared styling with desktop:** Mobile tab chips match desktop's rectangular tab style (top accent bar, colored icons — blue for terminal, yellow for SFTP, connection status dot). SSH↔SFTP companion buttons (`_MobileCompanionButton`) mirror desktop's `_companionButton` styling (colored background, border, icon + label). Active/saved session count is shown only in the global header bar (not duplicated in the session panel footer).

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
Desktop layout shell shared by the main screen and settings. Provides the consistent visual frame: decorated toolbar (surfaceContainerLow + bottom border), resizable sidebar with drag divider, main body area, and optional status bar. On narrow viewports, set `useDrawer: true` to render the sidebar as a pull-out `Drawer` instead of an inline panel.

State class `AppShellState` exposes `sidebarWidth` getter. Sidebar width is managed internally and persists as long as the widget stays mounted.

### ClippedRow

Drop-in `Row` replacement that clips overflowing children instead of showing yellow-and-black debug stripes. Extends `Flex` with `direction: Axis.horizontal` and `clipBehavior: Clip.hardEdge`. Use in any row whose parent can be resized (sidebar, split panes, column headers, status bars).

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
**Replaces `MouseRegion` + `GestureDetector` + `setState(_hovered)`.** Exception: `context_menu.dart` (keyboard nav state).

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
**Replaces bare `Divider(height: 1)` everywhere.** Standardises height (1 px), thickness (1 px), and color. Use `.indented()` for group separators in menus.

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

### HostKeyDialog

```dart
HostKeyDialog.showNewHost(context, {host, port, keyType, fingerprint})    → Future<bool>
HostKeyDialog.showKeyChanged(context, {host, port, keyType, fingerprint}) → Future<bool>
```
TOFU dialogs: new host / key changed.

### ConfirmDialog

```dart
ConfirmDialog.show(context, {
  required String title,
  required Widget content,
  String confirmLabel = 'Delete',
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
  void log(String message, {String? name, Object? error});
  Future<String> readLog();
  Future<void> dispose();
  Future<void> clearLogs();
}
```
File: `<appSupportDir>/logs/letsflutssh.log`. Rotation: 5 MB, 3 files.

**Rule:** `AppLogger.instance.log(message, name: 'Tag')` everywhere. Never `print()` / `debugPrint()`. Never log sensitive data.

### FileUtils

```dart
Future<void> writeFileAtomic(String path, String content);
Future<void> writeBytesAtomic(String path, List<int> bytes);
void restrictFilePermissions(String path);  // chmod 600
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
String sanitizeError(Object error);   // strips OS-locale text, handles SSHError chain, 43 errno codes (POSIX + Winsock)
```

---

## 8. Theme System

### AppTheme

Brightness-aware: all getters return the appropriate color based on current `_brightness`.

```dart
abstract final class AppTheme {
  static void setBrightness(Brightness brightness);
  static bool get isDark;

  // Backgrounds (dark → light)
  static Color get bg0;     // toolbar, status bar      (dark: #1B1D23)
  static Color get bg1;     // sidebar, dialogs         (dark: #1E2127)
  static Color get bg2;     // main content             (dark: #282C34)
  static Color get bg3;     // inputs, rows             (dark: #2C313A)
  static Color get bg4;     // hover on bg3             (dark: #333842)

  // Foreground
  static Color get fg;       // main text               (dark: #ABB2BF)
  static Color get fgDim;   // secondary text
  static Color get fgFaint; // disabled text
  static Color get fgBright;// emphasized text

  // Semantic colors
  static Color get accent, blue, green, red, yellow, orange, cyan, purple;
  static Color get border, borderLight, selection, hover, active;

  // Connection status
  static Color connected;          // green
  static Color connecting;         // yellow
  static Color disconnected;       // red

  // Special
  static Color folderIcon;         // yellow
  static Color searchHighlight;    // bright yellow

  // Section border helpers (brightness-aware)
  static BorderSide get borderSide;  // BorderSide(color: border)
  static Border get borderTop;       // Border(top: borderSide)
  static Border get borderBottom;    // Border(bottom: borderSide)

  // Border radius scale
  static const radiusSm;  // 4 px — inputs, buttons, small elements
  static const radiusMd;  // 6 px — cards, containers, default rounding
  static const radiusLg;  // 8 px — toasts, mobile elements, larger containers

  // Theme factory
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

**Rule:** Never use hardcoded `fontSize` numeric literals — always use `AppFonts.xs`, `AppFonts.sm`, etc. The constants are platform-aware: mobile gets +2 px automatically for touch readability.

**Rule:** Never use hardcoded `BorderRadius.circular(N)` or `BorderRadius.zero` — always use `AppTheme.radiusSm`, `radiusMd`, or `radiusLg`. Exception: pill-shaped elements (e.g. toggle tracks) that need full rounding.

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
  1. SSHConnection.connect()          │
     ├── TCP socket                   ▼
     ├── SSH handshake       UI: tabProvider.addTerminalTab(connection)
     ├── Auth chain                   │
     └── Host key verify              ▼
  2. Success:                TerminalTab → await connection.waitUntilReady()
     ├── state = connected            │
     └── completeReady()              ▼
  3. Failure:                TerminalPane → openShell() → xterm pipe
     ├── connectionError = msg
     ├── state = disconnected
     └── completeReady()
```

**Reconnect flow:** When a terminal tab reconnects (user clicks "Reconnect" after disconnect), `TerminalTab._refreshConfig()` re-reads the `Session` from `sessionProvider` using `Connection.sessionId` and updates `Connection.sshConfig` before creating a new `SSHConnection`. This ensures reconnect picks up any session edits (e.g. added keys, changed password). Quick-connect tabs (`sessionId == null`) use the original config.

### 9.2 SFTP Init Flow

```
FileBrowserTab.initState()
         │
         ├── await connection.waitUntilReady()
         │
         ▼
SFTPInitializer.init(connection)
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
  group: String           // folder path: "Production/Web" (/ separator)
  server: ServerAddress {
    host: String
    port: int             // default 22
    user: String
  }
  auth: SessionAuth {
    authType: AuthType    // password | key | keyWithPassword
    password: String      // empty if not password auth
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
  sshConnection: SSHConnection?
  state: SSHConnectionState  // disconnected | connecting | connected
  connectionError: String?
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
  id: String              // UUID (assigned by manager)
  name: String            // display name
  direction: TransferDirection  // upload | download
  sourcePath: String
  targetPath: String
  sizeBytes: int
  state: TaskState        // queued | running | completed | failed | cancelled
  progress: double        // 0.0 - 1.0
  error: String?
  run: Future<void> Function(ProgressCallback)
}
```

### AppConfig

```dart
AppConfig {
  terminal: TerminalConfig {
    fontSize: int         // 6-72, default 14
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
  }
  transferWorkers: int    // 1+, default 2
  maxHistory: int         // ≥0, default 500
  enableLogging: bool
  checkUpdatesOnStart: bool
  skippedVersion: String?
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
| Home directory | `HOME` / `USERPROFILE` | `EXTERNAL_STORAGE` / `/storage/emulated/0` |
| Drag & drop | desktop_drop + inter-pane | None |
| Deep links | `app_links` (URL scheme) | `app_links` (URL scheme + file intents) |
| Font scaling | UI scale in settings | Pinch-to-zoom terminal |

### Android specifics

- `MANAGE_EXTERNAL_STORAGE` permission for file access
- `flutter_foreground_task` for keep-alive on screen lock
- APK split per ABI: arm64-v8a, armeabi-v7a, x86_64

### iOS specifics

- `NSLocalNetworkUsageDescription` required for local TCP
- No foreground service (iOS background modes)
- Sandbox file access

### Desktop window constraints

All desktop platforms enforce a minimum window size of **480 × 360** logical pixels to prevent layout overflow:

| Platform | File | Mechanism |
|----------|------|-----------|
| Windows | `windows/runner/win32_window.cpp` | `WM_GETMINMAXINFO` with DPI scaling |
| Linux | `linux/runner/my_application.cc` | `gtk_window_set_geometry_hints` (`GDK_HINT_MIN_SIZE`) |
| macOS | `macos/Runner/MainFlutterWindow.swift` | `NSWindow.contentMinSize` |

Additionally, internal resizable elements (sidebar, file browser columns, split panes) use overflow-safe patterns:
- **`ClippedRow`** (`widgets/clipped_row.dart`): drop-in `Row` replacement that clips overflow via `Flex(clipBehavior: Clip.hardEdge)`. Used in file browser rows, column headers, breadcrumb paths, connection bar, and transfer panel
- **Sidebar text** (`_SidebarFooter`, `_PanelHeader`, session tree rows): `Flexible` / `Expanded` with `TextOverflow.ellipsis`
- **Welcome screen**: `SingleChildScrollView` prevents vertical overflow on small windows

### Windows specifics

- `hardwareKeyboardOnly: true` — xterm TextInputClient bug
- Inno Setup for EXE installer
- `USERPROFILE` for home directory

---

## 13. Security Model

### Credential encryption

```
credential.key (32 bytes, random)
         │
         ▼ AES-256-GCM
credentials.enc = [IV 12B] [ciphertext(JSON)] [GCM tag 16B]
```

- Key generated once, stored alongside (protection: file permissions)
- Completer guard prevents race condition during parallel key generation
- `CredentialStoreException` distinguishes "no data" from "corrupt key"

### .lfs export

```
[salt 32B] [IV 12B] [AES-256-GCM(ZIP(sessions.json + credentials.json))]

Key = PBKDF2-SHA256(password, salt, 600000 iterations)
```

### TOFU (Trust On First Use)

- New host → dialog with SHA256 fingerprint → user accepts/rejects
- Changed key → warning dialog → user accepts/rejects
- Without callback → reject (fail-safe)
- known_hosts: chmod 600

### Deep link validation

- URL scheme whitelist
- Path traversal rejection (`../`)
- Host/port sanitization

### Error sanitization

- `sanitizeError()` translates OS-locale error text to English using errno codes
- Handles `SSHError` chain: preserves English `message`, sanitizes `cause` recursively
- 43 errno codes mapped (30 POSIX/Linux + 13 Windows Winsock)
- Unknown errno → original OS text preserved as-is
- Applied in: `ConnectionManager`, `TerminalTab.reconnect()`, `TransferManager` (+ path stripping)

---

## 14. Testing Patterns & DI Hooks

### Injectable factories

| Class | DI parameter | Purpose |
|-------|------------|---------|
| `SSHConnection` | `socketFactory`, `clientFactory` | Mock TCP/SSH |
| `ConnectionManager` | `connectionFactory` | Mock connection creation |
| `TerminalTab` | `reconnectFactory` | Mock reconnect logic |
| `FileBrowserTab` | `sftpInitFactory` | Mock SFTP initialization |
| `ForegroundServiceManager` | `create()` factory | Platform-specific impl |

### Platform overrides

```dart
debugMobilePlatformOverride = true;    // force mobile layout in tests
debugDesktopPlatformOverride = true;   // force desktop layout in tests
```

### Test file mapping

Rule: **one test file per source file** (`lib/core/ssh/ssh_client.dart` → `test/core/ssh/ssh_client_test.dart`). No `_extra_test.dart` files.

### Mock generation

Uses `mockito` + `@GenerateMocks`. Generated mocks: `*.mocks.dart`.

---

## 15. CI/CD Pipeline

### 15.1 Branching Model

Two branches: **`dev`** (daily work) and **`main`** (releases only).

- All app development happens on `dev`. Push freely — CI, SonarCloud, OSV-Scanner run on every push. No tags, no builds, no releases.
- To release: merge `dev` → `main`. Everything is automatic: CI → auto-tag → build → release.
- Never push app changes directly to `main`. Dependabot PRs and CI/docs-only fixes are exceptions.

### 15.2 Workflow Graph

```
push to dev (daily work)
  │
  ├─► ci.yml              (paths: lib/, test/, pubspec.*)
  │     analyze + test + coverage
  │           │
  │           └─► sonarcloud.yml    (workflow_run[CI])
  │                 quality scan on dev branch
  │
  ├─► osv-scanner.yml      (paths: pubspec.*)
  ├─► codeql.yml           (paths: .github/**)
  └─► (no tags, no builds, no releases)

merge dev → main (release)
  │
  ├─► ci.yml               (analyze + test + coverage)
  │     │
  │     ├─► sonarcloud.yml  (quality scan — badges point here)
  │     │
  │     └─► auto-tag.yml    (workflow_run[CI])
  │           reads version from pubspec.yaml
  │           tag exists → skip / new version → create tag
  │                 │
  │                 └─► build.yml      (tags: v*)
  │                       preflight: CI on SHA? yes → check / no → trigger ci.yml
  │                       → build all platforms
  │                       → GitHub Release + SLSA attestation
  │
  ├─► scorecard.yml        (OpenSSF Scorecard)
  └─► codeql.yml           (Actions analysis)

Dependabot PR merged (into main)
  │
  └─► dependabot-release.yml → patch bump → commit
        └─► ci.yml → dependabot-tag.yml → build.yml → Release

Manual build
  │
  └─► gh workflow run build.yml
        preflight: no CI on SHA → triggers ci.yml → waits → build

Non-code PR (docs/test/ci)
  └─► ci-skip.yml → success for required checks (no tag, no release)
```

### 15.3 Workflow Catalog

| Workflow | Trigger | Branches | Purpose | Blocks release? |
|----------|---------|----------|---------|-----------------|
| `ci.yml` | push/PR (lib/, test/, pubspec.*) | main, dev | analyze + test + coverage | Yes (required) |
| `ci-skip.yml` | PR (non-code paths) | main, dev | No-op success for required checks | — |
| `auto-tag.yml` | workflow_run[CI] success | main only | Reads version, creates tag if new | — |
| `build.yml` | push tag v* / manual | — | Preflight (triggers CI if missing) + build all platforms + release | — |
| `sonarcloud.yml` | workflow_run[CI] / manual | main, dev | Quality + coverage scan | No (warn-only) |
| `osv-scanner.yml` | push pubspec.* / weekly | main, dev | CVE scan (pubspec.lock) | No (optional in preflight) |
| `scorecard.yml` | push main / weekly | main | OpenSSF supply chain assessment | No |
| `codeql.yml` | push .github/ / weekly | main, dev | GitHub Actions analysis | No |
| `dependabot-release.yml` | PR closed (dependabot) | main | Patch bump after dep merge | — |
| `dependabot-tag.yml` | workflow_run[CI] + chore(deps) | main | Tag after dep bump | — |
| `dependabot-automerge.yml` | PR (dependabot) | main | Auto-merge patch/minor | — |

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

#### Release

| Target | Purpose |
|--------|---------|
| `make tag` | Manual fallback: validate CI + create tag + push |

---

## 16. Design Decisions & Rationale

### 16.1 Architecture Choices

| Decision | Why |
|----------|-----|
| `pointycastle` instead of `encrypt` | Version conflict with dartssh2 |
| `CredentialStore` instead of `flutter_secure_storage` | Pure Dart, no OS deps, cross-platform |
| `app_links` instead of `uni_links` | Desktop support |
| `FilePaneController` as `ChangeNotifier` | Lightweight per-pane state, Riverpod overhead not justified |
| Sealed class `SplitNode` | Recursive split tree with type safety |
| Each terminal pane → own SSH shell | Shared `SSHConnection`, independent shells |
| `Listener` for marquee | Raw pointer events don't conflict with `Draggable` |
| `IndexedStack` for tabs | Preserves terminal state when switching tabs |
| Separate `features/mobile/` | Different interaction patterns, not a responsive adaptation |
| Global `navigatorKey` for host key dialog | SSH callback arrives without BuildContext |
| `AnimationStyle.noAnimation` | Animations disabled (Flutter 3.41+), design decision |

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
| `flutter_launcher_icons` | App icon gen |

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
