# LetsFLUTssh — Development Guide

## Project Overview

LetsFLUTssh — lightweight cross-platform SSH/SFTP client with GUI, written in Dart/Flutter.
Open-source alternative to Xshell/Termius, multi-platform (desktop + mobile).
Target platforms: Windows, Linux, macOS, Android, iOS.

**Predecessor:** LetsGOssh (Go/Fyne) — full feature port + improvements.
**Reference:** Termius (Flutter-based commercial SSH client) — proof that Flutter works for this domain.

## Working Agreements

### Commits

- **User commits manually** — Claude only suggests commit messages
- Format: `type: short description` (e.g. `feat: phase 1 — SSH terminal with xterm.dart`)
- Types: `feat`, `fix`, `refactor`, `docs`, `chore`
- Repository is **private** on GitHub

### Work Style

- Documentation is maintained in English (PLAN.md, README.md, CLAUDE.md)
- PLAN.md, CLAUDE.md, README.md **updated on every significant change**
- All architectural/UX patterns documented in CLAUDE.md at the time of implementation
- SSH keys accepted **both as file and text** (paste PEM) — key requirement
- Easy data transfer between devices — priority feature (`.lfs` archive format)
- Session grouping — tree with nested subfolders (e.g. `Production/Web/nginx1`)

### Post-change workflow (mandatory after every significant change)

1. **Version bump** — bump version in `pubspec.yaml` (patch for fix/feat, minor for new phase)
2. **CLAUDE.md** — update Current State and module descriptions; document **why** a decision was made
3. **README.md** — update if the change is user-visible
4. **Commit** — suggest a one-line message in `type: short description` format (user commits manually)

### Dependencies

- Always use **latest stable versions** of packages (latest pub.dev release)
- If a package has no stable release — use latest pre-release version compatible with current SDK

### Building

- `flutter run` — run (debug, current platform)
- `flutter build linux` / `flutter build windows` / `flutter build apk` / etc.
- `flutter test` — tests
- `flutter analyze` — linter

### What Not To Do

- Do not commit automatically, do not push
- Do not install packages without asking (user approves)
- Always run `flutter analyze` + `flutter test` before committing

## Tech Stack

- **Language:** Dart 3.x (null-safe)
- **Framework:** Flutter 3.x — cross-platform native rendering (Skia/Impeller)
- **SSH:** `dartssh2` ^2.15.0 — SSH2 protocol (connect, auth, shell, SFTP, port forwarding)
- **Terminal:** `xterm` ^4.0.0 — VT100/xterm terminal widget (256-color, RGB, mouse, scrollback)
- **Secure storage:** `pointycastle` ^4.0.0 — AES-256-GCM encrypted credential file (pure Dart, no OS deps)
- **File picker:** `file_picker` ^10.3.10 — native file/directory picker
- **File drop:** `desktop_drop` ^0.7.0 — OS drag&drop into app (desktop)
- **Data dir:** `path_provider` ^2.1.5 — platform-specific app data paths
- **State management:** `riverpod` ^2.x — reactive state (sessions, connections, transfers)
- **Serialization:** `json_serializable` + `freezed` — immutable models with JSON
- **Routing:** `go_router` ^14.x — declarative navigation

## Architecture

```
LetsFLUTssh/
├── lib/
│   ├── main.dart                    # Entry point, app setup, theme, routing
│   │
│   ├── core/                        # Shared foundation (no UI imports)
│   │   ├── ssh/                     # SSH client wrapper
│   │   │   ├── ssh_client.dart      # SSHConnection: connect, auth, shell, resize, keepalive
│   │   │   ├── ssh_config.dart      # SSHConfig model (host, port, user, auth params)
│   │   │   ├── known_hosts.dart     # TOFU host key verification + storage
│   │   │   ├── shell_helper.dart    # Shared SSH shell open + retry logic (desktop/mobile)
│   │   │   └── errors.dart          # AuthError, ConnectError structured types
│   │   │
│   │   ├── sftp/                    # SFTP operations wrapper
│   │   │   ├── sftp_client.dart     # SFTPService: list, upload, download, mkdir, delete, rename, chmod
│   │   │   ├── sftp_models.dart     # FileEntry, TransferProgress models
│   │   │   └── file_system.dart     # FileSystem interface (LocalFS, RemoteFS)
│   │   │
│   │   ├── transfer/               # Transfer queue manager
│   │   │   ├── transfer_manager.dart # Task queue, parallel workers, history
│   │   │   ├── transfer_task.dart   # Task model (direction, protocol, paths, progress)
│   │   │   └── transfer_history.dart # HistoryEntry model, persistence
│   │   │
│   │   ├── session/                 # Session model + persistence
│   │   │   ├── session.dart         # Session model (label, group, host, auth, etc.)
│   │   │   ├── session_store.dart   # CRUD + JSON file storage + search
│   │   │   └── session_tree.dart    # Tree structure for nested groups (Production/Web/nginx1)
│   │   │
│   │   ├── config/                  # App configuration
│   │   │   ├── app_config.dart      # Config model + defaults
│   │   │   └── config_store.dart    # Load/Save JSON from app support dir
│   │   │
│   │   ├── security/               # Credential encryption
│   │   │   └── credential_store.dart # AES-256-GCM encrypted credential storage
│   │   │
│   │   ├── connection/              # Connection lifecycle manager
│   │   │   ├── connection.dart      # Connection model (SSH client ref, state, label)
│   │   │   └── connection_manager.dart # Active connections tracking, tab association
│   │   │
│   │   └── deeplink/               # Deep link handling
│   │       └── deeplink_handler.dart # URL scheme + file open intent handler
│   │
│   ├── features/                    # Feature modules (UI + logic)
│   │   ├── terminal/                # Terminal tab
│   │   │   ├── terminal_tab.dart    # Widget: tiling container + reconnect + shortcuts
│   │   │   ├── terminal_pane.dart   # Single terminal pane (xterm + SSH shell pipe)
│   │   │   ├── tiling_view.dart     # Recursive split layout renderer
│   │   │   └── split_node.dart      # Sealed class: LeafNode | BranchNode tree
│   │   │
│   │   ├── file_browser/            # Dual-pane SFTP file browser
│   │   │   ├── file_browser_tab.dart    # Widget: split-pane (local | remote)
│   │   │   ├── file_pane.dart           # Single pane: table + path bar + navigation
│   │   │   ├── file_pane_dialogs.dart   # Shared dialogs: New Folder, Rename, Delete
│   │   │   ├── file_table.dart          # DataTable with sort, multiselect, context menu
│   │   │   ├── file_browser_controller.dart # State: listing, navigation, selection
│   │   │   ├── sftp_initializer.dart    # Shared SFTP init factory (desktop/mobile)
│   │   │   ├── transfer_panel.dart      # Bottom panel: progress + history (collapsible)
│   │   │   └── file_actions.dart        # Upload/download/delete/rename/mkdir actions
│   │   │
│   │   ├── session_manager/         # Session sidebar
│   │   │   ├── session_panel.dart   # Widget: tree view + search + actions
│   │   │   ├── session_tree_view.dart # Hierarchical session list (nested groups)
│   │   │   ├── session_edit_dialog.dart # Create/edit session dialog
│   │   │   ├── session_connect.dart # Shared connect logic (terminal/sftp/quick)
│   │   │   └── quick_connect_dialog.dart # Quick connect dialog
│   │   │
│   │   ├── settings/                # Settings screen
│   │   │   ├── settings_screen.dart # Full settings UI
│   │   │   └── export_import.dart   # Data export/import (.lfs archive)
│   │   │
│   │   └── tabs/                    # Tab management
│   │       ├── tab_bar.dart         # Custom tab bar with drag reorder
│   │       ├── tab_controller.dart  # Tab state: open, close, reorder, select
│   │       └── welcome_screen.dart  # Shown when no tabs open
│   │
│   ├── providers/                   # Riverpod providers (global state)
│   │   ├── session_provider.dart    # Session store provider
│   │   ├── connection_provider.dart # Active connections provider
│   │   ├── config_provider.dart     # App config provider
│   │   ├── transfer_provider.dart   # Transfer manager provider
│   │   └── theme_provider.dart      # Theme state (dark/light)
│   │
│   ├── widgets/                     # Reusable UI components
│   │   ├── split_view.dart          # Resizable split pane (H/V)
│   │   ├── toast.dart               # Non-blocking toast notifications
│   │   ├── context_menu.dart        # Right-click context menu helper
│   │   ├── key_field.dart           # SSH key input (file picker + PEM text + drag&drop)
│   │   └── search_field.dart        # Search/filter input
│   │
│   ├── theme/                        # App-wide theming
│   │   └── app_theme.dart           # OneDark/One Light palettes, semantic color constants
│   │
│   └── utils/                       # Utilities
│       ├── format.dart              # formatSize, formatTimestamp, formatDuration
│       ├── platform.dart            # Platform detection helpers
│       └── logger.dart              # Structured logging setup
│
├── test/                            # Unit + widget tests
│   ├── core/                        # Core logic tests
│   │   ├── session/
│   │   ├── transfer/
│   │   ├── security/
│   │   ├── config/
│   │   └── connection/
│   └── features/                    # Widget tests
│
├── assets/                          # Icons, fonts
│   └── icons/
│
├── pubspec.yaml                     # Dependencies, version
├── analysis_options.yaml            # Lint rules
├── .gitignore
├── CLAUDE.md                        # This file
├── README.md
└── PLAN.md                          # Step-by-step dev plan
```

## Key Design Principles

1. **Feature-first structure** — each feature (terminal, file_browser, session_manager) is an isolated module with UI + logic
2. **Core is UI-agnostic** — `core/` does not import Flutter; can be reused in a CLI tool
3. **Riverpod for state** — single source of truth for all state (sessions, connections, config, transfers)
4. **Immutable models** — all data classes via `freezed` (copyWith, equality, JSON serialization)
5. **FileSystem interface** — abstraction for local/remote file access (same as in LetsGOssh)
6. **No SCP** — dartssh2 doesn't support SCP; SFTP covers all use cases (file/directory upload/download with progress)
7. **Tree-based sessions** — nested groups via `/` separator (Production/Web/nginx1), stored as flat list with group path, UI builds TreeView

## Current State (v0.9.1 — Architecture refactoring)

### What works
- SSH connection via dartssh2 (password, key file, key text)
- Auth chain: key file → key text → password (same as LetsGOssh)
- **Session Manager** — session persistence in JSON, CRUD, duplicate
- **Session TreeView** — nested groups (Production/Web/nginx1), expand/collapse
- **Search/filter** — by label, group, host, user
- **Context menu** — SSH connect, SFTP connect, Edit, Delete, Duplicate (right-click)
- **Double-click** → SSH connect
- **Session Edit Dialog** — auth type selector (Password/Key/Key+Pass), group autocomplete
- **Resizable sidebar** — drag-divider between sidebar and content area
- Keep-alive via dartssh2 `keepAliveInterval`
- TOFU known hosts (auto-accept, persistent storage)
- Terminal emulation via xterm.dart (256-color, mouse, scrollback 5000 lines)
- Copy/paste built-in (xterm.dart built-in Actions: Ctrl+Shift+C/V)
- PTY resize on window resize
- Disconnect detection + Reconnect button
- Tab system (open, close, switch, IndexedStack for state preservation)
- Tab bar with state indicator (green/orange/red)
- Quick Connect dialog (host, port, user, password, key file picker, PEM text)
- Field validation in dialogs
- **OneDark theme** — Atom OneDark Pro palette (dark), One Light (light), system auto-detect
- App config (JSON persistence in app support dir)
- Status bar (connection state + tab count)
- Keyboard shortcuts: Ctrl+N (quick connect), Ctrl+W (close tab), Ctrl+Tab (next tab)
- Riverpod state management (config, connections, tabs, theme)
- Makefile (run, build, test, analyze, gen, clean)
- **SFTP File Browser** — dual-pane (local | remote) with navigation history
- **File pane** — sortable list (name/size/mode/modified), editable path bar, back/forward/up/refresh
- **Context menu** — open dir, transfer, new folder, rename, delete (single + multi-select)
- **Transfer Manager** — queue with configurable parallelism (default 2 workers)
- **Transfer Panel** — collapsible bottom panel with history (completed/failed, duration, error details)
- **SFTP toolbar button** — opens SFTP tab for active connection
- **Session context menu** — "SFTP Only" option for direct file browser connection
- **FileSystem interface** — LocalFS/RemoteFS abstraction (same as LetsGOssh)
- **Tab drag-to-reorder** — ReorderableListView, context menu (close, close others, close right)
- **Toast notifications** — overlay-based, 4 levels (info/success/warning/error), auto-dismiss, stacking
- **Settings screen** — theme, font size, scrollback, keepalive, timeout, port, transfer workers, max history, reset to defaults
- **Status bar** — connection state + transfer progress (reactive via StreamProvider)
- **Responsive layout** — sidebar → drawer on narrow screens (<600px), hamburger menu button
- **Reconnect** — error state UI with Reconnect + Close buttons
- **Secure credential storage** — AES-256-GCM encrypted file (pointycastle, pure Dart, no OS deps)
- **Credentials separated from sessions** — sessions.json has no secrets, credentials.enc with AES-256-GCM
- **Auto-migration** — plaintext credentials in sessions.json automatically migrate to encrypted store
- **Export/Import (.lfs)** — ZIP + AES-256-GCM (PBKDF2-SHA256 100k iterations), sessions + config + known_hosts
- **Import modes** — merge (add new, skip existing) / replace (overwrite all)
- **Settings UI** — Export Data / Import Data buttons with master password dialogs
- **Internal drag&drop** — Draggable + DragTarget between file browser panes, cross-pane only (same-pane drop rejected via PaneDragData identity)
- **Marquee selection** — rubber band selection from any position (5px threshold), Ctrl+click for multi-select
- **Del key** — deletes selected files in focused pane (Focus-based, not global)
- **Terminal search** — Ctrl+Shift+F, highlights matches in scrollback buffer, next/prev navigation
- **Session folder creation** — right-click context menu on groups/empty space → New Folder / New Session
- **Empty folders** — session groups persist without sessions (stored in empty_groups.json), duplicate name validation
- **Host key confirmation dialog** — SHA256 fingerprint display, Accept/Reject for unknown hosts, MITM warning for changed keys
- **Terminal right-click context menu** — Copy (selected text) / Paste from clipboard
- **Key field drag&drop** — drop .pem/.key files into session edit dialog, auto-reads PEM content
- **Auto-detect SSH keys** — tries ~/.ssh/id_ed25519, id_ecdsa, id_rsa, id_dsa (like OpenSSH) when no explicit key provided
- **Tiling terminal layout** — recursive split (vertical/horizontal) like tmux/Terminator, drag-to-resize dividers
- **Split context menu** — right-click → Split Right / Split Down / Close Pane
- **Pane focus tracking** — blue border on focused pane, click to switch focus
- **Multiple shells per connection** — each pane opens its own SSH shell on the shared Connection
- **Mobile UI** — bottom NavigationBar (Sessions / Terminal / Files), separate from desktop layout
- **SSH virtual keyboard** — Esc, Tab, Ctrl (sticky), Alt (sticky), arrows, F1-F12, |~/-/, haptic feedback
- **Mobile terminal** — full-screen, pinch-to-zoom (8-24pt), long press → copy/paste context menu
- **Mobile SFTP** — single-pane with SegmentedButton Local/Remote toggle, long-press selection mode, bottom sheet actions
- **Mobile tab switcher** — ChoiceChips for multiple terminal/SFTP tabs, badges on nav bar
- **Adaptive dialogs** — QuickConnect/SessionEdit use ConstrainedBox instead of fixed width
- **Mobile swipe navigation** — GestureDetector.onHorizontalDragEnd switches bottom nav tabs (velocity > 300)
- **Deep links** — `letsflutssh://connect?host=X&user=Y` via app_links package (Android intent filter + iOS CFBundleURLTypes)
- **File open intents** — ACTION_VIEW for .pem/.key/.pub/.lfs files (Android), open SSH keys and .lfs archives
- **Packaging** — AppImage + deb + tar.gz (Linux), EXE installer (Inno Setup) + zip (Windows), dmg + tar.gz (macOS), per-ABI APK (Android)
- **Security hardening** — chmod 600 on credential files, TOFU rejects unknown hosts without callback, PBKDF2 600k iterations, file paths removed from error messages
- **hardwareKeyboardOnly on desktop** — fixes Windows keyboard input by using KeyEvent.character instead of broken TextInputConnection/IME path
- **283 tests** — 209 unit + 67 widget + 7 deeplink; covers all core modules and major UI components; mockito mocks for SSH shell (ShellHelper)
- **User documentation** — docs/USER_GUIDE.md with keyboard shortcuts, features, security notes
- **ShellHelper** — shared SSH shell connection logic (retry, stream wiring) extracted from desktop/mobile terminal code
- **SFTPInitializer** — shared SFTP init factory (create service + controllers) used by desktop/mobile file browsers
- **FilePaneDialogs** — shared file operation dialogs (New Folder, Rename, Delete) extracted from file_pane.dart and mobile_file_browser.dart
- **SessionConnect** — shared connection logic (connectTerminal, connectSftp, quickConnect) extracted from main.dart
- **Settings screen optimized** — each section uses `ref.watch(configProvider.select(...))` for fine-grained rebuilds
- **Consistent error handling** — all silent `catch (_)` replaced with `dev.log()` logging in credential_store, config_store, sftp_client
- **chmod 600 error reporting** — credential_store now logs chmod failures instead of silently ignoring them
- **FilePaneController.dispose()** — properly calls `super.dispose()` to clean up ChangeNotifier listeners

### Decisions and Why
- **SSHConnectionState instead of ConnectionState** — name conflict with Flutter's `ConnectionState` from async.dart
- **xterm.dart built-in copy/paste** — xterm 4.0 already has Actions for CopySelectionTextIntent/PasteTextIntent, no need to implement manually
- **dartssh2 host key callback** — signature `FutureOr<bool> Function(String type, Uint8List fingerprint)`, not SSHPublicKey
- **IndexedStack for tabs** — preserves terminal state when switching between tabs
- **Flutter SDK** — installed at `/home/llloooggg/flutter-sdk` (stable 3.41.5, Dart 3.11.3)
- **dartssh2 SFTP API** — `attr.mode?.value` (not `attr.permissions?.mode`), `remoteFile.writeBytes()` (not `write()`)
- **FilePaneController as ChangeNotifier** — lightweight state for each pane, without Riverpod overhead for internal navigation state
- **TransferManager with Stream notifications** — Riverpod StreamProvider subscribes to onChange for reactive UI updates
- **pointycastle instead of encrypt** — encrypt ^5.0.3 requires pointycastle ^3.6.2, conflicts with dartssh2 (needs ^4.0.0); pointycastle is already a transitive dep
- **CredentialStore instead of flutter_secure_storage** — pure Dart, no OS-specific native deps; AES-256-GCM with random key in credentials.key
- **PBKDF2 600k iterations for .lfs** — OWASP 2024 recommendation for password-based encryption of archives
- **Listener instead of GestureDetector for marquee** — Listener (raw pointer events) doesn't participate in gesture arena, so it doesn't conflict with Draggable on file rows
- **Draggable only on selected files** — click on unselected file + drag = marquee; click on selected + drag = transfer between panes
- **PaneDragData with sourcePaneId** — DragTarget rejects drop with same paneId, preventing transfer to same pane
- **Focus-based Del** — each FilePane has a FocusNode; Del deletes only from the focused pane; focus switches on click and on drop
- **Empty groups in SessionStore** — empty folders stored in separate empty_groups.json; SessionTree.build() accepts emptyGroups for rendering
- **Global navigatorKey for host key dialog** — KnownHostsManager callbacks show Flutter dialogs via navigatorKey.currentContext, without binding to a specific widget
- **SHA256 fingerprint** — pointycastle SHA256Digest for standard format `SHA256:base64hash` (instead of hex of first 16 bytes)
- **Auto-detect SSH keys** — if keyPath and keyData are empty, try id_ed25519 → id_ecdsa → id_rsa → id_dsa from ~/.ssh/ (same order as OpenSSH)
- **Key file drop auto-reads PEM** — if dropped file < 32KB and contains "PRIVATE KEY", content is read into keyData; otherwise keyPath is set
- **Sealed class SplitNode** — Dart sealed class for recursive split tree (LeafNode | BranchNode); exhaustive switch, immutable IDs (uuid)
- **Tiling as tree** — recursive BranchNode(direction, ratio, first, second) allows arbitrary nesting depth; replaceNode/removeNode for tree mutation
- **TerminalPane vs TerminalTab** — TerminalPane = single terminal in tile (no reconnect); TerminalTab = container with tiling tree + reconnect + shortcuts
- **Each pane → own SSH shell** — openShell() called for each LeafNode, all shells on one SSHConnection; on reconnect the tree resets to a single leaf
- **OneDark theme** — centralized palette in `lib/theme/app_theme.dart`; all colors (connected/disconnected/warning/folder) via AppTheme semantic constants; no hardcoded Colors.red/green/orange
- **file_pane.dart split** — FileRow, MenuRow, MarqueePainter, PaneDragData extracted to `file_row.dart`; file_pane.dart contains only FilePane + state
- **Removed unused deps** — go_router (not used, navigation via MaterialApp), freezed_annotation (models written manually)
- **Separate features/mobile/** — desktop widgets have mouse-centric logic (marquee, right-click, drag&drop, tiling); mobile widgets are simpler but fundamentally different in interaction patterns; shared logic (SSH, SFTP, sessions) lives in core/
- **isMobilePlatform in main.dart** — on mobile, MobileShell (bottom nav) renders instead of desktop layout (sidebar + tabs + split); checked via Platform.isAndroid/isIOS
- **Sticky modifiers** — Ctrl/Alt as toggle (tap = one-shot, double-tap = lock); hold-to-activate is inconvenient on touchscreen; pattern from Termius/JuiceSSH
- **No tiling on mobile** — even on 6.7" screen, two terminals = ~35 columns, too narrow for SSH; MobileTerminalView renders one pane
- **Long-press selection** — no Ctrl+click or marquee on mobile; long press enters selection mode with checkboxes (like Android file manager)
- **AnimatedBuilder for toolbar** — MobileFileBrowser toolbar listens to FilePaneController via AnimatedBuilder for path updates on navigation
- **Focus(autofocus: true) removed from main.dart** — was stealing text input from TerminalView on Windows; backspace worked (raw key event) but letters didn't (IME/TextInputClient path)
- **hardwareKeyboardOnly: true on desktop** — xterm.dart CustomTextEdit (TextInputClient) doesn't work on Windows; CustomKeyboardListener reads KeyEvent.character directly — more reliable for desktop
- **app_links instead of uni_links** — more up-to-date package, desktop support, custom schemes + file URIs
- **TOFU reject without callback** — auto-accept removed; unknown hosts are now rejected if no UI callback exists; prevents MITM when no dialog is available
- **PBKDF2 600k iterations** — OWASP 2024 recommendation; 100k was sufficient in 2020, but GPU brute-force has gotten faster
- **chmod 600 on credential files** — prevents other users from reading credentials.enc/key on Unix systems
- **DeepLinkHandler.parseConnectUri static** — extracted from private method for testability; tests verify URI parsing without initializing app_links
- **ShellHelper static class** — extracted from TerminalPane/MobileTerminalView; retry logic + stream wiring in one place; desktop/mobile differ only in UI, not shell connection
- **SFTPInitializer factory** — creates SFTPService + FilePaneController(Local/Remote) + init(); returns SFTPInitResult with dispose(); desktop/mobile FileBrowser use identical initialization
- **FilePaneDialogs static** — New Folder/Rename/Delete dialogs were duplicated in file_pane.dart and mobile_file_browser.dart; extracted to shared class
- **SessionConnect static** — connectTerminal/connectSftp/quickConnect were duplicated three times in main.dart; extracted for reuse in mobile_shell
- **Settings sections as separate ConsumerWidget** — each section (Appearance, Terminal, Connection, Transfers) uses select() on its own fields; changing font size doesn't rebuild Transfers

### What's planned (ported from LetsGOssh + improvements)

**Ported as-is:**
- SSH connection (password, key file, key text, SSH agent)
- Known hosts (TOFU)
- Keep-alive
- Terminal emulation (xterm.dart provides out of the box: 256-color, RGB, mouse, scrollback, alternate screen)
- Session manager (CRUD, groups, search, context menu)
- SFTP file browser (dual-pane, upload/download, mkdir, delete, rename, chmod, properties)
- Transfer manager (queue, parallel workers, history)
- Drag&drop (files from OS + between panes)
- Toast notifications
- Config (theme, font size, scrollback, keepalive, etc.)
- Multiple tabs (terminal + SFTP)

**Improvements over LetsGOssh:**
- Tab drag reorder (Flutter has built-in Draggable)
- Tree view for sessions (nested groups)
- Scrollback out of the box (xterm.dart `maxLines`)
- Text selection + copy/paste out of the box (xterm.dart)
- Mouse reporting out of the box (xterm.dart)
- Smooth split-pane drag (Flutter layout doesn't lag like Fyne)
- Secure credential storage (AES-256-GCM encrypted file instead of plaintext JSON)
- Mobile support (Android, iOS) with adaptive UI
- Port forwarding UI
- Data export/import (.lfs encrypted archive)
- Settings screen

**Not ported:**
- SCP (dartssh2 doesn't support it; SFTP is sufficient)
- midterm / custom VT parser (xterm.dart handles everything)
- Custom split widget (Flutter layout is performant enough)

## Module Details

### `core/ssh`

SSH client wrapper over `dartssh2`:

- `SSHConfig`: host, port, user, password, keyPath, keyData, passphrase, keepAliveSec, timeoutSec
- `SSHConnection`:
  - `connect()` → auth → shell session
  - Auth chain: key file → key text → password → keyboard-interactive
  - `openShell(cols, rows)` → PTY + stdin/stdout streams
  - `resizeTerminal(cols, rows)`
  - `disconnect()`, `isConnected`, `onDisconnect` callback
  - Keep-alive via `SSHClient.keepAliveInterval`
- `KnownHostsManager`: TOFU verification, persistent storage at app support dir
- Structured errors: `AuthError`, `ConnectError` with cause unwrapping

### `core/sftp`

SFTP wrapper over `dartssh2` SFTP subsystem:

- `SFTPService`:
  - `list(path)` → `List<FileEntry>` (sorted: dirs first, then files)
  - `upload(localPath, remotePath, onProgress)` — file upload with progress
  - `download(remotePath, localPath, onProgress)` — file download with progress
  - `uploadDir(localDir, remoteDir, onProgress)` — recursive directory upload
  - `downloadDir(remoteDir, localDir, onProgress)` — recursive directory download
  - `mkdir(path)`, `remove(path)`, `removeDir(path)`, `rename(old, new)`, `chmod(path, mode)`, `stat(path)`, `getwd()`
- `FileSystem` interface — abstracts local (`dart:io`) and remote (SFTP) file access
  - `LocalFS`: wraps `dart:io` Directory/File operations
  - `RemoteFS`: wraps `SFTPService`
- `FileEntry`: name, path, size, mode, modTime, isDir
- `TransferProgress`: fileName, totalBytes, doneBytes, percent, isUpload, isCompleted

### `core/transfer`

Transfer queue (ported from LetsGOssh `internal/transfer`):

- `TransferManager`:
  - Configurable parallelism (default 2 workers)
  - `enqueue(task)` → returns task ID
  - `history` — completed/failed transfers
  - `clearHistory()`, `deleteHistory(ids)`
  - Auto-notify listeners (Riverpod)
- `TransferTask`: name, direction (upload/download), sourcePath, targetPath, run function
- `HistoryEntry`: id, name, direction, source, target, status, error, duration, timestamps

### `core/session`

Session management (ported from LetsGOssh `internal/session`):

- `Session`: id, label, group (path like "Production/Web"), host, port, user, authType, password, keyPath, keyData, passphrase, createdAt, updatedAt
- `SessionStore`:
  - CRUD: add, update, delete, duplicate
  - `search(query)` — by label, group, host
  - `groups()` — unique group paths
  - `byGroup(group)` — sessions in group
  - Persist to JSON file at app support dir
  - Credentials stored separately via `CredentialStore` (AES-256-GCM encrypted)
- `SessionTree`: builds tree structure from flat session list for TreeView UI
- `Session.validate()` — host required, port 1-65535, user required

### `core/config`

App configuration (ported from LetsGOssh `internal/config`):

- `AppConfig`: fontSize, theme, scrollback, keepAliveSec, defaultPort, sshTimeoutSec, toastDurationMs, transferWorkers, maxHistory, windowWidth, windowHeight
- `ConfigStore`: load/save JSON at app support dir
- Defaults: font 14, dark theme, 5000 scrollback, 30s keepalive, port 22

### `core/security`

Encrypted credential storage (pure Dart, no OS dependencies):

- `CredentialStore`: AES-256-GCM encrypted file-based storage for secrets
  - `credentials.enc` — encrypted JSON map of sessionId → CredentialData
  - `credentials.key` — 256-bit random key (generated once, stored alongside)
  - Methods: `loadAll()`, `saveAll()`, `get(id)`, `set(id, data)`, `delete(id)`
- `CredentialData`: password, keyData (PEM), passphrase
- `SessionStore` uses `CredentialStore` automatically — secrets never written to plaintext JSON
- Auto-migration: on load, if plaintext credentials found in sessions.json, migrate to encrypted store

### `features/settings/export_import`

Data portability (.lfs archive format):

- `ExportImport.export()`: sessions (with credentials) + config + known_hosts → ZIP → AES-256-GCM
- `ExportImport.import_()`: decrypt → unzip → parse → merge/replace sessions + config + known_hosts
- `ExportImport.preview()`: decrypt + list contents without applying
- Master password → PBKDF2-SHA256 (100k iterations, 32-byte salt) → 256-bit AES key
- Format: `[salt 32B] [iv 12B] [encrypted ZIP + GCM tag]`
- `ImportMode.merge` — add new sessions, skip existing (by ID)
- `ImportMode.replace` — delete all, import fresh

### `core/connection`

Connection lifecycle:

- `Connection`: label, sshConfig, sshClient (nullable), state (disconnected/connecting/connected)
- `ConnectionManager`:
  - Track active connections
  - Associate connections with tabs (1 connection → N tabs: terminal + SFTP)
  - `connect(config)`, `disconnect(id)`
  - Notify on state changes

### `features/terminal`

Terminal tab using `xterm` package:

- `TerminalTab`: `TerminalView` widget from xterm.dart, connected to SSH shell stdin/stdout
- xterm.dart provides out of the box:
  - VT100/xterm emulation (SGR, 256-color, RGB, alternate screen)
  - Scrollback (configurable `maxLines`)
  - Mouse reporting (1000/1002/1003/1006)
  - Keyboard input
- Custom additions:
  - Ctrl+Shift+C/V for copy/paste (if not built-in)
  - Right-click context menu (Copy/Paste)
  - `onResize` → SSH `resizeTerminal()`
  - Disconnect detection + reconnect UI

### `features/file_browser`

Dual-pane SFTP browser (ported from LetsGOssh `internal/ui/filebrowser`):

- Split-pane: local (left) | remote (right)
- `DataTable` with 4 columns: Name, Size, Mode, Modified — with sort headers
- Editable path bar + Back/Forward navigation
- Context menu: download/upload, rename, delete, new folder, properties
- Drag&drop between panes (Flutter `Draggable` + `DragTarget`)
- OS file drop into remote pane (`desktop_drop`)
- Multi-select (Ctrl+click / Shift+click)
- Transfer progress panel (collapsible, auto-reveal)
- History table (sortable, deletable)

### `features/session_manager`

Session sidebar (ported from LetsGOssh `internal/ui/sessionmgr`):

- TreeView with nested groups (Production/Web/nginx1)
- Search/filter bar
- Double-click → connect (SSH terminal)
- Context menu: SSH connect, SFTP only, edit, delete, duplicate
- New session / Edit session dialogs
- Quick Connect dialog

### `features/tabs`

Tab system:

- Custom tab bar with drag-to-reorder (Flutter `ReorderableListView` or custom `Draggable`)
- Tab types: Terminal, SFTP
- Close button on each tab
- Context menu: close, close others, reconnect
- Keyboard: Ctrl+Tab, Ctrl+1..9
- Welcome screen when no tabs

### `features/settings`

Settings screen:

- Theme (dark/light/system)
- Font size
- Scrollback lines
- Keep-alive interval
- Default port
- Transfer parallelism
- Data export/import

### `widgets/`

Reusable components:

- `SplitView`: resizable split (H/V) with draggable divider
- `Toast`: non-blocking notification (info/warning/error/success)
- `ContextMenu`: right-click popup menu helper
- `KeyField`: SSH key input widget (file picker, PEM text area, drag&drop)
- `SearchField`: filtered input with debounce

## Conventions

- Use `dart:developer` `log()` for structured logging
- Error wrapping: custom exception classes with `cause` field
- No global mutable state — all state via Riverpod providers
- UI updates automatic via Riverpod (no manual setState except in leaf widgets)
- Models: `freezed` for immutability + `json_serializable` for JSON
- Passwords/keys: stored in `CredentialStore` (AES-256-GCM encrypted file), NOT in plain JSON
- Test files: `*_test.dart` next to source or in `test/` mirror tree
- Lint rules: `flutter_lints` + additional (prefer_const_constructors, etc.)
- Platform-specific code: isolated behind `Platform.isX` checks or separate files

## Key Differences from LetsGOssh

| Aspect | LetsGOssh (Go/Fyne) | LetsFLUTssh (Dart/Flutter) |
|--------|---------------------|---------------------------|
| Terminal widget | Custom on vito/midterm (patched) | xterm.dart (maintained, feature-complete) |
| Scrollback | Manual OnScrollback patch | Built-in `maxLines` |
| Mouse reporting | Manual CSI parser | Built-in `mouseMode` |
| Text selection | Custom overlay | Built-in (xterm.dart) |
| Split pane | Custom throttled widget (60fps hack) | Flutter layout (no jank) |
| Tab reorder | Not implemented (Fyne limitation) | Built-in Draggable |
| Session tree | Flat groups only | Nested TreeView |
| Credential storage | Plain JSON | AES-256-GCM encrypted file (pointycastle) |
| SCP | Supported | Not needed (SFTP covers all) |
| Mobile | Fyne mobile (very raw) | Flutter mobile (production-ready) |
| Community | ~8k stars (Fyne) | ~170k stars (Flutter) |
| RAM usage | ~50-70 MB | ~90-120 MB |
| Binary size | ~10-15 MB | ~15-25 MB |

## Migration Notes

### What transfers directly (logic/algorithms)

- SSH auth chain logic (password → key → agent fallback order)
- Known hosts TOFU algorithm
- Session model fields and validation rules
- Transfer queue/worker pattern
- File browser navigation (path history, back/forward)
- Config structure and defaults
- FileSystem interface pattern (LocalFS/RemoteFS)
- Context menu item structure

### What needs rewrite (platform-specific)

- All UI code (Fyne widgets → Flutter widgets)
- SSH client calls (x/crypto/ssh → dartssh2 API)
- SFTP client calls (pkg/sftp → dartssh2 SFTP API)
- File I/O (Go os package → Dart dart:io)
- State management (Go mutexes/channels → Riverpod)
- Concurrency (goroutines → Dart isolates/async)
- Build system (Makefile → flutter CLI / pubspec.yaml)
