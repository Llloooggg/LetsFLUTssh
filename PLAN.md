# LetsFLUTssh — Development Plan

## Phase 1: Foundation + Terminal (v0.1)

**Goal:** Минимальный рабочий SSH-клиент с терминалом. Подключение, ввод, отображение.

- [x] Создать Flutter-проект (`flutter create`)
- [x] Настроить `pubspec.yaml` (зависимости: dartssh2, xterm, riverpod, path_provider, pointycastle)
- [x] Настроить `analysis_options.yaml` (strict lint rules)
- [x] `.gitignore` для Flutter
- [x] Инициализировать git-репозиторий
- [x] `lib/core/ssh/` — SSH клиент
    - [x] `SSHConfig` — модель конфигурации подключения (host, port, user, password, keyPath, keyData, passphrase)
    - [x] `SSHConnection` — обёртка над `dartssh2.SSHClient`
        - [x] `connect()` — подключение с timeout
        - [x] Auth chain: password → key file → key text → keyboard-interactive
        - [x] `openShell(cols, rows)` — PTY сессия, stdin/stdout потоки
        - [x] `resizeTerminal(cols, rows)` — PTY resize
        - [x] `disconnect()`, `isConnected` getter
        - [x] `onDisconnect` callback
        - [x] Keep-alive (configurable interval, default 30s)
    - [x] `errors.dart` — AuthError, ConnectError с cause unwrapping
- [x] `lib/core/ssh/known_hosts.dart` — TOFU host key verification
    - [x] Загрузка/сохранение known_hosts файла
    - [x] Проверка host key при подключении
    - [x] Диалог подтверждения нового ключа (SHA256 fingerprint + Accept/Reject)
    - [x] Диалог предупреждения при смене ключа (potential MITM warning)
- [x] `lib/features/terminal/` — Terminal tab
    - [x] `TerminalTab` widget: `xterm.TerminalView` подключённый к SSH shell
    - [x] Pipe: SSH stdout → xterm Terminal.write(); xterm onOutput → SSH stdin
    - [x] `onResize` → `SSHConnection.resizeTerminal()`
    - [x] Ctrl+Shift+C/V — copy/paste (из коробки xterm.dart — встроенные Actions)
    - [x] Right-click context menu (Copy / Paste)
    - [x] Disconnect detection → показать сообщение + кнопку Reconnect
- [x] `lib/features/tabs/` — базовая система вкладок
    - [x] Tab bar с кнопкой закрытия
    - [x] Welcome screen при отсутствии вкладок
- [x] `lib/main.dart` — точка входа
    - [x] MaterialApp с темой (dark по умолчанию)
    - [x] Quick Connect кнопка → диалог → подключение → terminal tab
    - [x] Status bar (connection info)
- [x] `lib/core/config/` — базовый конфиг
    - [x] `AppConfig` модель (fontSize, theme, scrollback, keepAlive, defaultPort)
    - [x] Загрузка/сохранение JSON в app support dir
- [x] `lib/providers/` — Riverpod providers
    - [x] `configProvider` — загрузка конфига
    - [x] `connectionProvider` — отслеживание активных подключений
- [x] Quick Connect диалог
    - [x] Host, Port, User, Password, Key file (file picker), Key text (multiline PEM)
    - [x] Валидация обязательных полей
- [x] Первый рабочий билд (Linux desktop) — требует ручной проверки
- [x] Тест: подключение к SSH серверу, команды, htop, vim — требует ручной проверки

## Phase 2: Session Manager (v0.2)

**Goal:** Сохранение сессий, sidebar, группы, поиск

- [x] `lib/core/session/` — модель и хранилище
    - [x] `Session` модель: id, label, group, host, port, user, authType, password, keyPath, keyData, passphrase, createdAt, updatedAt
    - [x] `Session.validate()` — host required, port 1-65535, user required
    - [x] `SessionStore` — CRUD + JSON persistence (credentials inline, Phase 5 → secure storage)
    - [x] `SessionTree` — построение дерева из flat-списка по group path (`/`-separated)
    - [x] Groups: `Production/Web/nginx1` → nested tree
    - [x] Search: по label, group, host, user
    - [x] Duplicate session
- [x] `lib/features/session_manager/` — UI sidebar
    - [x] `SessionPanel` — боковая панель (resizable)
    - [x] `SessionTreeView` — TreeView с вложенными группами
    - [x] Search/filter bar
    - [x] Double-click → SSH connect
    - [x] Context menu: SSH connect, Edit, Delete, Duplicate
    - [x] New / Edit session dialogs
        - [x] Label, Group (autocomplete existing groups), Host, Port, User
        - [x] Auth type selector (Password / Key / Key+Password)
        - [x] Key file field (path input с ~ expansion)
        - [x] Key text field (paste PEM)
        - [x] Passphrase field
        - [x] Inline validation
- [x] `lib/providers/session_provider.dart` — Riverpod provider для sessions
- [x] Split layout: sidebar (sessions) | main area (tabs)
- [x] Sidebar resizable с drag-divider
- [x] Тесты: session validation, tree building (28 тестов всего)

## Phase 3: SFTP File Browser (v0.3) ✅

**Goal:** Двухпанельный файловый менеджер (local | remote) с drag&drop

- [x] `lib/core/sftp/` — SFTP клиент
    - [x] `SFTPService` — обёртка над dartssh2 SFTP
        - [x] `list(path)` → sorted (dirs first, alphabetical)
        - [x] `upload(local, remote, onProgress)` — с progress callback
        - [x] `download(remote, local, onProgress)` — с progress callback
        - [x] `uploadDir(localDir, remoteDir, onProgress)` — recursive
        - [x] `downloadDir(remoteDir, localDir, onProgress)` — recursive
        - [x] `mkdir`, `remove`, `removeDir`, `rename`, `stat`, `getwd`
    - [x] `FileSystem` interface + `LocalFS` + `RemoteFS`
    - [x] `FileEntry` модель: name, path, size, mode, modTime, isDir
    - [x] `TransferProgress` модель: fileName, totalBytes, doneBytes, percent
- [x] `lib/core/transfer/` — transfer manager
    - [x] `TransferManager` — очередь задач + parallel workers (configurable)
    - [x] `TransferTask` — name, direction (upload/download), source, target, run function
    - [x] `HistoryEntry` — id, name, direction, status, error, duration, timestamps
    - [x] `clearHistory()`, `deleteHistory(ids)`
- [x] `lib/features/file_browser/` — UI файлового менеджера
    - [x] Split-pane: local (left) | remote (right)
    - [x] `FilePane` — generic single-pane file list
        - [x] File list: Name, Size, Mode, Modified — click-to-sort
        - [x] Dirs always first in sort
        - [x] Double-click folder → navigate
        - [x] Editable path bar (Enter → navigate)
        - [x] Back / Forward buttons с историей навигации
        - [x] Refresh button
        - [x] Multi-select (Ctrl+click)
    - [x] Context menu (right-click on file):
        - [x] Download / Upload (в зависимости от панели)
        - [x] Rename
        - [x] Delete (с confirm dialog)
        - [x] New Folder
    - [x] Internal drag&drop между панелями (Draggable + DragTarget)
    - [x] Marquee (rubber band) selection + Ctrl+click для multi-select
    - [x] OS drag&drop (`desktop_drop`) — drop files from OS into panes
    - [x] Transfer panel (bottom, collapsible)
        - [x] Active transfer info (count, current file)
        - [x] History list: Direction (↑/↓), Status, Name, Duration, Error
        - [x] Toggle bar "Transfers" для collapse
        - [x] Clear history
- [x] SFTP кнопка в toolbar → открывает SFTP tab для текущего подключения
- [x] Multiple SFTP tabs per connection
- [x] SFTP-only connect — через context menu "SFTP Only"
- [x] `lib/providers/transfer_provider.dart` — Riverpod provider
- [x] Тесты: sftp models, transfer manager, format utils (53 теста всего)

## Phase 4: Polish & UX (v0.4) ✅

**Goal:** Доводка UI/UX до production-качества

- [x] Tab bar improvements
    - [x] Drag-to-reorder вкладок (ReorderableListView)
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
    - [ ] Keyboard toolbar for terminal (deferred to Phase 10)

## Phase 5: Data Portability & Security (v0.5)

**Goal:** Безопасное хранение, экспорт/импорт, шифрование

- [x] Secure credential storage
    - [x] AES-256-GCM encrypted file via pointycastle (pure Dart, no OS deps)
    - [x] Key data (PEM) + passwords + passphrases in `credentials.enc`
    - [x] JSON-файл сессий содержит только non-secret поля
    - [x] Migration: import plaintext sessions → encrypted storage (auto on load)
- [x] Export/Import
    - [x] Формат `.lfs` (LetsFLUTssh archive) — ZIP + AES-256-GCM
    - [x] Export: sessions (с credentials) + config + known_hosts
    - [x] Import: merge/replace mode, config + known_hosts import
    - [x] Master password → PBKDF2-SHA256 (100k iterations) → AES-256-GCM
    - [x] Drag&drop `.lfs` файла в окно → автоимпорт
- [x] Settings → Export Data / Import Data

## Phase 6: Advanced Features (v0.6) ✅

**Goal:** Terminal search, session folders, auto-detect SSH keys

- [x] Terminal search (Ctrl+Shift+F)
    - [x] Поиск по scrollback buffer
    - [x] Highlight matches
    - [x] Next/Previous navigation
- [x] Session panel: create folders via context menu (right-click on group or empty space)
- [x] Auto-detect SSH keys from ~/.ssh/ (id_rsa, id_ed25519, id_ecdsa)

## Phase 7: Tiling & Split Terminals (v0.7) ✅

**Goal:** Мульти-терминал layout (как tmux/Terminator/VS Code)

- [x] Split-view внутри вкладки
    - [x] Vertical split (left | right terminals)
    - [x] Horizontal split (top / bottom terminals)
    - [x] Recursive splitting (quad layout и т.д.)
    - [x] Drag to resize splits
    - [x] Focus indicator (blue border on active pane)
    - [x] Keyboard shortcuts: Ctrl+Shift+D (split right), Ctrl+Shift+E (split down), Ctrl+Shift+W (close pane)
    - [x] Context menu: Split Right / Split Down / Close Pane
    - [x] Each pane opens its own SSH shell on shared Connection

## Phase 8: Mobile (v0.8)

**Goal:** Полноценная мобильная версия (Android + iOS)

- [ ] Адаптивный UI
    - [ ] Sidebar → bottom navigation / drawer
    - [ ] File browser → single pane with toggle
    - [ ] Full-screen terminal
- [ ] Virtual keyboard
    - [ ] SSH-specific keys panel: Ctrl, Esc, Tab, Alt, arrows, F1-F12
    - [ ] Configurable key layout
    - [ ] Swipe gestures (left/right = tab switch, up = keyboard)
- [ ] Touch terminal
    - [ ] Long press → context menu (copy/paste)
    - [ ] Pinch to zoom (font size)
    - [ ] Swipe up/down = scrollback
- [ ] Platform integration
    - [ ] URL scheme: `letsflutssh://connect?host=...`
    - [ ] Share intent: receive SSH key files
    - [ ] Notification for active sessions in background
- [ ] Android build (APK + AAB)
- [ ] iOS build

## Phase 9: Stable Release (v1.0)

**Goal:** Production-ready release

- [ ] Полное покрытие тестами (unit + widget + integration)
- [x] CI/CD (GitHub Actions)
    - [x] flutter analyze + flutter test on PR
    - [x] Build artifacts: Linux, Windows, macOS, Android APK
- [ ] Packaging
    - [ ] Linux: AppImage, deb, snap
    - [ ] Windows: MSIX, portable zip
    - [ ] macOS: dmg
    - [ ] Android: Play Store / F-Droid
- [ ] Performance profiling и оптимизация
- [ ] Security audit (credential storage, SSH implementation)
- [ ] Документация пользователя

## Phase 10: Post-Release Polish (v1.x)

**Goal:** Продвинутые фичи, не блокирующие стабильный релиз

- [ ] Port forwarding
    - [ ] Local forwarding (localPort → remoteHost:remotePort)
    - [ ] Remote forwarding (remotePort → localHost:localPort)
    - [ ] Dynamic/SOCKS proxy (если dartssh2 поддерживает)
    - [ ] UI: список активных tunnels, add/remove
- [ ] SSH tunneling через jump host
    - [ ] ProxyJump equivalent (SSH → SSH chain)
- [ ] Multi-exec
    - [ ] Выбрать несколько сессий → выполнить команду на всех одновременно
    - [ ] Результаты в отдельных панелях (side by side)
- [ ] Session logging
    - [ ] Запись вывода терминала в файл
    - [ ] Timestamp каждой строки
    - [ ] Auto-log option per session
- [ ] Broadcast input to all panes (type once → send to all)
- [ ] Synchronized scrolling (optional)
- [ ] Biometric auth for opening app / accessing credentials
- [ ] Keyboard toolbar for terminal (mobile SSH keys: Ctrl, Esc, Tab, Alt, arrows, F1-F12)

---

## Текущий статус

**Активная фаза:** Phase 8 (Mobile) — следующая
**Прогресс:** Phases 1-7 завершены. v0.7.1 — OneDark theme, cleanup (removed unused deps, split file_pane.dart, added logging). 62 теста.

### Порядок работы

Фазы 1-3 — core функционал (terminal, sessions, file browser). Это MVP.
Фаза 4 — polish до юзабельного состояния.
Фазы 5-6 — security, search, advanced UX.
Фаза 7 — tiling/split terminals.
Фаза 8 — mobile.
Фаза 9 — стабильный релиз.
Фаза 10 — post-release polish (port forwarding, multi-exec, logging, etc.)

### Оценка трудоёмкости

| Phase | Описание              | Сложность                                                      |
| ----- | --------------------- | -------------------------------------------------------------- |
| 1 ✅  | Foundation + Terminal | Medium (dartssh2 + xterm.dart делают основную работу)          |
| 2 ✅  | Session Manager       | Medium (UI-heavy, но простая логика)                           |
| 3 ✅  | SFTP File Browser     | Hard (много UI: dual-pane, drag&drop, history)                 |
| 4 ✅  | Polish & UX           | Medium (доводка существующего)                                 |
| 5 ✅  | Security & Export     | Medium (pointycastle AES-256-GCM + archive ZIP)                |
| 6 ✅  | Advanced UX           | Medium (terminal search, session folders, key improvements)    |
| 7 ✅  | Tiling                | Medium (recursive split layout)                                |
| 8     | Mobile                | Hard (адаптивный UI + virtual keyboard + platform integration) |
| 9     | Release               | Medium (CI/CD + packaging + testing)                           |
| 10    | Post-Release Polish   | Hard (port forwarding, multi-exec, jump hosts)                 |
