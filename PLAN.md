# LetsFLUTssh — Development Plan

## Phase 1: Foundation + Terminal (v0.1)

**Goal:** Minimal working SSH client with terminal. Connect, type, display.

- [x] Create Flutter project (`flutter create`)
- [x] Configure `pubspec.yaml` (deps: dartssh2, xterm, riverpod, path_provider, pointycastle)
- [x] Configure `analysis_options.yaml` (strict lint rules)
- [x] `.gitignore` for Flutter
- [x] Initialize git repository
- [x] `lib/core/ssh/` — SSH client
    - [x] `SSHConfig` — connection config model (host, port, user, password, keyPath, keyData, passphrase)
    - [x] `SSHConnection` — wrapper over `dartssh2.SSHClient`
        - [x] `connect()` — connection with timeout
        - [x] Auth chain: password → key file → key text → keyboard-interactive
        - [x] `openShell(cols, rows)` — PTY session, stdin/stdout streams
        - [x] `resizeTerminal(cols, rows)` — PTY resize
        - [x] `disconnect()`, `isConnected` getter
        - [x] `onDisconnect` callback
        - [x] Keep-alive (configurable interval, default 30s)
    - [x] `errors.dart` — AuthError, ConnectError with cause unwrapping
- [x] `lib/core/ssh/known_hosts.dart` — TOFU host key verification
    - [x] Load/save known_hosts file
    - [x] Host key verification on connect
    - [x] New key confirmation dialog (SHA256 fingerprint + Accept/Reject)
    - [x] Key change warning dialog (potential MITM warning)
- [x] `lib/features/terminal/` — Terminal tab
    - [x] `TerminalTab` widget: `xterm.TerminalView` connected to SSH shell
    - [x] Pipe: SSH stdout → xterm Terminal.write(); xterm onOutput → SSH stdin
    - [x] `onResize` → `SSHConnection.resizeTerminal()`
    - [x] Ctrl+Shift+C/V — copy/paste (built-in xterm.dart Actions)
    - [x] Right-click context menu (Copy / Paste)
    - [x] Disconnect detection → show message + Reconnect button
- [x] `lib/features/tabs/` — basic tab system
    - [x] Tab bar with close button
    - [x] Welcome screen when no tabs open
- [x] `lib/main.dart` — entry point
    - [x] MaterialApp with theme (dark by default)
    - [x] Quick Connect button → dialog → connect → terminal tab
    - [x] Status bar (connection info)
- [x] `lib/core/config/` — basic config
    - [x] `AppConfig` model (fontSize, theme, scrollback, keepAlive, defaultPort)
    - [x] Load/save JSON in app support dir
- [x] `lib/providers/` — Riverpod providers
    - [x] `configProvider` — config loading
    - [x] `connectionProvider` — active connections tracking
- [x] Quick Connect dialog
    - [x] Host, Port, User, Password, Key file (file picker), Key text (multiline PEM)
    - [x] Required field validation
- [x] First working build (Linux desktop) — requires manual testing
- [x] Test: SSH connection, commands, htop, vim — requires manual testing

## Phase 2: Session Manager (v0.2)

**Goal:** Session persistence, sidebar, groups, search

- [x] `lib/core/session/` — model and store
    - [x] `Session` model: id, label, group, host, port, user, authType, password, keyPath, keyData, passphrase, createdAt, updatedAt
    - [x] `Session.validate()` — host required, port 1-65535, user required
    - [x] `SessionStore` — CRUD + JSON persistence (credentials inline, Phase 5 → secure storage)
    - [x] `SessionTree` — tree building from flat list by group path (`/`-separated)
    - [x] Groups: `Production/Web/nginx1` → nested tree
    - [x] Search: by label, group, host, user
    - [x] Duplicate session
- [x] `lib/features/session_manager/` — sidebar UI
    - [x] `SessionPanel` — side panel (resizable)
    - [x] `SessionTreeView` — TreeView with nested groups
    - [x] Search/filter bar
    - [x] Double-click → SSH connect
    - [x] Context menu: SSH connect, Edit, Delete, Duplicate
    - [x] New / Edit session dialogs
        - [x] Label, Group (autocomplete existing groups), Host, Port, User
        - [x] Auth type selector (Password / Key / Key+Password)
        - [x] Key file field (path input with ~ expansion)
        - [x] Key text field (paste PEM)
        - [x] Passphrase field
        - [x] Inline validation
- [x] `lib/providers/session_provider.dart` — Riverpod provider for sessions
- [x] Split layout: sidebar (sessions) | main area (tabs)
- [x] Sidebar resizable with drag-divider
- [x] Tests: session validation, tree building (28 tests total)

## Phase 3: SFTP File Browser (v0.3) ✅

**Goal:** Dual-pane file manager (local | remote) with drag&drop

- [x] `lib/core/sftp/` — SFTP client
    - [x] `SFTPService` — wrapper over dartssh2 SFTP
        - [x] `list(path)` → sorted (dirs first, alphabetical)
        - [x] `upload(local, remote, onProgress)` — with progress callback
        - [x] `download(remote, local, onProgress)` — with progress callback
        - [x] `uploadDir(localDir, remoteDir, onProgress)` — recursive
        - [x] `downloadDir(remoteDir, localDir, onProgress)` — recursive
        - [x] `mkdir`, `remove`, `removeDir`, `rename`, `stat`, `getwd`
    - [x] `FileSystem` interface + `LocalFS` + `RemoteFS`
    - [x] `FileEntry` model: name, path, size, mode, modTime, isDir
    - [x] `TransferProgress` model: fileName, totalBytes, doneBytes, percent
- [x] `lib/core/transfer/` — transfer manager
    - [x] `TransferManager` — task queue + parallel workers (configurable)
    - [x] `TransferTask` — name, direction (upload/download), source, target, run function
    - [x] `HistoryEntry` — id, name, direction, status, error, duration, timestamps
    - [x] `clearHistory()`, `deleteHistory(ids)`
- [x] `lib/features/file_browser/` — file manager UI
    - [x] Split-pane: local (left) | remote (right)
    - [x] `FilePane` — generic single-pane file list
        - [x] File list: Name, Size, Mode, Modified — click-to-sort
        - [x] Dirs always first in sort
        - [x] Double-click folder → navigate
        - [x] Editable path bar (Enter → navigate)
        - [x] Back / Forward buttons with navigation history
        - [x] Refresh button
        - [x] Multi-select (Ctrl+click)
    - [x] Context menu (right-click on file):
        - [x] Download / Upload (depending on pane)
        - [x] Rename
        - [x] Delete (with confirm dialog)
        - [x] New Folder
    - [x] Internal drag&drop between panes (Draggable + DragTarget)
    - [x] Marquee (rubber band) selection + Ctrl+click for multi-select
    - [x] OS drag&drop (`desktop_drop`) — drop files from OS into panes
    - [x] Transfer panel (bottom, collapsible)
        - [x] Active transfer info (count, current file)
        - [x] History list: Direction (↑/↓), Status, Name, Duration, Error
        - [x] Toggle bar "Transfers" to collapse
        - [x] Clear history
- [x] SFTP button in toolbar → opens SFTP tab for active connection
- [x] Multiple SFTP tabs per connection
- [x] SFTP-only connect — via context menu "SFTP Only"
- [x] `lib/providers/transfer_provider.dart` — Riverpod provider
- [x] Tests: sftp models, transfer manager, format utils (53 tests total)

## Phase 4: Polish & UX (v0.4) ✅

**Goal:** UI/UX polish to production quality

- [x] Tab bar improvements
    - [x] Drag-to-reorder tabs (ReorderableListView)
    - [x] Context menu: close, close others, close tabs to the right
    - [x] Color indicator: green = connected, red = disconnected, orange = connecting
- [x] Toast notifications
    - [x] Non-blocking overlay popup (right side, stacking)
    - [x] Levels: Info, Warning, Error, Success
    - [x] Auto-dismiss timer + dismiss button
    - [x] Fade + slide animation
- [x] Key field improvements
    - [x] Drag&drop .pem/.key files into key field (desktop_drop)
    - [x] Auto-read PEM content on drop
- [x] Reconnect logic
    - [x] Terminal tab: error state → Reconnect / Close buttons
- [x] Toolbar
    - [x] Quick Connect, SFTP, Settings buttons with tooltips
    - [x] Hamburger menu on narrow screens
- [x] Settings screen
    - [x] Theme (dark / light / system)
    - [x] Font size (slider)
    - [x] Scrollback lines, Keep-alive, SSH timeout, Default port
    - [x] Transfer workers, Max history
    - [x] Reset to defaults
- [x] Status bar
    - [x] Connection state
    - [x] Transfer progress summary (reactive)
- [x] Mobile adaptations
    - [x] Responsive layout (sidebar → drawer on <600px)
    - [x] Hamburger menu button

## Phase 5: Data Portability & Security (v0.5)

**Goal:** Secure storage, export/import, encryption

- [x] Secure credential storage
    - [x] AES-256-GCM encrypted file via pointycastle (pure Dart, no OS deps)
    - [x] Key data (PEM) + passwords + passphrases in `credentials.enc`
    - [x] Session JSON file contains only non-secret fields
    - [x] Migration: import plaintext sessions → encrypted storage (auto on load)
- [x] Export/Import
    - [x] `.lfs` format (LetsFLUTssh archive) — ZIP + AES-256-GCM
    - [x] Export: sessions (with credentials) + config + known_hosts
    - [x] Import: merge/replace mode, config + known_hosts import
    - [x] Master password → PBKDF2-SHA256 (100k iterations) → AES-256-GCM
    - [x] Drag&drop `.lfs` file into window → auto-import
- [x] Settings → Export Data / Import Data

## Phase 6: Advanced Features (v0.6) ✅

**Goal:** Terminal search, session folders, auto-detect SSH keys

- [x] Terminal search (Ctrl+Shift+F)
    - [x] Search scrollback buffer
    - [x] Highlight matches
    - [x] Next/Previous navigation
- [x] Session panel: create folders via context menu (right-click on group or empty space)
- [x] Auto-detect SSH keys from ~/.ssh/ (id_rsa, id_ed25519, id_ecdsa)

## Phase 7: Tiling & Split Terminals (v0.7) ✅

**Goal:** Multi-terminal layout (like tmux/Terminator/VS Code)

- [x] Split-view within a tab
    - [x] Vertical split (left | right terminals)
    - [x] Horizontal split (top / bottom terminals)
    - [x] Recursive splitting (quad layout, etc.)
    - [x] Drag to resize splits
    - [x] Focus indicator (blue border on active pane)
    - [x] Keyboard shortcuts: Ctrl+Shift+D (split right), Ctrl+Shift+E (split down), Ctrl+Shift+W (close pane)
    - [x] Context menu: Split Right / Split Down / Close Pane
    - [x] Each pane opens its own SSH shell on shared Connection

## Phase 8: Mobile (v0.8) ✅

**Goal:** Full-featured mobile version (Android + iOS)

- [x] Adaptive UI
    - [x] Sidebar → bottom navigation (Sessions / Terminal / Files)
    - [x] File browser → single pane with Local/Remote toggle
    - [x] Full-screen terminal (no tiling on mobile)
    - [x] Tab switcher via ChoiceChips (multiple terminals/SFTP)
    - [x] FAB for Quick Connect on Sessions page
    - [x] Dialogs adapt to narrow screens (ConstrainedBox)
- [x] Virtual keyboard
    - [x] SSH-specific keys panel: Esc, Tab, Ctrl, Alt, arrows, |, ~, /, -
    - [x] F1-F12 expandable row (Fn toggle)
    - [x] Sticky modifiers: tap = one-shot, double-tap = lock
    - [x] Haptic feedback on key press
- [x] Touch terminal
    - [x] Long press → context menu (copy/paste)
    - [x] Pinch to zoom (font size 8-24pt)
- [x] Platform integration
    - [x] URL scheme: `letsflutssh://connect?host=...` (app_links + Android/iOS config)
    - [x] File open intents: .pem/.key/.lfs files (ACTION_VIEW)
    - [x] Swipe gestures (left/right = tab switch, velocity threshold 300)
- [x] Android build (APK + AAB)

## Phase 9: Stable Release (v1.0)

**Goal:** Production-ready release

- [x] Unit tests for core modules (209 tests)
- [x] Widget tests for UI components (67 widget tests, 283 total)
- [x] CI/CD (GitHub Actions)
    - [x] flutter analyze + flutter test on PR
    - [x] Build artifacts: Linux, Windows, macOS, Android APK
- [x] Packaging
    - [x] Linux: AppImage, deb, tar.gz (.desktop file, CI packaging)
    - [x] Windows: EXE installer (Inno Setup), portable zip
    - [x] macOS: dmg (hdiutil), tar.gz
- [x] Performance profiling and optimization
    - [x] Cached computed properties (totalFileSize, selectedEntries) in FilePaneController
    - [x] Memoized session counts in SessionTree (O(n²) → O(1) for group rendering)
    - [x] ListView.builder for session tree (lazy rendering instead of full Column)
    - [x] Extracted terminal search bar to separate widget (search state no longer rebuilds TerminalView)
    - [x] RepaintBoundary for marquee CustomPaint
    - [x] Throttled marquee selection updates (50ms)
    - [x] Fixed toast AnimationController deferred disposal (memory leak)
    - [x] Optimized ref.watch with .select() in SessionPanel
- [x] Security audit (credential storage, SSH implementation)
    - [x] File permissions (chmod 600) on credential files
    - [x] TOFU: reject unknown hosts without callback (no auto-accept)
    - [x] PBKDF2 iterations bumped 100k → 600k (OWASP 2024)
    - [x] Error messages: removed file paths from user-facing errors
    - [x] Logging: auto-detect SSH key failures now logged
- [x] User documentation (docs/USER_GUIDE.md)
- [x] Architecture refactoring (v0.9.1)
    - [x] ShellHelper — shared SSH shell connection logic (retry + stream wiring), extracted from terminal_pane + mobile_terminal_view
    - [x] SFTPInitializer — shared SFTP init factory (service + controllers), extracted from file_browser_tab + mobile_file_browser
    - [x] FilePaneDialogs — shared dialogs (New Folder, Rename, Delete), extracted from file_pane + mobile_file_browser
    - [x] SessionConnect — shared connection logic (connectTerminal, connectSftp, quickConnect), extracted from main.dart
    - [x] Settings screen split into section widgets with `configProvider.select()` — fine-grained rebuilds
    - [x] Silent `catch (_)` → `catch (e) { dev.log() }` in credential_store, config_store, sftp_client
    - [x] FilePaneController.dispose() now calls super.dispose() (memory leak fix)
    - [x] Mockito-based SSH shell tests (8 tests with mocked SSHConnection/SSHSession)
    - [x] FilePaneController tests (20 tests — navigation, selection, sort, cache, dispose)
    - [x] FilePaneDialogs widget tests (14 tests — new folder, rename, delete dialogs)

## Phase 10: Post-Release Polish (v1.x)

**Goal:** Advanced features, not blocking stable release

- [ ] Port forwarding
    - [ ] Local forwarding (localPort → remoteHost:remotePort)
    - [ ] Remote forwarding (remotePort → localHost:localPort)
    - [ ] Dynamic/SOCKS proxy (if dartssh2 supports it)
    - [ ] UI: active tunnels list, add/remove
- [ ] SSH tunneling via jump host
    - [ ] ProxyJump equivalent (SSH → SSH chain)
- [ ] Multi-exec
    - [ ] Select multiple sessions → run command on all simultaneously
    - [ ] Results in separate panels (side by side)
- [ ] Session logging
    - [ ] Record terminal output to file
    - [ ] Timestamp each line
    - [ ] Auto-log option per session
- [ ] Broadcast input to all panes (type once → send to all)
- [ ] Synchronized scrolling (optional)
- [ ] Biometric auth for opening app / accessing credentials
- [ ] Notification for active sessions in background (mobile)
- [ ] Keyboard toolbar for terminal (mobile SSH keys: Ctrl, Esc, Tab, Alt, arrows, F1-F12)
- [ ] Integration tests (SSH + SFTP with real server) — medium priority
- [ ] iOS build (untested) — low priority
- [ ] Android: Play Store / F-Droid — low priority

---

## Current Status

**Active phase:** Phase 9 (Stable Release) — completed
**Progress:** Phases 1-9 completed. v0.9.1 — 283 tests (209 unit + 67 widget + 7 deeplink). Architecture refactoring (ShellHelper, SFTPInitializer, FilePaneDialogs, SessionConnect), mockito SSH mocks, security audit, packaging, user docs.

### Work Order

Phases 1-3 — core functionality (terminal, sessions, file browser). This is the MVP.
Phase 4 — polish to usable state.
Phases 5-6 — security, search, advanced UX.
Phase 7 — tiling/split terminals.
Phase 8 — mobile.
Phase 9 — stable release.
Phase 10 — post-release polish (port forwarding, multi-exec, logging, etc.)

### Effort Estimates

| Phase | Description           | Complexity                                                     |
| ----- | --------------------- | -------------------------------------------------------------- |
| 1 ✅  | Foundation + Terminal | Medium (dartssh2 + xterm.dart do the heavy lifting)            |
| 2 ✅  | Session Manager       | Medium (UI-heavy, but simple logic)                            |
| 3 ✅  | SFTP File Browser     | Hard (lots of UI: dual-pane, drag&drop, history)               |
| 4 ✅  | Polish & UX           | Medium (refinement of existing code)                           |
| 5 ✅  | Security & Export     | Medium (pointycastle AES-256-GCM + archive ZIP)               |
| 6 ✅  | Advanced UX           | Medium (terminal search, session folders, key improvements)    |
| 7 ✅  | Tiling                | Medium (recursive split layout)                                |
| 8 ✅  | Mobile                | Hard (adaptive UI + virtual keyboard + platform integration)   |
| 9     | Release               | Medium (CI/CD + packaging + testing)                           |
| 10    | Post-Release Polish   | Hard (port forwarding, multi-exec, jump hosts)                 |
