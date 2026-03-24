# LetsFLUTssh — Development Guide

## Project Overview

LetsFLUTssh — lightweight cross-platform SSH/SFTP client with GUI, written in Dart/Flutter.
Аналог Xshell/Termius, open-source и мультиплатформенный (desktop + mobile).
Target platforms: Windows, Linux, macOS, Android, iOS.

**Predecessor:** LetsGOssh (Go/Fyne) — перенос всего функционала + улучшения.
**Reference:** Termius (Flutter-based commercial SSH client) — proof that Flutter works for this domain.

## Working Agreements

### Коммиты

- **Пользователь коммитит сам** — Claude только предлагает сообщение коммита
- Формат: `type: краткое описание` (например `feat: phase 1 — SSH terminal with xterm.dart`)
- Типы: `feat`, `fix`, `refactor`, `docs`, `chore`
- Репозиторий **приватный** на GitHub

### Стиль работы

- Документация ведётся на русском (PLAN.md) и английском (README.md, CLAUDE.md)
- PLAN.md, CLAUDE.md, README.md **обновляются при каждом значимом изменении**
- Все архитектурные/UX-паттерны документируются в CLAUDE.md в момент внедрения
- Ключи SSH принимаются **и файлом, и текстом** (paste PEM) — ключевое требование
- Лёгкий перенос данных между устройствами — приоритетная фича (формат `.lfs` archive)
- Группировка сессий — дерево с вложенными подпапками (например `Production/Web/nginx1`)

### Post-change workflow (обязательно после каждого значимого изменения)

1. **Version bump** — бампать версию в `pubspec.yaml` (patch для fix/feat, minor для новой фазы)
2. **CLAUDE.md** — обновить Current State и описания модулей; записать **почему** было принято решение
3. **README.md** — обновить если изменение видимо пользователю
4. **Коммит** — предложить однострочное сообщение в формате `type: краткое описание` (пользователь коммитит сам)

### Зависимости

- Всегда использовать **последние стабильные версии** пакетов (последний pub.dev release)
- Если пакет без стабильного релиза — последняя pre-release версия, совместимая с текущим SDK

### Сборка

- `flutter run` — запуск (debug, текущая платформа)
- `flutter build linux` / `flutter build windows` / `flutter build apk` / etc.
- `flutter test` — тесты
- `flutter analyze` — линтер

### Что не делать

- Не коммитить автоматически, не пушить
- Не устанавливать пакеты без спроса (пользователь одобряет)
- Перед коммитом обязательно запускать `flutter analyze` + `flutter test`

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
│   │   └── connection/              # Connection lifecycle manager
│   │       ├── connection.dart      # Connection model (SSH client ref, state, label)
│   │       └── connection_manager.dart # Active connections tracking, tab association
│   │
│   ├── features/                    # Feature modules (UI + logic)
│   │   ├── terminal/                # Terminal tab
│   │   │   ├── terminal_tab.dart    # Widget: xterm TerminalView + SSH pipe
│   │   │   ├── terminal_controller.dart # State: connect, disconnect, resize, input
│   │   │   └── terminal_shortcuts.dart  # Keyboard shortcuts (Ctrl+Shift+C/V, etc.)
│   │   │
│   │   ├── file_browser/            # Dual-pane SFTP file browser
│   │   │   ├── file_browser_tab.dart    # Widget: split-pane (local | remote)
│   │   │   ├── file_pane.dart           # Single pane: table + path bar + navigation
│   │   │   ├── file_table.dart          # DataTable with sort, multiselect, context menu
│   │   │   ├── file_browser_controller.dart # State: listing, navigation, selection
│   │   │   ├── transfer_panel.dart      # Bottom panel: progress + history (collapsible)
│   │   │   └── file_actions.dart        # Upload/download/delete/rename/mkdir actions
│   │   │
│   │   ├── session_manager/         # Session sidebar
│   │   │   ├── session_panel.dart   # Widget: tree view + search + actions
│   │   │   ├── session_tree_view.dart # Hierarchical session list (nested groups)
│   │   │   ├── session_edit_dialog.dart # Create/edit session dialog
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

1. **Feature-first structure** — каждая фича (terminal, file_browser, session_manager) — изолированный модуль с UI + логикой
2. **Core is UI-agnostic** — `core/` не импортирует Flutter; может быть переиспользован в CLI-утилите
3. **Riverpod for state** — единый источник правды для всех состояний (sessions, connections, config, transfers)
4. **Immutable models** — все data-классы через `freezed` (copyWith, equality, JSON serialization)
5. **FileSystem interface** — абстракция для local/remote файлового доступа (как в LetsGOssh)
6. **No SCP** — dartssh2 не поддерживает SCP; SFTP покрывает все use cases (upload/download файлов и директорий с прогрессом)
7. **Tree-based sessions** — вложенные группы через `/` разделитель (Production/Web/nginx1), хранятся как flat list с group path, UI строит TreeView

## Current State (v0.7.1 — Phase 7 complete + cleanup)

### What works
- SSH подключение через dartssh2 (password, key file, key text)
- Auth chain: key file → key text → password (как в LetsGOssh)
- **Session Manager** — сохранение сессий в JSON, CRUD, duplicate
- **Session TreeView** — вложенные группы (Production/Web/nginx1), expand/collapse
- **Search/filter** — по label, group, host, user
- **Context menu** — SSH connect, SFTP connect, Edit, Delete, Duplicate (right-click)
- **Double-click** → SSH connect
- **Session Edit Dialog** — auth type selector (Password/Key/Key+Pass), group autocomplete
- **Resizable sidebar** — drag-divider между sidebar и content area
- Keep-alive через dartssh2 `keepAliveInterval`
- TOFU known hosts (auto-accept, persistent storage)
- Terminal emulation через xterm.dart (256-color, mouse, scrollback 5000 lines)
- Copy/paste из коробки (xterm.dart built-in Actions: Ctrl+Shift+C/V)
- PTY resize при изменении размера окна
- Disconnect detection + Reconnect кнопка
- Tab system (open, close, switch, IndexedStack для сохранения состояния)
- Tab bar с индикатором состояния (green/orange/red)
- Quick Connect диалог (host, port, user, password, key file picker, PEM text)
- Валидация полей в диалоге
- **OneDark theme** — Atom OneDark Pro palette (dark), One Light (light), system auto-detect
- App config (JSON persistence в app support dir)
- Status bar (connection state + tab count)
- Keyboard shortcuts: Ctrl+N (quick connect), Ctrl+W (close tab), Ctrl+Tab (next tab)
- Riverpod state management (config, connections, tabs, theme)
- Makefile (run, build, test, analyze, gen, clean)
- **SFTP File Browser** — dual-pane (local | remote) с navigation history
- **File pane** — sortable list (name/size/mode/modified), editable path bar, back/forward/up/refresh
- **Context menu** — open dir, transfer, new folder, rename, delete (single + multi-select)
- **Transfer Manager** — queue с configurable parallelism (default 2 workers)
- **Transfer Panel** — collapsible bottom panel с history (completed/failed, duration, error details)
- **SFTP toolbar button** — opens SFTP tab for active connection
- **Session context menu** — "SFTP Only" option для прямого подключения к file browser
- **FileSystem interface** — абстракция LocalFS/RemoteFS (как в LetsGOssh)
- **Tab drag-to-reorder** — ReorderableListView, context menu (close, close others, close right)
- **Toast notifications** — overlay-based, 4 levels (info/success/warning/error), auto-dismiss, stacking
- **Settings screen** — theme, font size, scrollback, keepalive, timeout, port, transfer workers, max history, reset to defaults
- **Status bar** — connection state + transfer progress (reactive via StreamProvider)
- **Responsive layout** — sidebar → drawer on narrow screens (<600px), hamburger menu button
- **Reconnect** — error state UI with Reconnect + Close buttons
- **Secure credential storage** — AES-256-GCM encrypted file (pointycastle, pure Dart, no OS deps)
- **Credentials separated from sessions** — sessions.json без секретов, credentials.enc с AES-256-GCM
- **Auto-migration** — plaintext credentials в sessions.json автоматически мигрируют в encrypted store
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
- **Split shortcuts** — Ctrl+Shift+D (split right), Ctrl+Shift+E (split down), Ctrl+Shift+W (close pane)
- **Pane focus tracking** — blue border on focused pane, click to switch focus
- **Multiple shells per connection** — each pane opens its own SSH shell on the shared Connection

### Решения и почему
- **SSHConnectionState вместо ConnectionState** — конфликт имён с Flutter's `ConnectionState` из async.dart
- **xterm.dart built-in copy/paste** — xterm 4.0 уже имеет Actions для CopySelectionTextIntent/PasteTextIntent, не нужно реализовывать вручную
- **dartssh2 host key callback** — signature `FutureOr<bool> Function(String type, Uint8List fingerprint)`, не SSHPublicKey
- **IndexedStack для табов** — сохраняет состояние терминала при переключении между вкладками
- **Flutter SDK** — установлен в `/home/llloooggg/flutter-sdk` (stable 3.41.5, Dart 3.11.3)
- **dartssh2 SFTP API** — `attr.mode?.value` (не `attr.permissions?.mode`), `remoteFile.writeBytes()` (не `write()`)
- **FilePaneController как ChangeNotifier** — lightweight state для каждой панели, без Riverpod overhead для внутреннего состояния навигации
- **TransferManager с Stream notifications** — Riverpod StreamProvider подписывается на onChange для reactive UI updates
- **pointycastle вместо encrypt** — encrypt ^5.0.3 требует pointycastle ^3.6.2, конфликт с dartssh2 (needs ^4.0.0); pointycastle уже transitive dep
- **CredentialStore вместо flutter_secure_storage** — pure Dart, no OS-specific native deps; AES-256-GCM с random key в credentials.key
- **PBKDF2 100k iterations для .lfs** — industry standard key derivation для password-based encryption архивов
- **Listener вместо GestureDetector для marquee** — Listener (raw pointer events) не участвует в gesture arena, поэтому не конфликтует с Draggable на строках файлов
- **Draggable только на выделенных файлах** — клик по невыделенному файлу + drag = marquee; клик по выделенному + drag = transfer между панелями
- **PaneDragData с sourcePaneId** — DragTarget отклоняет drop с тем же paneId, предотвращая transfer в ту же панель
- **Focus-based Del** — каждая FilePane имеет FocusNode; Del удаляет только из панели с фокусом; фокус переключается при клике и при drop
- **Empty groups в SessionStore** — пустые папки хранятся в отдельном empty_groups.json; SessionTree.build() принимает emptyGroups для рендеринга
- **Global navigatorKey для host key dialog** — KnownHostsManager callbacks показывают Flutter dialogs через navigatorKey.currentContext, без привязки к конкретному виджету
- **SHA256 fingerprint** — pointycastle SHA256Digest для стандартного формата `SHA256:base64hash` (вместо hex первых 16 байт)
- **Auto-detect SSH keys** — если keyPath и keyData пусты, пробуем id_ed25519 → id_ecdsa → id_rsa → id_dsa из ~/.ssh/ (порядок как в OpenSSH)
- **Key file drop auto-reads PEM** — если dropped файл < 32KB и содержит "PRIVATE KEY", содержимое читается в keyData; иначе ставится keyPath
- **Sealed class SplitNode** — Dart sealed class для recursive split tree (LeafNode | BranchNode); exhaustive switch, immutable IDs (uuid)
- **Tiling как tree** — recursive BranchNode(direction, ratio, first, second) позволяет произвольную глубину вложенности; replaceNode/removeNode для мутации дерева
- **TerminalPane vs TerminalTab** — TerminalPane = один терминал в тайле (без reconnect); TerminalTab = контейнер с tiling tree + reconnect + shortcuts
- **Каждый pane → свой SSH shell** — openShell() вызывается для каждого LeafNode, все шеллы на одном SSHConnection; при reconnect дерево сбрасывается в один лист
- **OneDark theme** — централизованная палитра в `lib/theme/app_theme.dart`; все цвета (connected/disconnected/warning/folder) через AppTheme semantic constants; нет хардкода Colors.red/green/orange
- **file_pane.dart split** — FileRow, MenuRow, MarqueePainter, PaneDragData вынесены в `file_row.dart`; file_pane.dart содержит только FilePane + state
- **Удалены unused deps** — go_router (не используется, навигация через MaterialApp), freezed_annotation (модели написаны вручную)

### What's planned (перенос из LetsGOssh + улучшения)

**Переносится as-is:**
- SSH подключение (password, key file, key text, SSH agent)
- Known hosts (TOFU)
- Keep-alive
- Terminal emulation (xterm.dart даёт из коробки: 256-color, RGB, mouse, scrollback, alternate screen)
- Session manager (CRUD, groups, search, context menu)
- SFTP file browser (dual-pane, upload/download, mkdir, delete, rename, chmod, properties)
- Transfer manager (queue, parallel workers, history)
- Drag&drop (файлы из ОС + между панелями)
- Toast notifications
- Config (theme, font size, scrollback, keepalive, etc.)
- Multiple tabs (terminal + SFTP)

**Улучшения по сравнению с LetsGOssh:**
- Tab drag reorder (Flutter has built-in Draggable)
- Tree view для сессий (вложенные группы)
- Scrollback из коробки (xterm.dart `maxLines`)
- Text selection + copy/paste из коробки (xterm.dart)
- Mouse reporting из коробки (xterm.dart)
- Smooth split-pane drag (Flutter layout не тормозит как Fyne)
- Secure credential storage (AES-256-GCM encrypted file вместо plaintext JSON)
- Mobile support (Android, iOS) с адаптивным UI
- Port forwarding UI
- Data export/import (.lfs encrypted archive)
- Settings screen

**Не переносится:**
- SCP (dartssh2 не поддерживает; SFTP достаточно)
- midterm / custom VT parser (xterm.dart всё делает)
- Custom split widget (Flutter layout достаточно производительный)

## Module Details

### `core/ssh`

SSH-клиент обёртка над `dartssh2`:

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

SFTP обёртка над `dartssh2` SFTP subsystem:

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

Transfer queue (порт из LetsGOssh `internal/transfer`):

- `TransferManager`:
  - Configurable parallelism (default 2 workers)
  - `enqueue(task)` → returns task ID
  - `history` — completed/failed transfers
  - `clearHistory()`, `deleteHistory(ids)`
  - Auto-notify listeners (Riverpod)
- `TransferTask`: name, direction (upload/download), sourcePath, targetPath, run function
- `HistoryEntry`: id, name, direction, source, target, status, error, duration, timestamps

### `core/session`

Session management (порт из LetsGOssh `internal/session`):

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

App configuration (порт из LetsGOssh `internal/config`):

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

Dual-pane SFTP browser (порт из LetsGOssh `internal/ui/filebrowser`):

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

Session sidebar (порт из LetsGOssh `internal/ui/sessionmgr`):

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
