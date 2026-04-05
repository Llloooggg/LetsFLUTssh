# LetsFLUTssh — Development Guide

## Project Overview

LetsFLUTssh — lightweight cross-platform SSH/SFTP client with GUI, written in Dart/Flutter.
Open-source alternative to Xshell/Termius. Platforms: Windows, Linux, macOS, Android, iOS.

**Solo developer project** — no team, no second reviewer. Scorecard checks like Code-Review and Branch-Protection assume multi-person teams; some findings are expected and acceptable for a solo project.

**Predecessor:** LetsGOssh (Go/Fyne) — full feature port + improvements.

## How to Use Technical Documentation

**Primary reference:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — contains ALL architecture details, data models, API references, data flows, design decisions, and CI/CD pipeline docs.

**Rule for Claude:** Do NOT read ARCHITECTURE.md cover-to-cover. Jump to the specific section you need via the links below.

### Quick Navigation by Task

| I need to... | Read this section |
|---|---|
| Understand the module layout | [§2 Module Map](docs/ARCHITECTURE.md#2-module-map) |
| Work with SSH connections | [§3.1 SSH](docs/ARCHITECTURE.md#31-ssh-coressh) + [§9.1 SSH Flow](docs/ARCHITECTURE.md#91-ssh-connection-flow) |
| Work with SFTP / file browser | [§3.2 SFTP](docs/ARCHITECTURE.md#32-sftp-coresftp) + [§5.2 File Browser](docs/ARCHITECTURE.md#52-file-browser-featuresfile_browser) |
| Work with transfers | [§3.3 Transfer Queue](docs/ARCHITECTURE.md#33-transfer-queue-coretransfer) + [§9.4 Transfer Flow](docs/ARCHITECTURE.md#94-file-transfer-flow) |
| Work with sessions | [§3.4 Sessions](docs/ARCHITECTURE.md#34-session-management-coresession) + [§9.3 CRUD Flow](docs/ARCHITECTURE.md#93-session-crud-flow) |
| Work with connections | [§3.5 Connection Lifecycle](docs/ARCHITECTURE.md#35-connection-lifecycle-coreconnection) |
| Work with encryption/security | [§3.6 Security](docs/ARCHITECTURE.md#36-security--encryption-coresecurity) + [§13 Security Model](docs/ARCHITECTURE.md#13-security-model) |
| Work with config | [§3.7 Configuration](docs/ARCHITECTURE.md#37-configuration-coreconfig) |
| Work with terminal / tiling | [§5.1 Terminal](docs/ARCHITECTURE.md#51-terminal-with-tiling-featuresterminal) |
| Work with tabs / workspace tiling | [§5.4 Tab & Workspace System](docs/ARCHITECTURE.md#54-tab--workspace-system) |
| Work with mobile features | [§5.6 Mobile](docs/ARCHITECTURE.md#56-mobile-featuresmobile) + [§12 Platform-Specific](docs/ARCHITECTURE.md#12-platform-specific-behavior) |
| Use or create widgets | [§6 Widgets API](docs/ARCHITECTURE.md#6-widgets--public-api-reference) |
| Use utilities | [§7 Utilities API](docs/ARCHITECTURE.md#7-utilities--public-api-reference) |
| Work with theme / colors | [§8 Theme System](docs/ARCHITECTURE.md#8-theme-system) |
| Add/change user-facing strings | [§8.1 i18n](docs/ARCHITECTURE.md#81-internationalization-i18n) |
| Understand Riverpod providers | [§4 State Management](docs/ARCHITECTURE.md#4-state-management--riverpod) |
| Understand data persistence | [§11 Persistence](docs/ARCHITECTURE.md#11-persistence--storage) |
| Check data models | [§10 Data Models](docs/ARCHITECTURE.md#10-data-models) |
| Understand CI/CD / workflows | [§15 CI/CD Pipeline](docs/ARCHITECTURE.md#15-cicd-pipeline) |
| Check design decisions / gotchas | [§16 Design Decisions](docs/ARCHITECTURE.md#16-design-decisions--rationale) |
| Check dependencies / versions | [§17 Dependencies](docs/ARCHITECTURE.md#17-dependencies) |
| Write tests / understand DI | [§14 Testing Patterns](docs/ARCHITECTURE.md#14-testing-patterns--di-hooks) |

---

## Working Agreements

### Documentation Maintenance — MANDATORY

**Every code change MUST be accompanied by documentation updates.** This is non-negotiable.

| What changed | Update |
|---|---|
| New file in `lib/` | Add to [§2 Module Map](docs/ARCHITECTURE.md#2-module-map) + relevant §3/§5 section |
| New/changed class, public API | Update the corresponding §3-§8 section in ARCHITECTURE.md |
| New/changed data model | Update [§10 Data Models](docs/ARCHITECTURE.md#10-data-models) |
| New/changed provider | Update [§4 Provider Catalog](docs/ARCHITECTURE.md#42-provider-catalog) + dependency graph |
| New/changed widget | Update [§6 Widgets API](docs/ARCHITECTURE.md#6-widgets--public-api-reference) |
| New/changed utility | Update [§7 Utilities API](docs/ARCHITECTURE.md#7-utilities--public-api-reference) |
| Changed data flow | Update relevant [§9 Data Flow](docs/ARCHITECTURE.md#9-data-flow-diagrams) diagram |
| New dependency added | Update [§17 Dependencies](docs/ARCHITECTURE.md#17-dependencies) |
| Changed persistence format | Update [§11 Persistence](docs/ARCHITECTURE.md#11-persistence--storage) |
| Changed security model | Update [§13 Security Model](docs/ARCHITECTURE.md#13-security-model) + SECURITY.md |
| New design decision | Add to [§16 Design Decisions](docs/ARCHITECTURE.md#16-design-decisions--rationale) with rationale |
| New CI workflow / changed pipeline | Update [§15 CI/CD](docs/ARCHITECTURE.md#15-cicd-pipeline) |
| Platform-specific change | Update [§12 Platform-Specific](docs/ARCHITECTURE.md#12-platform-specific-behavior) |
| New DI hook for testing | Update [§14 Testing Patterns](docs/ARCHITECTURE.md#14-testing-patterns--di-hooks) |
| New/changed user-facing string | Add key to `lib/l10n/app_en.arb`, run `flutter gen-l10n`, use `S.of(context).key` |
| Architecture changed | Update this file (CLAUDE.md) if navigation links affected |
| User-visible change | Update README.md |
| Security scope change | Update SECURITY.md |

**Violation = incomplete commit.** The same commit that changes code MUST include the doc update.

### Commits

- **Claude does not commit or push unless the user explicitly asks.** "commit" = commit only, "commit and push" = commit + push
- **Every commit that affects the shipped app MUST include a version bump** in `pubspec.yaml` (the only source of truth). Includes: `lib/`, platform configs, native code, assets, build settings. Patch for bugfix/refactor, minor for new feature, major for breaking change. **No bump needed for:** tests, docs, CI, linter fixes
- Format: `type: short description` — types: `feat`, `fix`, `refactor` (app changes), `test`, `docs`, `chore`, `ci` (non-app). Messages drive auto-changelog — keep them user-readable
- **One fix / one commit** — each logical change is a separate commit. Do not bundle unrelated fixes
- **HARD STOP between fixes** — workflow is strictly sequential: implement fix → write tests → bump version → update docs → **stop and ask user to commit**. Do NOT start the next fix until the current one is committed. This is a blocking gate. After finishing a fix, present the work and prompt the user — never silently continue to the next task
- **Green CI before merging to main** — pre-commit hook runs `make check` automatically, so tests must pass before any commit. If pre-existing test failures exist, fix them first in a separate `fix:` commit with version bump
- **Version gatekeeper** — before suggesting commit, check if version bump needed. If yes — remind. If no — say so explicitly
- Repository is **public** on GitHub

### Work Style

- **All files in English only** — code, comments, commits, docs. No exceptions
- **Best practices by default** — if the user's request leads to a hacky solution, push back and propose a best-practice alternative. Only implement hacky approach if user explicitly confirms
- **Think systemically** — consider full scope and side effects, not just the literal instruction
- **UI changes = test updates** — proactively update all tests that reference changed widget names, labels, or finders. Same change, not afterthought
- **Ask before guessing UI placement** — if ambiguous, ask once upfront. Do not guess and iterate
- **Cross-platform verification** — Android change → also check iOS; Windows change → also check Linux + macOS → [§12 Platform-Specific](docs/ARCHITECTURE.md#12-platform-specific-behavior)

### Branching & Release Flow

Two branches: `dev` (daily work) and `main` (releases only).

**Daily work** — push everything to `dev`. CI, SonarCloud, OSV-Scanner run on every push.

**Release** — merge `dev` into `main`. Automatic: CI on main → auto-tag reads version from pubspec.yaml → creates tag → build → release. Details: [§15 CI/CD Pipeline](docs/ARCHITECTURE.md#15-cicd-pipeline)

**Rule:** never push directly to `main` (except Dependabot PRs and CI/docs-only fixes). All app work goes through `dev` → `main` merge.

**Merging dev → main** — sync dev with main first: `git fetch origin main && git merge origin/main` and push. Then create PR with `--auto` flag. Required checks: `ci`, `osv-scan`, `semgrep-scan`, `codeql-scan`. After merge, sync dev with main again.

**Claude default branch is `dev`.** Always work on `dev` unless explicitly told otherwise.

**Contributors** — work via forks, PRs target `dev` (never `main`), all CI checks must pass.

| Scenario                    | What to do                                                          |
| --------------------------- | ------------------------------------------------------------------- |
| App change (feat/fix/refac) | Merge `dev` → `main` — auto-tag handles it                         |
| Tests/docs/CI only          | Merge to `main` — no new version, no tag, no release                |
| Dependabot deps             | Auto: PR to main → merge → version bump → CI → auto-tag → release  |
| Manual build                | `gh workflow run build-release.yml` — fails if CI hasn't passed     |
| Failed build (re-trigger)   | `gh workflow run build-release.yml --ref v{VERSION}`                |

### Skills & Hooks

Custom skills and hooks live in `.claude/skills/` and `.claude/hooks/`. Skills are auto-loaded by Claude and can be invoked via `/command`.

**Skills** (`.claude/skills/<name>/SKILL.md`):

| Skill | What it does |
|-------|-------------|
| `/analyze` | Run `make analyze` — Dart analyzer |
| `/test` | Run `make test` — test suite with coverage |
| `/check` | Run `make check` — analyzer + tests sequentially |
| `/commit` | Full commit workflow: version bump check, docs check, commit per project rules |
| `/pr` | Create PR dev → main: sync with main, create PR with `--auto` merge |
| `/coverage` | Check SonarCloud coverage via API: overall, new code, per-file top worst |
| `/fix-sonar` | Fetch SonarCloud issues and fix them by severity (accepts filter: `CRITICAL`, file path) |
| `/fix-security` | Fetch GitHub security alerts (Dependabot, CodeQL, Semgrep, secrets) and fix them |
| `/write-tests` | Fetch uncovered lines from SonarCloud and write missing tests (accepts: `new`, file path) |

**Hooks** (`.claude/hooks/`):

| Hook | Trigger | What it does |
|------|---------|-------------|
| `format-dart.sh` | PostToolUse on Edit/Write | Auto-runs `dart format` on .dart files after every edit |
| `gen-l10n.sh` | PostToolUse on Edit/Write | Auto-runs `flutter gen-l10n` on .arb files after every edit |
| `pre-commit-check.sh` | PreToolUse on `git commit *` | Runs `make check` (analyzer + tests), blocks commit on failure |

### Dependencies & Building

- Latest **stable** versions only — no beta/dev/pre-release. No OS-level deps (`apt install`/`brew install`)
- **Always build via Makefile** — `make run`, `make build-linux`, `make test`, `make analyze`. Never call `flutter build`/`flutter run` directly. Full target list: [§15.4 Makefile Targets](docs/ARCHITECTURE.md#154-makefile-targets)
- **Always use Context7 MCP** for library/API docs — don't guess APIs, look them up
- **Pin external downloads in CI** — any `wget`/`curl` in workflows must use a specific release version and verify SHA256 checksum

### What Not To Do

- Do not install packages without asking
- **Never suppress issues** — no `// NOSONAR`, `// ignore:`, `@SuppressWarnings`. Always fix the root cause
- **Never amend after push** — only new commits. Amend OK only before first push
- **All code must have tests** — target 100% coverage; 80% is SonarCloud minimum, never the goal. After writing code: `make test`, check uncovered lines, write more tests. Only skip untestable lines (real SSH, native file I/O). Use `/coverage` skill to check real numbers via SonarCloud API
- **Code must be testable by design** — extract pure logic from SSH/platform/I/O deps. DI over hardcoded `ref.read()`. Interfaces for file ops. Dialog returns data, service processes it. Pure functions over closures. DI hooks: [§14 Testing Patterns](docs/ARCHITECTURE.md#14-testing-patterns--di-hooks)
- **One test file per source file** — no `_extra_test` sprawl. Add to existing test file
- **Parallel agents** — only `git add` files YOU changed. **Do NOT run tests** — testing is the main process's job. Leave untracked/modified files from other agents alone

---

## Code Quality Rules

All code must follow **Effective Dart** and pass `dart analyze` with zero issues. Rules in `analysis_options.yaml` (extends `flutter_lints/flutter.yaml`). `make analyze` must pass with zero issues before every commit.

- **Cognitive complexity** ≤ 15 per method (SonarCloud S3776). Extract helper methods to reduce
- **No nested ternaries** (SonarCloud S3358). Extract to local variables or use `if`/`else`
- **No `print()`/`debugPrint()`** — use `AppLogger.instance.log(message, name: 'Tag')`. **Never log sensitive data** → [§7 AppLogger API](docs/ARCHITECTURE.md#7-utilities--public-api-reference)
- **No generated file edits** — `*.g.dart` and `*.freezed.dart` are excluded from analysis

---

## Conventions

### Architecture
- **Feature-first** — each feature is isolated module with UI + logic → [§5 Feature Modules](docs/ARCHITECTURE.md#5-feature-modules)
- **Core is UI-agnostic** — `core/` doesn't import Flutter → [§3 Core Modules](docs/ARCHITECTURE.md#3-core-modules)
- **Riverpod for state** — single source of truth, no global mutable state → [§4 Providers](docs/ARCHITECTURE.md#4-state-management--riverpod)
- **Immutable models** — hand-written with copyWith, ==, hashCode, toJson/fromJson → [§10 Data Models](docs/ARCHITECTURE.md#10-data-models)
- **FileSystem interface** — abstraction for local/remote → [§3.2 SFTP](docs/ARCHITECTURE.md#32-sftp-coresftp)
- **No SCP** — dartssh2 doesn't support it; SFTP covers all use cases
- **Tree-based sessions** — nested groups via `/` separator → [§3.4 Sessions](docs/ARCHITECTURE.md#34-session-management-coresession)
- SSH keys accepted **both as file and text** (paste PEM)
- `.lfs` export format: `[salt 32B] [iv 12B] [encrypted ZIP + GCM tag]`, merge/replace import modes → [§3.9 Import](docs/ARCHITECTURE.md#39-import-coreimport)

### Security
- Credentials in `CredentialStore` (AES-256-GCM), NOT in plain JSON → [§3.6 Security](docs/ARCHITECTURE.md#36-security--encryption-coresecurity)

### Theme & UI Constants
OneDark theme: centralized in `app_theme.dart`, semantic color constants, no hardcoded `Colors` → [§8 Theme](docs/ARCHITECTURE.md#8-theme-system)

- **Font sizes** — never hardcode `fontSize`. Use `AppFonts.tiny`/`xxs`/`xs`/`sm`/`md`/`lg`/`xl` (mobile +2 px)
- **Border radius** — never hardcode `BorderRadius.circular(N)`. Use `AppTheme.radiusSm` (4), `radiusMd` (6), `radiusLg` (8). Exception: pill-shaped elements
- **Heights** — never hardcode height literals. Use `AppTheme` constants: `barHeight{Sm,Md,Lg}`, `controlHeight{Xs..Xl}`, `itemHeight{Xs..Xl}`

### UI Components
- **Buttons & hover** — `AppIconButton` for all icon buttons. `HoverRegion` for custom hover containers. Never use bare `IconButton`, `InkWell` for buttons, or manual `MouseRegion`+`GestureDetector`+`setState(_hovered)`. Exception: `context_menu.dart`, mobile touch buttons → [§6 Widgets API](docs/ARCHITECTURE.md#6-widgets--public-api-reference)
- **Dialogs** — `AppDialog` for all modal dialogs. Never use bare `AlertDialog`. Complex dialogs: compose from `AppDialogHeader`/`AppDialogFooter`/`AppDialogAction`. Progress: `AppProgressDialog.show()`. Exception: mobile touch buttons keep `Material`+`InkWell` for ripple
- **Text overflow protection** — localized text in `Row` or fixed-width → wrap with `Flexible`/`Expanded` + `overflow: TextOverflow.ellipsis`. For label columns use `ConstrainedBox(maxWidth:)` instead of fixed `SizedBox(width:)`

### Localization (i18n)
All user-facing strings MUST use `S.of(context).xxx`. Never hardcode strings in widgets — treat this as a bug. Add keys to `lib/l10n/app_en.arb`, run `flutter gen-l10n`, use `S.of(context).newKey`. Exceptions: constructor defaults (no context), log messages, `_AlreadyRunningApp`. Tests must include `localizationsDelegates: S.localizationsDelegates, supportedLocales: S.supportedLocales` in every `MaterialApp`. See [§8.1 i18n](docs/ARCHITECTURE.md#81-internationalization-i18n)
