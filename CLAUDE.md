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
| Work with tabs | [§5.4 Tab System](docs/ARCHITECTURE.md#54-tab-system-featurestabs) |
| Work with mobile features | [§5.6 Mobile](docs/ARCHITECTURE.md#56-mobile-featuresmobile) + [§12 Platform-Specific](docs/ARCHITECTURE.md#12-platform-specific-behavior) |
| Use or create widgets | [§6 Widgets API](docs/ARCHITECTURE.md#6-widgets--public-api-reference) |
| Use utilities | [§7 Utilities API](docs/ARCHITECTURE.md#7-utilities--public-api-reference) |
| Work with theme / colors | [§8 Theme System](docs/ARCHITECTURE.md#8-theme-system) |
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
| Architecture changed | Update this file (CLAUDE.md) if navigation links affected |
| User-visible change | Update README.md |
| Security scope change | Update SECURITY.md |

**Violation = incomplete commit.** Do not mark a task as done until docs are updated. The same commit that changes code MUST include the doc update.

### Commits

- **Claude does not commit or push unless the user explicitly asks.** When asked — scope matches what was said: "commit" = commit only, "commit and push" = commit + push (auto-tag handles the rest). For multiple fixes — see "HARD STOP between fixes" rule below
- **Every commit that affects the shipped app MUST include a version bump** in `pubspec.yaml` (the only source of truth — `package_info_plus` reads it at runtime). Includes: `lib/`, platform configs, native code, assets, build settings. Patch for bugfix/refactor, minor for new feature, major for breaking change. No exceptions
- Format: `type: short description` — types: `feat`, `fix`, `refactor` (app changes), `test`, `docs`, `chore`, `ci` (non-app)
- **Commit messages drive auto-changelog** — `feat:` → Features, `fix:` → Fixes, `refactor:` → Improvements. Keep messages user-readable. If commit has both app changes and docs — prefix describes the app change only
- **One fix / one commit** — each logical change is a separate commit. Do not bundle unrelated fixes
- **HARD STOP between fixes** — when working on multiple fixes, the workflow is strictly sequential: implement fix → write tests → bump version → update docs → `make analyze` → commit. **Do NOT start the next fix until the current one is committed.** This is a blocking gate, not a suggestion. Starting the next fix before committing the current one is a rule violation — it leads to tangled changes in shared files and painful commit splitting
- **Green CI before pushing app changes** — run `make test` before pushing. If pre-existing test failures exist, fix them first in a separate `fix:` commit with version bump, push, confirm CI is green, then push your app change. Never push a `feat:`/`fix:`/`refactor:` commit on top of red CI — auto-tag only fires after successful CI, so a failed pipeline blocks all subsequent releases until the tests are fixed
- Repository is **public** on GitHub

### Work Style

- **All files must be written in English only** — code, comments, commit messages, documentation, everything. No exceptions
- Documentation in English (README.md, CLAUDE.md, ARCHITECTURE.md, SECURITY.md, CONTRIBUTING.md), updated on every significant change
- SSH keys accepted **both as file and text** (paste PEM) — key requirement
- Easy data transfer between devices — `.lfs` archive format → [§3.9 Import](docs/ARCHITECTURE.md#39-import-coreimport)
- Session grouping — tree with nested subfolders (e.g. `Production/Web/nginx1`) → [§3.4 Sessions](docs/ARCHITECTURE.md#34-session-management-coresession)
- **Cross-platform verification** — Android change → also check iOS; Windows change → also check Linux + macOS. Verify all sibling platforms before committing → [§12 Platform-Specific](docs/ARCHITECTURE.md#12-platform-specific-behavior)
- **Best practices by default** — always implement using best practices. If the user's request leads to a hacky or suboptimal solution, push back and propose a best-practice alternative. Explain why. Only implement a hacky approach if the user explicitly confirms after hearing the alternative

### Versioning & Tagging

Plain SemVer: `MAJOR.MINOR.PATCH`. Bump: patch (bugfix/refactor), minor (feature), major (breaking).

**No bump needed for:** tests, docs, CI, linter fixes. **Bump IS needed for:** any `lib/` change (including logging), platform configs, native code, assets.

**Tagging — fully automated via `auto-tag.yml`.** Just `git push` — CI → auto-tag → build → release. Details: [§15 CI/CD Pipeline](docs/ARCHITECTURE.md#15-cicd-pipeline)

| Scenario                    | What to do                                                          |
| --------------------------- | ------------------------------------------------------------------- |
| App change (feat/fix/refac) | `git push` — auto-tag handles it                                   |
| App change + tests/docs     | Bundle tests/docs into the app commit, OR make sure the app commit is pushed last |
| Tests/docs/CI only          | `git push` — no tag, no release (correct behavior)                  |
| Dependabot deps             | Auto: merge → version bump → CI → `dependabot-tag.yml`             |
| Failed build (re-trigger)   | `gh workflow run build.yml --ref v{VERSION}` (manual dispatch — preflight warns if Sonar/OSV not found, then proceeds) |

`make tag` exists as a **manual fallback only**. Normal flow never needs it.

- By default Claude only reminds about tagging — does **not** run `make tag` unless user explicitly asks

**HEAD must be a taggable commit.** auto-tag only inspects the HEAD commit message. If HEAD is `test:`, `docs:`, `ci:`, or `chore:` — no tag is created even if prior commits have version bumps.

### Post-change checklist

1. Version bump in same commit (if app-affecting)
2. **Update docs**: ARCHITECTURE.md (see table above), CLAUDE.md if nav links affected, README.md if user-visible, SECURITY.md if security scope changes
3. `make analyze` + `make test` must pass

### Dependencies & Building

- Latest **stable** versions only — no beta/dev/pre-release. No OS-level deps (`apt install`/`brew install`)
- **Always build via Makefile** — `make run`, `make build-linux`, `make test`, `make analyze`. Never call `flutter build`/`flutter run` directly. Full target list: [§15.3 Makefile Targets](docs/ARCHITECTURE.md#153-makefile-targets)
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

## Conventions

- **Logging** — `AppLogger.instance.log(message, name: 'Tag')` everywhere, never `print()`/`debugPrint()`. **Never log sensitive data** → [§7 AppLogger API](docs/ARCHITECTURE.md#7-utilities--public-api-reference)
- All state via Riverpod providers — no global mutable state → [§4 Providers](docs/ARCHITECTURE.md#4-state-management--riverpod)
- Immutable models with copyWith, ==, hashCode, toJson/fromJson → [§10 Data Models](docs/ARCHITECTURE.md#10-data-models)
- Credentials in `CredentialStore` (AES-256-GCM), NOT in plain JSON → [§3.6 Security](docs/ARCHITECTURE.md#36-security--encryption-coresecurity)
- OneDark theme: centralized in `app_theme.dart`, semantic color constants, no hardcoded Colors → [§8 Theme](docs/ARCHITECTURE.md#8-theme-system)
- **Font sizes** — never hardcode `fontSize` numbers. Use `AppFonts.tiny`/`xxs`/`xs`/`sm`/`md`/`lg`/`xl` — they are platform-aware (mobile +2 px). See [§8 Theme](docs/ARCHITECTURE.md#8-theme-system)
- **Border radius** — never hardcode `BorderRadius.circular(N)` or `BorderRadius.zero`. Use `AppTheme.radiusSm` (2 px), `radiusMd` (4 px), `radiusLg` (6 px). Exception: pill-shaped elements (toggle tracks). See [§8 Theme](docs/ARCHITECTURE.md#8-theme-system)
- **Buttons & hover** — `AppIconButton` for all icon buttons (rectangular hover, no splash, disabled dimming). `HoverRegion` for custom hover containers (builder pattern). Never use bare `IconButton`, `InkWell` for buttons, or manual `MouseRegion`+`GestureDetector`+`setState(_hovered)`. Exception: `context_menu.dart` (centralized keyboard nav state) → [§6 Widgets API](docs/ARCHITECTURE.md#6-widgets--public-api-reference)
- `.lfs` export format: `[salt 32B] [iv 12B] [encrypted ZIP + GCM tag]`, merge/replace import modes → [§3.9 Import](docs/ARCHITECTURE.md#39-import-coreimport)
