# LetsFLUTssh — Development Plan

## Phase 1: Foundation + Terminal (v0.1)

**Goal:** Минимальный рабочий SSH-клиент с терминалом. Подключение, ввод, отображение.

- [x] Создать Flutter-проект (`flutter create`)
- [x] Настроить `pubspec.yaml` (зависимости: dartssh2, xterm, riverpod, path_provider, flutter_secure_storage)
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
    - [ ] Диалог подтверждения нового ключа (TOFU auto-accept, диалог в Phase 4)
- [x] `lib/features/terminal/` — Terminal tab
    - [x] `TerminalTab` widget: `xterm.TerminalView` подключённый к SSH shell
    - [x] Pipe: SSH stdout → xterm Terminal.write(); xterm onOutput → SSH stdin
    - [x] `onResize` → `SSHConnection.resizeTerminal()`
    - [x] Ctrl+Shift+C/V — copy/paste (из коробки xterm.dart — встроенные Actions)
    - [ ] Right-click context menu (Copy / Paste) — Phase 4
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
- [ ] Первый рабочий билд (Linux desktop) — требует ручной проверки
- [ ] Тест: подключение к SSH серверу, команды, htop, vim — требует ручной проверки

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

## Phase 3: SFTP File Browser (v0.3)

**Goal:** Двухпанельный файловый менеджер (local | remote) с drag&drop

- [ ] `lib/core/sftp/` — SFTP клиент
    - [ ] `SFTPService` — обёртка над dartssh2 SFTP
        - [ ] `list(path)` → sorted (dirs first, alphabetical)
        - [ ] `upload(local, remote, onProgress)` — с progress callback
        - [ ] `download(remote, local, onProgress)` — с progress callback
        - [ ] `uploadDir(localDir, remoteDir, onProgress)` — recursive
        - [ ] `downloadDir(remoteDir, localDir, onProgress)` — recursive
        - [ ] `mkdir`, `remove`, `removeDir`, `rename`, `chmod`, `stat`, `getwd`
    - [ ] `FileSystem` interface + `LocalFS` + `RemoteFS`
    - [ ] `FileEntry` модель: name, path, size, mode, modTime, isDir
    - [ ] `TransferProgress` модель: fileName, totalBytes, doneBytes, percent
- [ ] `lib/core/transfer/` — transfer manager
    - [ ] `TransferManager` — очередь задач + parallel workers (configurable)
    - [ ] `TransferTask` — name, direction (upload/download), source, target, run function
    - [ ] `HistoryEntry` — id, name, direction, status, error, duration, timestamps
    - [ ] `clearHistory()`, `deleteHistory(ids)`
- [ ] `lib/features/file_browser/` — UI файлового менеджера
    - [ ] Split-pane: local (left) | remote (right) — resizable divider
    - [ ] `FilePane` — generic single-pane file list
        - [ ] DataTable: Name, Size, Mode, Modified — click-to-sort headers (▲/▼)
        - [ ] Dirs always first in sort
        - [ ] Double-click folder → navigate
        - [ ] Editable path bar (Enter → navigate)
        - [ ] Back / Forward buttons с историей навигации
        - [ ] Refresh button
        - [ ] Multi-select (Ctrl+click, Shift+click)
    - [ ] Context menu (right-click on file):
        - [ ] Download / Upload (в зависимости от панели)
        - [ ] Rename
        - [ ] Delete (с confirm dialog)
        - [ ] New Folder
        - [ ] Properties (name, path, size, mode, isDir)
    - [ ] Internal drag&drop между панелями
        - [ ] Drag из local → drop в remote = upload
        - [ ] Drag из remote → drop в local = download
        - [ ] Visual feedback (highlight target pane)
    - [ ] OS drag&drop (`desktop_drop`)
        - [ ] Drop файлов из файлового менеджера ОС в remote pane → auto upload
    - [ ] Transfer panel (bottom, collapsible)
        - [ ] Progress bar для текущей передачи
        - [ ] History table: Time, Direction (↑/↓), File, Source, Target, Status, Elapsed, Info
        - [ ] Sortable columns
        - [ ] Auto-reveal при начале передачи
        - [ ] Toggle bar "▲ Transfers" для collapse
        - [ ] Clear history / delete entry
- [ ] SFTP кнопка в toolbar → открывает SFTP tab для текущего подключения
- [ ] Multiple SFTP tabs per connection
- [ ] SFTP-only connect (SSH в фоне, без terminal tab)
- [ ] `lib/providers/transfer_provider.dart` — Riverpod provider
- [ ] Тесты: FileSystem interface, transfer manager queue, history

## Phase 4: Polish & UX (v0.4)

**Goal:** Доводка UI/UX до production-качества

- [ ] Tab bar improvements
    - [ ] Drag-to-reorder вкладок
    - [ ] Context menu: close, close others, reconnect
    - [ ] Keyboard: Ctrl+Tab (next), Ctrl+Shift+Tab (prev), Ctrl+1..9
    - [ ] Color indicator: green = connected, red = disconnected, gray = connecting
- [ ] Toast notifications
    - [ ] Non-blocking popup (right side)
    - [ ] Levels: Info, Warning, Error, Success
    - [ ] Auto-dismiss timer (configurable)
    - [ ] Dismiss button
- [ ] Key field improvements
    - [ ] Drag&drop key file into field (desktop_drop zone on key input)
    - [ ] Auto-detect PEM format on paste
- [ ] Reconnect logic
    - [ ] Terminal tab: error state → Reconnect / Close buttons
    - [ ] Auto-reconnect option (future)
- [ ] Toolbar
    - [ ] Quick Connect button
    - [ ] SFTP button (visible only when SSH connected)
    - [ ] Tooltips on all buttons
- [ ] Settings screen (basic)
    - [ ] Theme (dark / light / system)
    - [ ] Font size
    - [ ] Scrollback lines
    - [ ] Keep-alive interval
    - [ ] Default port
    - [ ] Transfer workers count
- [ ] Status bar
    - [ ] Connection state
    - [ ] Transfer progress summary
- [ ] Mobile adaptations (basic)
    - [ ] Responsive layout (sidebar → drawer on small screens)
    - [ ] Touch-friendly hit targets
    - [ ] Keyboard toolbar with Ctrl/Esc/Tab/arrows for terminal

## Phase 5: Data Portability & Security (v0.5)

**Goal:** Безопасное хранение, экспорт/импорт, шифрование

- [ ] Secure credential storage
    - [ ] Passwords хранятся в flutter_secure_storage (OS keychain)
    - [ ] Key data (PEM) хранятся в flutter_secure_storage
    - [ ] JSON-файл сессий содержит только non-secret поля
    - [ ] Migration: import plaintext sessions → secure storage
- [ ] Export/Import
    - [ ] Формат `.lfs` (LetsFLUTssh archive) — ZIP + AES-256-GCM
    - [ ] Export: sessions + config + known_hosts + SSH keys (опционально)
    - [ ] Import: превью содержимого, выбор merge/replace
    - [ ] Master password для шифрования архива
    - [ ] Drag&drop `.lfs` файла в окно
- [ ] Settings → Export Data / Import Data

## Phase 6: Advanced Features (v0.6)

**Goal:** Port forwarding, multi-exec, session logging

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
- [ ] Terminal search (Ctrl+Shift+F)
    - [ ] Поиск по scrollback buffer
    - [ ] Highlight matches

## Phase 7: Tiling & Split Terminals (v0.7)

**Goal:** Мульти-терминал layout (как tmux/Terminator/VS Code)

- [ ] Split-view внутри вкладки
    - [ ] Vertical split (left | right terminals)
    - [ ] Horizontal split (top / bottom terminals)
    - [ ] Recursive splitting (quad layout и т.д.)
    - [ ] Drag to resize splits
- [ ] Broadcast input to all panes (type once → send to all)
- [ ] Synchronized scrolling (optional)

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
- [ ] Biometric auth for opening app / accessing credentials
- [ ] Android build (APK + AAB)
- [ ] iOS build

## Phase 9: Import from LetsGOssh (v0.x)

**Goal:** Миграция данных из старой Go-версии

- [ ] Import sessions from `~/.letsgossh/sessions.json`
    - [ ] Map fields: label, group, host, port, user, authType, password, keyPath, keyData
    - [ ] Migrate passwords to flutter_secure_storage
- [ ] Import config from `~/.letsgossh/config.json`
- [ ] Import known_hosts from `~/.letsgossh/known_hosts`
- [ ] Auto-detect on first launch (если `~/.letsgossh/` существует → предложить импорт)

## Phase 10: Stable Release (v1.0)

**Goal:** Production-ready release

- [ ] Полное покрытие тестами (unit + widget + integration)
- [ ] CI/CD (GitHub Actions)
    - [ ] flutter analyze + flutter test on PR
    - [ ] Build artifacts: Linux, Windows, macOS, Android APK
- [ ] Packaging
    - [ ] Linux: AppImage, deb, snap
    - [ ] Windows: MSIX, portable zip
    - [ ] macOS: dmg
    - [ ] Android: Play Store / F-Droid
    - [ ] iOS: TestFlight / App Store
- [ ] Auto-updater (desktop)
- [ ] Performance profiling и оптимизация
- [ ] Security audit (credential storage, SSH implementation)
- [ ] Документация пользователя
- [ ] Website / landing page

---

## Текущий статус

**Активная фаза:** Phase 2 (Session Manager) — завершена
**Прогресс:** Phase 1 + Session Manager. Sidebar с TreeView, search, context menu, CRUD, группы. 28 тестов, 0 issues.

### Порядок работы

Фазы 1-3 — core функционал (terminal, sessions, file browser). Это MVP.
Фаза 4 — polish до юзабельного состояния.
Фазы 5-7 — advanced features.
Фаза 8 — mobile.
Фаза 9 — миграция с LetsGOssh (может быть раньше, если нужно).
Фаза 10 — стабильный релиз.

### Оценка трудоёмкости

| Phase | Описание | Сложность |
|-------|----------|-----------|
| 1 | Foundation + Terminal | Medium (dartssh2 + xterm.dart делают основную работу) |
| 2 | Session Manager | Medium (UI-heavy, но простая логика) |
| 3 | SFTP File Browser | Hard (много UI: dual-pane, drag&drop, history) |
| 4 | Polish & UX | Medium (доводка существующего) |
| 5 | Security & Export | Medium (flutter_secure_storage + zip/crypto) |
| 6 | Advanced | Hard (port forwarding, multi-exec) |
| 7 | Tiling | Medium (recursive split layout) |
| 8 | Mobile | Hard (адаптивный UI + virtual keyboard + platform integration) |
| 9 | Import | Easy (JSON parsing + mapping) |
| 10 | Release | Medium (CI/CD + packaging + testing) |
