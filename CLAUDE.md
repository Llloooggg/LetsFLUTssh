# LetsFLUTssh — Development Guide

## Project Overview

LetsFLUTssh — lightweight cross-platform SSH/SFTP client with GUI, written in Dart/Flutter.
Open-source alternative to Xshell/Termius. Platforms: Windows, Linux, macOS, Android, iOS.

**Solo developer project** — no team, no second reviewer. Scorecard checks like Code-Review and Branch-Protection assume multi-person teams; some findings are expected and acceptable for a solo project.

**Predecessor:** LetsGOssh (Go/Fyne) — full feature port + improvements.

## Working Agreements

### Commits

- **Claude does not commit or push unless the user explicitly asks.** When asked — scope matches what was said: "commit" = commit only, "commit and push" = commit + push (auto-tag handles the rest). When the user asks to do multiple fixes — commit each fix immediately after finishing it (see below), don't wait for the whole batch
- **Every commit that affects the shipped app MUST include a version bump** in `pubspec.yaml` (the only source of truth — `package_info_plus` reads it at runtime). Includes: `lib/`, platform configs, native code, assets, build settings. Patch for bugfix/refactor, minor for new feature, major for breaking change. No exceptions
- Format: `type: short description` — types: `feat`, `fix`, `refactor` (app changes), `test`, `docs`, `chore`, `ci` (non-app)
- **Commit messages drive auto-changelog** — `feat:` → Features, `fix:` → Fixes, `refactor:` → Improvements. Keep messages user-readable. If commit has both app changes and docs — prefix describes the app change only
- **One fix / one commit** — each logical change is a separate commit. Do not bundle unrelated fixes
- **Commit immediately after each fix** — when working on multiple fixes, commit each one right after finishing it (code + tests + version bump), then start the next. Never accumulate and batch-commit at the end
- Repository is **public** on GitHub

### Work Style

- Documentation in English (README.md, CLAUDE.md, SECURITY.md), updated on every significant change
- SSH keys accepted **both as file and text** (paste PEM) — key requirement
- Easy data transfer between devices — `.lfs` archive format
- Session grouping — tree with nested subfolders (e.g. `Production/Web/nginx1`)
- **Cross-platform verification** — Android change → also check iOS; Windows change → also check Linux + macOS. Verify all sibling platforms before committing

### Versioning & Tagging

Plain SemVer: `MAJOR.MINOR.PATCH`. Bump: patch (bugfix/refactor), minor (feature), major (breaking).

**No bump needed for:** tests, docs, CI, linter fixes. **Bump IS needed for:** any `lib/` change (including logging), platform configs, native code, assets.

**Tagging — fully automated via `auto-tag.yml`:**

Just `git push` — everything else is automatic:

1. Push triggers CI (analyze + test)
2. CI passes → `auto-tag.yml` fires (also triggers `sonarcloud.yml` for quality scan)
3. auto-tag fetches commit message via GitHub API (no untrusted input in shell/env — Scorecard safe), checks prefix
4. If prefix is `feat:` / `fix:` / `refactor:` → reads version from `pubspec.yaml`, creates annotated tag `v{VERSION}` via API using `RELEASE_TOKEN`
5. Tag triggers Build & Release workflow → preflight waits for CI (required) + SonarCloud (warn-only) + OSV-Scanner (required) → build all platforms → create GitHub Release

**HEAD must be a taggable commit.** auto-tag only inspects the HEAD commit message. If HEAD is `test:`, `docs:`, `ci:`, or `chore:` — no tag is created even if prior commits have version bumps.

| Scenario                    | What to do                                                          |
| --------------------------- | ------------------------------------------------------------------- |
| App change (feat/fix/refac) | `git push` — auto-tag handles it                                   |
| App change + tests/docs     | Bundle tests/docs into the app commit, OR make sure the app commit is pushed last |
| Tests/docs/CI only          | `git push` — no tag, no release (correct behavior)                  |
| Dependabot deps             | Auto: merge → version bump → CI → `dependabot-tag.yml`             |
| Failed build (re-trigger)   | `gh workflow run build.yml --ref v{VERSION}` (manual dispatch — preflight warns if Sonar/OSV not found, then proceeds) |

`make tag` exists as a **manual fallback only** (runs local checks, verifies remote CI, tags, pushes). Normal flow never needs it.

- By default Claude only reminds about tagging — does **not** run `make tag` unless user explicitly asks

**Full workflow chain:**

```
# Normal push (feat/fix/refactor) to main:
git push
  │
  ├─► ci.yml          (on: push lib/**,test/**,pubspec.*)
  │     analyze + test + upload artifacts (coverage, sonar-source)
  │           │
  │           ├─► sonarcloud.yml   (on: workflow_run[CI] completed, main only)
  │           │     downloads sonar-source + coverage artifacts
  │           │     flutter pub get → Sonar scan
  │           │     (no checkout — Scorecard safe, no untrusted ref in shell)
  │           │     manual: gh workflow run sonarcloud.yml [-f ci-run-id=<id>]
  │           │
  │           └─► auto-tag.yml     (on: workflow_run[CI] completed)
  │                 reads HEAD commit via GitHub API → feat/fix/refactor → tag v*
  │                       │
  │                       └─► build.yml   (on: push tags/v*)
  │                             preflight: waits CI (required) + OSV (required)
  │                               + SonarCloud (warn-only)
  │                             → build all platforms → GitHub Release
  │
  ├─► scorecard.yml   (on: push)      — OpenSSF Scorecard
  └─► codeql.yml      (on: push)      — CodeQL analysis

# Dependabot patch/minor merge:
PR merge → dependabot-release.yml   (on: pull_request[closed])
               bumps version in pubspec.yaml → commit
                     │
                     └─► ci.yml (on: push) → ... → dependabot-tag.yml
                                                       → build.yml → Release

# ci:/docs:/test:/chore: commits: CI does NOT trigger (paths-filter).
#   No tag, no release — correct behavior.
```

### Post-change checklist

1. Version bump in same commit (if app-affecting)
2. Update CLAUDE.md if architecture changed, README.md if user-visible, SECURITY.md if security scope changes
3. `make analyze` + `make test` must pass

### Dependencies & Building

- Latest **stable** versions only — no beta/dev/pre-release. No OS-level deps (`apt install`/`brew install`)
- **Always build via Makefile** — `make run`, `make build-linux`, `make test`, `make analyze`. Never call `flutter build`/`flutter run` directly
- **Always use Context7 MCP** for library/API docs — don't guess APIs, look them up
- **Pin external downloads in CI** — any `wget`/`curl` in workflows must use a specific release version (not rolling tags like `continuous`) and verify SHA256 checksum after download

### What Not To Do

- Do not commit/push unless explicitly asked. Do not install packages without asking
- **Never suppress issues** — no `// NOSONAR`, `// ignore:`, `@SuppressWarnings` or any other suppression mechanism. Always fix the root cause
- **Never touch `UI_REDESIGN_PLAN.md`** — do not read, edit, or commit it
- **Never amend after push** — only new commits. Amend OK only before first push
- **All code must have tests** — target 100% coverage; 80% is SonarCloud minimum, never the goal
    - After writing code: `make test`, check uncovered lines, write more tests. Only skip untestable lines (real SSH, native file I/O)
    - **SonarCloud verification** — check real numbers via API, local `lcov.info` may lag:
        - Overall: `curl -s "https://sonarcloud.io/api/measures/component?component=Llloooggg_LetsFLUTssh&metricKeys=coverage,uncovered_lines"`
        - New code: `curl -s "https://sonarcloud.io/api/measures/component?component=Llloooggg_LetsFLUTssh&metricKeys=new_coverage,new_uncovered_lines,new_lines_to_cover"`
        - Per-file: `curl -s "https://sonarcloud.io/api/measures/component_tree?component=Llloooggg_LetsFLUTssh&metricKeys=uncovered_lines,coverage&strategy=leaves&ps=50&s=metric&metricSort=uncovered_lines&asc=false"`
- **Code must be testable by design** — extract pure logic from SSH/platform/I/O deps. DI over hardcoded `ref.read()`. Interfaces for file ops. Dialog returns data, service processes it. Pure functions over closures. No duplicate logic across files
- **One test file per source file** — no `_extra_test` sprawl. Add to existing test file. Parallel agents: zero overlap in file assignments
- **Parallel agents** — only `git add` files YOU changed. Run only your own test file, never `make test`. Leave untracked/modified files from other agents alone
- **Version gatekeeper** — before suggesting commit, check if version bump needed. If yes — remind. If no — say so explicitly

## Tech Stack

- **Language:** Dart 3.x (null-safe), **Framework:** Flutter 3.x
- **SSH:** `dartssh2` ^2.15.0, **Terminal:** `xterm` ^4.0.0, **Crypto:** `pointycastle` ^4.0.0 (AES-256-GCM)
- **File drop:** `desktop_drop` ^0.7.0, **Data dir:** `path_provider` ^2.1.5
- **State:** `riverpod` ^2.x, **Serialization:** hand-written JSON (freezed planned)

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
│   │   │   ├── session_panel.dart   # Widget: tree view + search + actions + bulk select
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
└── README.md
```

## Key Design Principles

1. **Feature-first** — each feature is isolated module with UI + logic
2. **Core is UI-agnostic** — `core/` doesn't import Flutter
3. **Riverpod for state** — single source of truth
4. **Immutable models** — hand-written with copyWith, equality, JSON
5. **FileSystem interface** — abstraction for local/remote
6. **No SCP** — dartssh2 doesn't support it; SFTP covers all use cases
7. **Tree-based sessions** — nested groups via `/` separator, flat list with group path

## Current State

### Features

| Category          | What works                                                                                                                                                                                |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **SSH**           | dartssh2 (password, key file, key text), auth chain, keep-alive, TOFU known hosts, tiling split (like tmux), terminal search (Ctrl+Shift+F)                     |
| **SFTP**          | Dual-pane (local\|remote), upload/download/mkdir/delete/rename/chmod, drag&drop (panes + OS), marquee selection, sortable columns, transfer queue + history                               |
| **Sessions**      | AES-256-GCM encrypted credentials, CRUD/duplicate, nested tree groups, search/filter, drag&drop reorder, empty folders, bulk select (multi-delete/move)                                   |
| **Tabs**          | Multi-tab (terminal + SFTP), drag-to-reorder, IndexedStack state preservation, context menu                                                                                               |
| **Security**      | AES-256-GCM (pointycastle, pure Dart), chmod 600, PBKDF2 600k iterations, error sanitization, deep link validation, TOFU (no auto-accept)                                                 |
| **Export/Import** | `.lfs` archive (ZIP + AES-256-GCM), merge/replace modes, auto-migration from plaintext                                                                                                    |
| **Mobile**        | Bottom nav, SSH virtual keyboard (sticky modifiers applied to system keyboard too), pinch-to-zoom, single-pane SFTP, deep links, file open intents                                        |
| **UI**            | OneDark/One Light themes, responsive layout (sidebar→drawer <600px), toast notifications, no animations                                                                                   |
| **CI/CD**         | `ci.yml`: analyze + test + outdated deps + commit-lint. `sonarcloud.yml`: triggers after CI via `workflow_run` (main branch only, no fork PR code execution), downloads sonar-source + coverage artifacts, runs flutter pub get (no checkout — Scorecard safe), warn-only in build preflight (workflow_run check-runs attach to default branch HEAD, not tagged commit SHA). `auto-tag.yml`: after CI passes, fetches commit message via API (no untrusted input in shell), creates annotated tag for feat/fix/refactor commits. `build.yml`: preflight waits for CI (required) + SonarCloud (warn-only) + OSV-Scanner (required); manual dispatch warns and proceeds if checks not found, build provenance attestation (SLSA), packaging (AppImage/deb, EXE/zip, dmg, per-ABI APK). `dependabot-release.yml`: auto patch-bump + commit when Dependabot merges pub dependency updates. `dependabot-tag.yml`: creates tag after CI passes on the bump commit. `osv-scanner.yml`: dependency CVE scan (on pubspec change + weekly). `scorecard.yml`: OpenSSF Scorecard (on push + weekly). `codeql.yml`: Actions workflow analysis (weekly; Dart covered by SonarCloud). Dependabot version updates (pub + actions, weekly) with auto-merge for patch/minor. All actions pinned to SHA. Branch protection on main (require CI + OSV-Scanner). Top-level `permissions: read-all` on all workflows. OpenSSF Best Practices badge (passing) |

### Decisions and Why

**API gotchas (dartssh2 / xterm / Flutter):**

- `SSHConnectionState` not `ConnectionState` — name conflict with Flutter's async.dart
- dartssh2 host key: `FutureOr<bool> Function(String type, Uint8List fingerprint)`, not SSHPublicKey
- dartssh2 SFTP: `attr.mode?.value`, `remoteFile.writeBytes()` (not `.permissions?.mode`, `.write()`)
- `hardwareKeyboardOnly: true` on desktop — xterm TextInputClient broken on Windows

**Architecture choices:**

- `pointycastle` instead of `encrypt` — version conflict with dartssh2
- `CredentialStore` instead of `flutter_secure_storage` — pure Dart, no OS deps
- `app_links` instead of `uni_links` — desktop support
- `FilePaneController` as `ChangeNotifier` — lightweight per-pane state without Riverpod overhead
- Sealed class `SplitNode` — recursive split tree (LeafNode | BranchNode)
- Each terminal pane → own SSH shell, shared `SSHConnection`
- `Listener` for marquee — raw pointer events don't conflict with `Draggable`
- `IndexedStack` for tabs — preserves terminal state
- Separate `features/mobile/` — different interaction patterns
- Global `navigatorKey` for host key dialog — callbacks need Flutter context

**Security decisions:**

- PBKDF2 600k iterations (OWASP 2024), chmod 600, TOFU reject without callback
- Deep link path traversal rejection, error message sanitization (no file paths)
- `CredentialStoreException` distinguishes "no credentials" from "corrupt key"
- SessionStore aborts on credential load failure — prevents overwriting encrypted store
- `RandomAccessFile` for SFTP upload — `try/finally` guarantees file handle cleanup

**Platform-specific:**

- Android: `EXTERNAL_STORAGE` env var + `/storage/emulated/0` fallback, `MANAGE_EXTERNAL_STORAGE`
- iOS: `NSLocalNetworkUsageDescription` required for local TCP
- `AnimationStyle.noAnimation` everywhere (Flutter 3.41+)

## Conventions

- **Logging** — `AppLogger.instance.log(message, name: 'Tag')` everywhere, never `print()`/`debugPrint()`. File: `<appSupportDir>/logs/letsflutssh.log`. Disabled by default. **Never log sensitive data**. Rotation: 5 MB, 3 files
- All state via Riverpod providers — no global mutable state
- Immutable models with copyWith, ==, hashCode, toJson/fromJson
- Credentials in `CredentialStore` (AES-256-GCM), NOT in plain JSON
- OneDark theme: centralized in `app_theme.dart`, semantic color constants, no hardcoded Colors
- `.lfs` export format: `[salt 32B] [iv 12B] [encrypted ZIP + GCM tag]`, merge/replace import modes
