# LetsFLUTssh — Development Guide

## Project Overview

LetsFLUTssh — lightweight cross-platform SSH/SFTP client with GUI, written in Dart/Flutter.
Open-source alternative to Xshell/Termius, multi-platform (desktop + mobile).
Target platforms: Windows, Linux, macOS, Android, iOS.

**Predecessor:** LetsGOssh (Go/Fyne) — full feature port + improvements.

## Working Agreements

### Commits

- **User commits manually** — Claude only suggests commit messages
- Format: `type: short description` (e.g. `feat: phase 1 — SSH terminal with xterm.dart`)
- Types: `feat`, `fix`, `refactor`, `docs`, `chore`
- Repository is **public** on GitHub

### Work Style

- Documentation is maintained in English (PLAN.md, README.md, CLAUDE.md, SECURITY.md)
- PLAN.md, CLAUDE.md, README.md **updated on every significant change**
- All architectural/UX patterns documented in CLAUDE.md at the time of implementation
- SSH keys accepted **both as file and text** (paste PEM) — key requirement
- Easy data transfer between devices — priority feature (`.lfs` archive format)
- Session grouping — tree with nested subfolders (e.g. `Production/Web/nginx1`)

### Versioning Strategy

SemVer with two maturity stages: `MAJOR.MINOR.PATCH[-beta.N]`

**Stages:**

| Stage         | When to use                                         | Meaning                  |
| ------------- | --------------------------------------------------- | ------------------------ |
| `beta.N`      | Feature works but not battle-tested on real servers | "Can try, bugs expected" |
| _(no suffix)_ | Beta survived 1-2 weeks without critical bugs       | "Production-ready"       |

No `rc` stage — unnecessary overhead for a small team. Can be introduced later if external testers or contributors need a "feature freeze" signal.

**Version bump rules — always bump MAJOR.MINOR.PATCH, regardless of stage:**

| Change type                                                | Bump      | Example                                       |
| ---------------------------------------------------------- | --------- | --------------------------------------------- |
| Bug fix                                                    | **patch** | 1.0.0-beta.1 → 1.0.1-beta.1, or 1.0.2 → 1.0.3 |
| New feature                                                | **minor** | 1.0.x → 1.1.0-beta.1, or 1.1.0 → 1.2.0        |
| Major rework or breaking change (file format, API, crypto) | **major** | 1.x.y → 2.0.0-beta.1                          |

**No version bump needed for:** tests, refactoring (no behavior change), docs, CI configs, linter fixes. These are `test:`/`refactor:`/`docs:`/`chore:` commits without a version bump.

Stage suffix (`-beta.N`) tracks maturity, not content changes. When a bugfix lands during beta, bump patch AND reset stage counter to 1:

```
v1.0.0-beta.1 → bugfix → v1.0.1-beta.1 → bugfix → v1.0.2-beta.1 → stable 2 weeks → v1.0.2
```

**Transition criteria:**

- **beta → stable:** all tests green (analyze + test), coverage ≥80% (SonarCloud QG), manual testing on 2+ platforms with real SSH servers, no known crashes or data loss, beta lives 1-2 weeks with no critical bugs; critical bug found → fix → bump patch → new beta.1 → timer resets
- **stable → next beta:** new feature (port forwarding, multi-exec, etc.) is functional enough to demo

**Tagging workflow:**

1. Bump version in `pubspec.yaml` (change MAJOR.MINOR.PATCH and/or stage suffix)
2. Commit: `chore: bump version to X.Y.Z[-beta.N]`
3. Tag: `git tag vX.Y.Z[-beta.N]` on HEAD
4. Push tag: `git push origin vX.Y.Z[-beta.N]`
5. CI creates GitHub Release (pre-release for beta, Latest for stable)

**Stable release from beta (no changes needed):**

```bash
# Update pubspec.yaml: remove -beta.N suffix (keep same MAJOR.MINOR.PATCH) → commit
git tag v1.0.2        # same version, just without stage
git push origin v1.0.2
```

**Example full lifecycle:**

```
v1.0.0-beta.1 → bugfix → v1.0.1-beta.1 → 2 weeks stable → v1.0.1
v1.0.1 → bugfix → v1.0.2
v1.0.2 → new feature → v1.1.0-beta.1 → 2 weeks stable → v1.1.0
v1.1.0 → major rework → v2.0.0-beta.1
```

Old beta tags stay in history — they document the path to release.

### Post-change workflow (mandatory after every significant change)

1. **Version bump** — bump version in `pubspec.yaml` (see Versioning Strategy above)
2. **CLAUDE.md** — update Current State and module descriptions; document **why** a decision was made
3. **README.md** — update if the change is user-visible
4. **PLAN.md** — update phase checkmarks and current status if applicable
5. **SECURITY.md** — update if security scope changes (new crypto, auth methods, etc.)
6. **Commit** — suggest a one-line message in `type: short description` format (user commits manually)

### Dependencies

- Always use **latest stable versions** of packages (latest pub.dev release)
- If a package has no stable release — use latest pre-release version compatible with current SDK
- **No OS-level dependencies** — app must build with just Flutter SDK, no `apt install` / `brew install` required. Flutter plugins that bundle their own native code (desktop_drop, path_provider, permission_handler) are fine — they compile as part of the Flutter build

### Building

- **Always build via Makefile** — `make run`, `make build-linux`, `make test`, `make analyze`, etc.
- Do not call `flutter build` / `flutter run` directly — Makefile wraps them with correct flags and environment

### What Not To Do

- Do not commit automatically, do not push
- Do not install packages without asking (user approves)
- **All code must have tests** — target 100% coverage on new code AND overall; 80% is the hard minimum (SonarCloud Quality Gate), never the goal; write tests for every testable line
    - After writing code: run `make test`, check uncovered lines, keep writing tests until all testable lines are covered
    - Only skip lines that physically cannot be tested (real SSH server, native file I/O with path_provider)
    - Before suggesting commit: `make analyze` + `make test`
    - **SonarCloud verification** — when working on test coverage, always check SonarCloud API for real numbers (both overall and new code coverage). Local `lcov.info` may lag behind. Use:
        - Overall: `curl -s "https://sonarcloud.io/api/measures/component?component=Llloooggg_LetsFLUTssh&metricKeys=coverage,uncovered_lines"`
        - New code: `curl -s "https://sonarcloud.io/api/measures/component?component=Llloooggg_LetsFLUTssh&metricKeys=new_coverage,new_uncovered_lines,new_lines_to_cover"`
        - Per-file: `curl -s "https://sonarcloud.io/api/measures/component_tree?component=Llloooggg_LetsFLUTssh&metricKeys=uncovered_lines,coverage&strategy=leaves&ps=50&s=metric&metricSort=uncovered_lines&asc=false"`
- **Parallel agents** — multiple agents may work in the same repo simultaneously:
    - Only `git add` files YOU changed — never stage unrelated changes from other agents
    - Before committing, run `git status` and verify every staged file is yours
    - If you see untracked/modified files you didn't touch — leave them alone
- **Version gatekeeper** — before suggesting a commit, check if the change requires a version bump per Versioning Strategy above. If it does (bugfix → patch, feature → minor, breaking → major), remind the user to bump. If it doesn't (tests, docs, refactor, CI), explicitly say no bump needed

## Tech Stack

- **Language:** Dart 3.x (null-safe)
- **Framework:** Flutter 3.x — cross-platform native rendering (Skia/Impeller)
- **SSH:** `dartssh2` ^2.15.0 — SSH2 protocol (connect, auth, shell, SFTP, port forwarding)
- **Terminal:** `xterm` ^4.0.0 — VT100/xterm terminal widget (256-color, RGB, mouse, scrollback)
- **Secure storage:** `pointycastle` ^4.0.0 — AES-256-GCM encrypted credential file (pure Dart, no OS deps)
- **File picker:** `file_picker` ^10.3.10 — native file/directory picker
- **File drop:** `desktop_drop` ^0.7.0 — OS drag&drop into app (desktop)
- **Data dir:** `path_provider` ^2.1.5 — platform-specific app data paths
- **Permissions:** `permission_handler` ^12.0.1 — runtime permission requests (Android storage access)
- **State management:** `riverpod` ^2.x — reactive state (sessions, connections, transfers)
- **Serialization:** `json_serializable` + `freezed` — immutable models with JSON

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
├── test/                            # Unit + widget tests (mirror tree)
├── assets/icons/                    # App icons
├── pubspec.yaml                     # Dependencies, version
├── analysis_options.yaml            # Lint rules
├── CLAUDE.md                        # This file
├── README.md
└── PLAN.md                          # Step-by-step dev plan
```

## Key Design Principles

1. **Feature-first structure** — each feature (terminal, file_browser, session_manager) is an isolated module with UI + logic
2. **Core is UI-agnostic** — `core/` does not import Flutter; can be reused in a CLI tool
3. **Riverpod for state** — single source of truth for all state (sessions, connections, config, transfers)
4. **Immutable models** — all data classes via `freezed` (copyWith, equality, JSON serialization)
5. **FileSystem interface** — abstraction for local/remote file access
6. **No SCP** — dartssh2 doesn't support SCP; SFTP covers all use cases
7. **Tree-based sessions** — nested groups via `/` separator, stored as flat list with group path

## Current State (v0.9.5)

### Features by category

| Category          | What works                                                                                                                                                                                                                             |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **SSH**           | dartssh2 (password, key file, key text), auth chain (key→text→password), keep-alive, TOFU known hosts (explicit accept, no auto-trust), auto-detect keys from ~/.ssh/, tiling split layout (like tmux), terminal search (Ctrl+Shift+F) |
| **SFTP**          | Dual-pane (local\|remote), upload/download/mkdir/delete/rename/chmod, drag&drop between panes + from OS, marquee selection, sortable columns with owner, transfer queue (parallel workers), transfer history                           |
| **Sessions**      | JSON persistence + AES-256-GCM encrypted credentials, CRUD/duplicate, nested tree groups, search/filter, drag&drop reorder, empty folders, unified New Session dialog (connect-only or save&connect)                                   |
| **Tabs**          | Multi-tab (terminal + SFTP), drag-to-reorder, IndexedStack state preservation, context menu (close/close others/close right)                                                                                                           |
| **Security**      | AES-256-GCM credential storage (pointycastle, pure Dart), chmod 600, PBKDF2 600k iterations for .lfs export, error message sanitization (no file paths), deep link URI validation (path traversal rejection)                           |
| **Export/Import** | `.lfs` archive (ZIP + AES-256-GCM), merge/replace import modes, auto-migration from plaintext                                                                                                                                          |
| **Mobile**        | Bottom nav, SSH virtual keyboard (sticky modifiers), pinch-to-zoom, single-pane SFTP, long-press selection, swipe navigation, deep links (`letsflutssh://`), file open intents (.pem/.key/.lfs)                                        |
| **UI**            | OneDark/One Light themes, responsive layout (sidebar→drawer <600px), toast notifications, settings screen, no animations (instant UX)                                                                                                  |
| **CI/CD**         | GitHub Actions (analyze+test+build), SonarCloud (coverage QG ≥80%), CodeQL weekly scan, packaging (AppImage/deb/tar.gz, EXE/zip, dmg, per-ABI APK)                                                                                     |
| **Code quality**  | Injectable factories for testability, mockito mocks, consistent error handling (no silent catch), proper dispose() chains, immutable tiling tree updates, model equality (==/hashCode)                                                 |

### Decisions and Why

**API gotchas (dartssh2 / xterm / Flutter):**

- `SSHConnectionState` not `ConnectionState` — name conflict with Flutter's async.dart
- dartssh2 host key callback: `FutureOr<bool> Function(String type, Uint8List fingerprint)`, not SSHPublicKey
- dartssh2 SFTP API: `attr.mode?.value` (not `attr.permissions?.mode`), `remoteFile.writeBytes()` (not `write()`)
- xterm.dart copy/paste: built-in Actions for CopySelectionTextIntent/PasteTextIntent
- `hardwareKeyboardOnly: true` on desktop — xterm.dart TextInputClient broken on Windows; KeyEvent.character works

**Architecture choices:**

- `pointycastle` instead of `encrypt` — version conflict with dartssh2 (both need pointycastle, different major versions)
- `CredentialStore` instead of `flutter_secure_storage` — pure Dart, no OS-specific native deps
- `app_links` instead of `uni_links` — more up-to-date, desktop support
- `FilePaneController` as `ChangeNotifier` — lightweight per-pane state without Riverpod overhead
- `TransferManager` with `Stream` — Riverpod StreamProvider subscribes to onChange
- Sealed class `SplitNode` — recursive split tree (LeafNode | BranchNode), exhaustive switch
- Each terminal pane → own SSH shell — `openShell()` per LeafNode, shared `SSHConnection`
- `Listener` instead of `GestureDetector` for marquee — raw pointer events don't conflict with `Draggable`
- `IndexedStack` for tabs — preserves terminal state when switching
- Separate `features/mobile/` — fundamentally different interaction patterns (no marquee, no right-click, no tiling)
- Empty groups in `empty_groups.json` — separate from sessions for clean session list
- Global `navigatorKey` for host key dialog — callbacks need Flutter context without binding to specific widget

**Security decisions:**

- PBKDF2 600k iterations — OWASP 2024 recommendation
- chmod 600 on credential files — prevents other users from reading on Unix
- TOFU reject without callback — no auto-accept; prevents MITM when no dialog available
- Deep link path traversal rejection — `..` in key path blocked
- Error message sanitization — file paths stripped from user-facing errors
- `CredentialStoreException` on decryption failure — callers distinguish "no credentials" from "corrupt key"
- SessionStore aborts on credential load failure — prevents overwriting encrypted store with partial data
- Key generation race guard — `_keyGenInProgress` flag prevents concurrent key generation
- `RandomAccessFile` for SFTP upload — `try/finally` guarantees file handle cleanup (replaces stream approach)

**Platform-specific:**

- Android home directory: `EXTERNAL_STORAGE` env var with `/storage/emulated/0` fallback
- `MANAGE_EXTERNAL_STORAGE` — file manager needs full filesystem access; older permissions with `maxSdkVersion`
- `NSLocalNetworkUsageDescription` — iOS blocks TCP to local network without it
- `AnimationStyle.noAnimation` everywhere — Flutter 3.41+ supports it on showMenu/showDialog

## Security & Data Portability

- Credentials encrypted with AES-256-GCM (stored separately from session metadata in `credentials.enc`)
- Encryption key: 256-bit random, stored in `credentials.key` alongside encrypted file
- File permissions restricted (chmod 600) on Unix systems (credentials.enc, credentials.key, known_hosts)
- Known hosts verification (TOFU) — explicit user confirmation required, no auto-accept
- Data export/import to `.lfs` archive: ZIP + AES-256-GCM, master password → PBKDF2-SHA256 600k iterations → 256-bit AES key
- Format: `[salt 32B] [iv 12B] [encrypted ZIP + GCM tag]`
- Import modes: merge (add new, skip existing) / replace (delete all, import fresh)
- Auto-migration from plaintext to encrypted storage on upgrade
- Deep link URI validation: host format, port range 1-65535, path traversal rejection
- Error messages sanitized: file paths stripped from user-facing errors

## Conventions

- Use `dart:developer` `log()` for structured logging
- Error wrapping: custom exception classes with `cause` field
- No global mutable state — all state via Riverpod providers
- UI updates automatic via Riverpod (no manual setState except in leaf widgets)
- Models: `freezed` for immutability + `json_serializable` for JSON
- Passwords/keys: stored in `CredentialStore` (AES-256-GCM encrypted file), NOT in plain JSON
- Test files: `*_test.dart` in `test/` mirror tree
- Lint rules: `flutter_lints` + additional (prefer_const_constructors, etc.)
- Platform-specific code: isolated behind `Platform.isX` checks or separate files
- OneDark theme: centralized palette in `lib/theme/app_theme.dart`; semantic color constants; no hardcoded Colors
