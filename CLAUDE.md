# LetsFLUTssh — Development Guide

## Project Overview

LetsFLUTssh — lightweight cross-platform SSH/SFTP client with GUI, written in Dart/Flutter.
Open-source alternative to Xshell/Termius. Platforms: Windows, Linux, macOS, Android, iOS.

**Solo developer project** — no team, no second reviewer. Scorecard checks like Code-Review and Branch-Protection assume multi-person teams; some findings are expected and acceptable for a solo project.

**Predecessor:** LetsGOssh (Go/Fyne) — full feature port + improvements.

## How to Use Technical Documentation

**Primary reference:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — contains ALL architecture details, data models, API references, data flows, design decisions, and CI/CD pipeline docs.

**Rule for Claude:** Do NOT read ARCHITECTURE.md cover-to-cover. Jump to the specific section you need via the links below. Each section of this file points to the relevant ARCHITECTURE.md anchor.

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

**Violation = incomplete commit.** Do not mark a task as done until docs are updated. The same commit that changes code MUST include the doc update.

### Commits

- **Claude does not commit or push unless the user explicitly asks.** When asked — scope matches what was said: "commit" = commit only, "commit and push" = commit + push. **Exception for multiple fixes:** after completing each fix (code + tests + version bump + docs), Claude MUST stop and ask the user to commit before starting the next fix — do not silently proceed to the next task
- **Every commit that affects the shipped app MUST include a version bump** in `pubspec.yaml` (the only source of truth — `package_info_plus` reads it at runtime). Includes: `lib/`, platform configs, native code, assets, build settings. Patch for bugfix/refactor, minor for new feature, major for breaking change. No exceptions
- Format: `type: short description` — types: `feat`, `fix`, `refactor` (app changes), `test`, `docs`, `chore`, `ci` (non-app)
- **Commit messages drive auto-changelog** — `feat:` → Features, `fix:` → Fixes, `refactor:` → Improvements. Keep messages user-readable. If commit has both app changes and docs — prefix describes the app change only
- **One fix / one commit** — each logical change is a separate commit. Do not bundle unrelated fixes
- **HARD STOP between fixes** — when working on multiple fixes, the workflow is strictly sequential: implement fix → write tests → bump version → update docs → **stop and ask user to commit**. **Do NOT start the next fix until the current one is committed.** This is a blocking gate, not a suggestion. After finishing a fix, Claude MUST present the completed work and prompt the user (e.g. "Ready to commit. Should I commit before moving to the next fix?") — never silently continue to the next task. Starting the next fix before committing the current one is a rule violation — it leads to tangled changes in shared files and painful commit splitting. Note: `make check` (analyzer + tests) runs automatically as a pre-commit hook — no need to run it manually
- **Green CI before merging to main** — the pre-commit hook runs `make check` automatically, so tests must pass before any commit lands. If pre-existing test failures exist, fix them first in a separate `fix:` commit with version bump. Never merge to main with failing CI on dev — auto-tag fires after successful CI on main, so a failed pipeline blocks the release
- Repository is **public** on GitHub

### Work Style

- **All files must be written in English only** — code, comments, commit messages, documentation, everything. No exceptions
- Documentation in English (README.md, CLAUDE.md, ARCHITECTURE.md, SECURITY.md, CONTRIBUTING.md), updated on every significant change
- SSH keys accepted **both as file and text** (paste PEM) — key requirement
- Easy data transfer between devices — `.lfs` archive format → [§3.9 Import](docs/ARCHITECTURE.md#39-import-coreimport)
- Session grouping — tree with nested subfolders (e.g. `Production/Web/nginx1`) → [§3.4 Sessions](docs/ARCHITECTURE.md#34-session-management-coresession)
- **Zero hardcoded user-facing strings** — every label, tooltip, button text, error message, hint, and status string visible to the user MUST use `S.of(context).xxx`. When adding or changing UI text, always add the key to `app_en.arb` + all other ARB files, run `flutter gen-l10n`, and use the generated accessor. Never leave English literals in widget code — treat hardcoded strings as a bug. See [§8.1 i18n](docs/ARCHITECTURE.md#81-internationalization-i18n)
- **Cross-platform verification** — Android change → also check iOS; Windows change → also check Linux + macOS. Verify all sibling platforms before committing → [§12 Platform-Specific](docs/ARCHITECTURE.md#12-platform-specific-behavior)
- **Best practices by default** — always implement using best practices. If the user's request leads to a hacky or suboptimal solution, push back and propose a best-practice alternative. Explain why. Only implement a hacky approach if the user explicitly confirms after hearing the alternative
- **Think systemically, not literally** — when given an instruction, consider its full scope and side effects. Don't blindly execute a narrow change — think about what else is affected (related code, docs, formatting, consistency). Apply the intent behind the request, not just the letter
- **UI changes = test updates** — when modifying UI components (renaming labels, changing widget structure, removing suffixes), proactively update all tests that reference old widget names, labels, or finders. Do it in the same change, not as an afterthought
- **Ask before guessing UI placement** — if a UI change has any ambiguity about exact placement, behavior, or layout rules (tab positions, split behavior, drag zones), ask the user once upfront. Do not guess and iterate through 3-4 cycles

### Branching & Release Flow

Two branches: `dev` (daily work) and `main` (releases only).

**Daily work** — push everything to `dev`. CI, SonarCloud, OSV-Scanner run on every push. No tags, no builds, no releases.

**Release** — merge `dev` into `main`. Everything is automatic: CI on main → auto-tag reads version from pubspec.yaml → creates tag → build → release.

**Rule:** never push directly to `main` (except Dependabot PRs and CI/docs-only fixes). All app work goes through `dev` → `main` merge.

**Merging dev → main** — before creating a PR, sync dev with main: `git fetch origin main && git merge origin/main` and push. The main branch requires dev to be up-to-date (strict status checks). Then create PR with `--auto` flag (`gh pr create ... && gh pr merge --auto --merge`). The PR will merge automatically once all required checks pass (`ci`, `osv-scan`, `semgrep-scan`, `codeql-scan`). After merge, sync dev with main again.

**Claude default branch is `dev`.** Always work on `dev` unless the user explicitly says otherwise. If on `main` — switch to `dev` before making changes.

### Contributor Workflow

External contributors work via **forks** — standard open source model. No write access to the repo needed.

**Contributor flow:**
1. Fork the repo
2. Create a feature/fix branch in the fork (`feature/...`, `fix/...`)
3. Implement changes, push to the fork
4. Open a PR from fork into `dev` (NOT `main`)
5. CI runs all checks automatically on the PR
6. Maintainer (repo owner) reviews, requests changes if needed, merges into `dev`

**Rules for PRs from contributors:**
- Target branch is always `dev`, never `main`
- All CI checks must pass before merge (`ci`, `osv-scan`, `semgrep-scan`, `codeql-scan`)
- Maintainer is the only person who merges to `main` (release flow)

### Branch Protection (GitHub Rulesets)

Three rulesets protect the repository:

| Ruleset | Branch | Rules | Bypass |
|---------|--------|-------|--------|
| `main` | `main` | No deletion, no force-push, PR required, all CI checks required | None |
| `dev-protect` | `dev` | No deletion, no force-push | None |
| `dev-checks` | `dev` | All CI checks required | Admin (repo owner) — allows direct push |

**Why two rulesets for dev:** the owner needs to push directly to `dev` (bypassing CI requirement), but nobody — including the owner — should be able to delete or force-push `dev`. Splitting into two rulesets with different bypass settings achieves this.

### Versioning & Tagging

Plain SemVer: `MAJOR.MINOR.PATCH`. Bump: patch (bugfix/refactor), minor (feature), major (breaking).

**No bump needed for:** tests, docs, CI, linter fixes. **Bump IS needed for:** any `lib/` change (including logging), platform configs, native code, assets.

**Tagging — fully automated via `auto-tag.yml`.** Merge to main → CI → auto-tag → release. Details: [§15 CI/CD Pipeline](docs/ARCHITECTURE.md#15-cicd-pipeline)

| Scenario                    | What to do                                                          |
| --------------------------- | ------------------------------------------------------------------- |
| App change (feat/fix/refac) | Merge `dev` → `main` — auto-tag handles it                         |
| Tests/docs/CI only          | Merge to `main` — no new version, no tag, no release                |
| Dependabot deps             | Auto: PR to main → merge → version bump → CI → auto-tag → release  |
| Manual build                | `gh workflow run build-release.yml` — fails if CI hasn't passed           |
| Failed build (re-trigger)   | `gh workflow run build-release.yml --ref v{VERSION}`                      |

Manual release: `gh workflow run build-release.yml` — fails if CI hasn't passed on HEAD.

### Skills & Hooks

Custom skills and hooks live in `.claude/skills/` and `.claude/hooks/` and are committed to the repo. Personal settings (permissions, paths) go in `.claude/settings.local.json` (gitignored). Skills are auto-loaded by Claude when context matches, and can also be invoked manually via `/command`.

**Skills** (`.claude/skills/<name>/SKILL.md`):

| Skill | What it does |
|-------|-------------|
| `/analyze` | Run `make analyze` — Dart analyzer |
| `/test` | Run `make test` — test suite with coverage |
| `/check` | Run `make check` — analyzer + tests sequentially |
| `/commit` | Full commit workflow: version bump check, docs check, commit per project rules (pre-commit hook runs analyzer + tests) |
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

### Post-change checklist

1. Version bump in same commit (if app-affecting)
2. **Update docs**: ARCHITECTURE.md (see table above), CLAUDE.md if nav links affected, README.md if user-visible, SECURITY.md if security scope changes
3. Pre-commit hook runs `make check` (analyzer + tests) automatically — commit will be blocked if anything fails

### Dependencies & Building

- Latest **stable** versions only — no beta/dev/pre-release. No OS-level deps (`apt install`/`brew install`)
- **Always build via Makefile** — `make run`, `make build-linux`, `make test`, `make analyze`. Never call `flutter build`/`flutter run` directly. Full target list: [§15.4 Makefile Targets](docs/ARCHITECTURE.md#154-makefile-targets)
- **Always use Context7 MCP** for library/API docs — don't guess APIs, look them up
- **Pin external downloads in CI** — any `wget`/`curl` in workflows must use a specific release version (not rolling tags like `continuous`) and verify SHA256 checksum after download

### What Not To Do

- Do not commit/push unless explicitly asked. Do not install packages without asking
- **Never suppress issues** — no `// NOSONAR`, `// ignore:`, `@SuppressWarnings` or any other suppression mechanism. Always fix the root cause
- **Never amend after push** — only new commits. Amend OK only before first push
- **All code must have tests** — target 100% coverage; 80% is SonarCloud minimum, never the goal
    - After writing code: `make test`, check uncovered lines, write more tests. Only skip untestable lines (real SSH, native file I/O)
    - **SonarCloud verification** — check real numbers via API, local `lcov.info` may lag:
        - Overall: `curl -s "https://sonarcloud.io/api/measures/component?component=Llloooggg_LetsFLUTssh&metricKeys=coverage,uncovered_lines"`
        - New code: `curl -s "https://sonarcloud.io/api/measures/component?component=Llloooggg_LetsFLUTssh&metricKeys=new_coverage,new_uncovered_lines,new_lines_to_cover"`
        - Per-file: `curl -s "https://sonarcloud.io/api/measures/component_tree?component=Llloooggg_LetsFLUTssh&metricKeys=uncovered_lines,coverage&strategy=leaves&ps=50&s=metric&metricSort=uncovered_lines&asc=false"`
- **Code must be testable by design** — extract pure logic from SSH/platform/I/O deps. DI over hardcoded `ref.read()`. Interfaces for file ops. Dialog returns data, service processes it. Pure functions over closures. No duplicate logic across files. DI hooks: [§14 Testing Patterns](docs/ARCHITECTURE.md#14-testing-patterns--di-hooks)
- **One test file per source file** — no `_extra_test` sprawl. Add to existing test file. Parallel agents: zero overlap in file assignments
- **Parallel agents** — only `git add` files YOU changed. **Do NOT run tests** — neither your own test file nor `make test`. Leave untracked/modified files from other agents alone. **Testing is the main process's job** — after all sub-agents finish, the main process runs `make test` once to validate everything together
- **Version gatekeeper** — before suggesting commit, check if version bump needed. If yes — remind. If no — say so explicitly

## Key Design Principles

1. **Feature-first** — each feature is isolated module with UI + logic → [§5 Feature Modules](docs/ARCHITECTURE.md#5-feature-modules)
2. **Core is UI-agnostic** — `core/` doesn't import Flutter → [§3 Core Modules](docs/ARCHITECTURE.md#3-core-modules)
3. **Riverpod for state** — single source of truth → [§4 State Management](docs/ARCHITECTURE.md#4-state-management--riverpod)
4. **Immutable models** — hand-written with copyWith, equality, JSON → [§10 Data Models](docs/ARCHITECTURE.md#10-data-models)
5. **FileSystem interface** — abstraction for local/remote → [§3.2 SFTP](docs/ARCHITECTURE.md#32-sftp-coresftp)
6. **No SCP** — dartssh2 doesn't support it; SFTP covers all use cases
7. **Tree-based sessions** — nested groups via `/` separator, flat list with group path → [§3.4 Sessions](docs/ARCHITECTURE.md#34-session-management-coresession)
8. **Custom UI components** — `AppIconButton` and `HoverRegion` instead of Material `IconButton`/`InkWell`. Never use `IconButton` directly — use `AppIconButton` for icons, `HoverRegion` for custom hover containers → [§6 Widgets API](docs/ARCHITECTURE.md#6-widgets--public-api-reference)

## Dart/Flutter Style Rules

All code must follow **Effective Dart** guidelines and pass `dart analyze` with zero issues. Key rules enforced in this project:

### Naming
- **Classes, enums, typedefs, extensions:** `UpperCamelCase` — `SessionManager`, `SortColumn`
- **Variables, parameters, functions, methods:** `lowerCamelCase` — `currentPath`, `navigateTo()`
- **Constants:** `lowerCamelCase` (not `SCREAMING_CAPS`) — `defaultTimeout`, `maxRetries`
- **Files and directories:** `snake_case` — `file_pane.dart`, `transfer_panel.dart`
- **Libraries and packages:** `snake_case` — `import 'package:letsflutssh/core/ssh.dart'`
- **Private members:** prefix with `_` — `_sortColumn`, `_buildHeader()`
- **Boolean names:** positive phrasing with `is`/`has`/`can`/`should` — `isConnected`, `hasError`

### Formatting & Structure
- **Line length:** 120 characters max (dart format default for this project)
- **Trailing commas:** always on the last argument/element in multi-line constructs — enables clean diffs and auto-formatting
- **Imports:** relative within the package (`prefer_relative_imports` lint enabled). Group: dart → package → relative, separated by blank lines
- **Single quotes** for strings (`prefer_single_quotes` lint enabled)
- **`const` constructors** wherever possible (`prefer_const_constructors` lint enabled)
- **`final` locals** — never reassign when not needed (`prefer_final_locals` lint enabled)

### Code Quality
- **Cognitive complexity** ≤ 15 per method (SonarCloud S3776). Extract helper methods to reduce complexity
- **No nested ternaries** (SonarCloud S3358). Extract to local variables or use `if`/`else`
- **No `print()`/`debugPrint()`** — use `AppLogger` (also enforced by `avoid_print` lint)
- **Sort `child`/`children` last** in widget constructors (`sort_child_properties_last` lint)
- **Key in widget constructors** (`use_key_in_widget_constructors` lint)
- **Dead code** is a warning, **missing return** is an error (see `analysis_options.yaml`)
- **No generated file edits** — `*.g.dart` and `*.freezed.dart` are excluded from analysis

### Flutter-Specific
- **Widget methods vs widgets:** extract to private methods within the same widget class for simple cases; extract to separate `StatelessWidget`/`StatefulWidget` for reusable or complex pieces
- **`BuildContext`** must not be stored or used across async gaps
- **Dispose** controllers, focus nodes, animation controllers in `dispose()`
- **`const` widgets** when possible — improves rebuild performance

### What the Analyzer Enforces

All rules are in `analysis_options.yaml` (extends `flutter_lints/flutter.yaml`). Enabled lints:
`prefer_const_constructors`, `prefer_const_declarations`, `prefer_final_locals`, `prefer_single_quotes`, `sort_child_properties_last`, `use_key_in_widget_constructors`, `avoid_print`, `prefer_relative_imports`

**Rule:** `make analyze` must pass with zero issues before every commit. No suppressions (`// ignore:`) — fix the root cause.

---

## Conventions

- **Logging** — `AppLogger.instance.log(message, name: 'Tag')` everywhere, never `print()`/`debugPrint()`. **Never log sensitive data** → [§7 AppLogger API](docs/ARCHITECTURE.md#7-utilities--public-api-reference)
- All state via Riverpod providers — no global mutable state → [§4 Providers](docs/ARCHITECTURE.md#4-state-management--riverpod)
- Immutable models with copyWith, ==, hashCode, toJson/fromJson → [§10 Data Models](docs/ARCHITECTURE.md#10-data-models)
- Credentials in `CredentialStore` (AES-256-GCM), NOT in plain JSON → [§3.6 Security](docs/ARCHITECTURE.md#36-security--encryption-coresecurity)
- OneDark theme: centralized in `app_theme.dart`, semantic color constants, no hardcoded Colors → [§8 Theme](docs/ARCHITECTURE.md#8-theme-system)
- **Font sizes** — never hardcode `fontSize` numbers. Use `AppFonts.tiny`/`xxs`/`xs`/`sm`/`md`/`lg`/`xl` — they are platform-aware (mobile +2 px). See [§8 Theme](docs/ARCHITECTURE.md#8-theme-system)
- **Border radius** — never hardcode `BorderRadius.circular(N)` or `BorderRadius.zero`. Use `AppTheme.radiusSm` (4 px), `radiusMd` (6 px), `radiusLg` (8 px). Exception: pill-shaped elements (toggle tracks). See [§8 Theme](docs/ARCHITECTURE.md#8-theme-system)
- **Heights** — never hardcode height numeric literals for UI elements. Use `AppTheme` height constants: `barHeight{Sm,Md,Lg}` for bars/headers, `controlHeight{Xs..Xl}` for buttons/inputs/selectors, `itemHeight{Xs..Xl}` for rows/containers/list items. See [§8 Theme](docs/ARCHITECTURE.md#8-theme-system)
- **Buttons & hover** — `AppIconButton` for all icon buttons (rectangular hover, no splash, disabled dimming). `HoverRegion` for custom hover containers (builder pattern). Never use bare `IconButton`, `InkWell` for buttons, or manual `MouseRegion`+`GestureDetector`+`setState(_hovered)`. Exception: `context_menu.dart` (centralized keyboard nav state), mobile touch buttons (`ssh_keyboard_bar.dart`, `mobile_file_browser.dart`, `mobile_terminal_view.dart`) → [§6 Widgets API](docs/ARCHITECTURE.md#6-widgets--public-api-reference)
- **Dialogs** — `AppDialog` for all modal dialogs (dark bg, header+close, footer+actions). Never use bare `AlertDialog`. For complex dialogs (tabs, trees), compose from `AppDialogHeader`/`AppDialogFooter`/`AppDialogAction`. Progress spinners via `AppProgressDialog.show()`. Exception: mobile touch buttons keep `Material`+`InkWell` for ripple → [§6 Widgets API](docs/ARCHITECTURE.md#6-widgets--public-api-reference)
- **Localization (i18n)** — all user-facing strings MUST use `S.of(context).xxx` from `l10n/app_localizations.dart`. Never hardcode strings in widgets. Add new keys to `lib/l10n/app_en.arb`, run `flutter gen-l10n`, then use `S.of(context).newKey`. Exceptions: constructor default parameters (no context available), log messages (not user-facing), `_AlreadyRunningApp` (own MaterialApp without delegates). Tests must include `localizationsDelegates: S.localizationsDelegates, supportedLocales: S.supportedLocales` in every `MaterialApp`. See [§8.1 i18n](docs/ARCHITECTURE.md#81-internationalization-i18n)
- **Text overflow protection** — when placing localized text in `Row` or fixed-width containers, always wrap with `Flexible`/`Expanded` and add `overflow: TextOverflow.ellipsis`. Translations can be 30-50% longer than English. For label columns use `ConstrainedBox(maxWidth:)` instead of fixed `SizedBox(width:)`
- `.lfs` export format: `[salt 32B] [iv 12B] [encrypted ZIP + GCM tag]`, merge/replace import modes → [§3.9 Import](docs/ARCHITECTURE.md#39-import-coreimport)
