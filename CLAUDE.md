# LetsFLUTssh — Development Guide

## Project Overview

LetsFLUTssh — lightweight cross-platform SSH/SFTP client with GUI, written in Dart/Flutter.
Open-source alternative to Xshell/Termius. Platforms: Windows, Linux, macOS, Android, iOS.

**Solo developer project** — no team, no second reviewer. Scorecard checks like Code-Review and Branch-Protection assume multi-person teams; some findings are expected and acceptable for a solo project.

**Predecessor:** LetsGOssh (Go/Fyne) — full feature port + improvements.

## Documentation

- **Architecture & API:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — module structure, data models, providers, data flows, design decisions, CI/CD. **Do NOT read cover-to-cover** — use [navigation table](docs/CLAUDE_RULES.md#quick-navigation-by-task) to jump to the section you need
- **Claude reference tables:** [`docs/CLAUDE_RULES.md`](docs/CLAUDE_RULES.md) — read specific sections on demand:
  - [Navigation by task](docs/CLAUDE_RULES.md#quick-navigation-by-task) — when you need to find something in ARCHITECTURE.md
  - [Doc maintenance checklist](docs/CLAUDE_RULES.md#documentation-maintenance-checklist) — before committing, check what docs to update
  - [Conventions](docs/CLAUDE_RULES.md#conventions) — when writing code (architecture, UI components, theme, i18n)
  - [Branching & release](docs/CLAUDE_RULES.md#branching--release-flow) — when doing git/PR operations
- **Contributing (for humans):** [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) — build instructions, code style, PR guidelines

---

## Working Agreements

### Commits

- **Claude does not commit or push unless the user explicitly asks.** "commit" = commit only, "commit and push" = commit + push
- **Version bumps are automatic.** The `/pr` skill runs `scripts/bump-version.sh` before creating PR — it parses conventional commits since the last tag and bumps `pubspec.yaml` (patch for fix/refactor/perf/build/deps, minor for feat, major for BREAKING CHANGE; chore/docs/test/ci/Revert = no bump). **Do NOT bump version manually** — just use correct conventional commit prefixes. Dependabot PRs are bumped by CI (`dependabot-auto.yml`)
- Format per [CONTRIBUTING.md](docs/CONTRIBUTING.md#commit-messages). Messages drive auto-changelog — keep them user-readable
- **One fix / one commit** — each logical change is a separate commit. Do not bundle unrelated fixes
- **HARD STOP between fixes** — implement fix → write tests → update docs → **stop and ask user to commit**. Do NOT start the next fix until the current one is committed. **Exception:** when the user explicitly asks to fix everything at once ("fix all and push"), execute end-to-end without pausing between fixes
- **Green CI before merging to main** — pre-commit hook runs `make check` automatically
- **Claude default branch is `dev`.** Always work on `dev` unless explicitly told otherwise. Never push directly to `main`
- Repository is **public** on GitHub

### Work Style

- **All files in English only** — code, comments, commits, docs. No exceptions
- **Best practices by default** — push back on hacky solutions, propose best-practice alternatives
- **Think systemically** — consider full scope and side effects, not just the literal instruction
- **UI changes = test updates** — proactively update all tests that reference changed widget names, labels, or finders
- **Ask before guessing UI placement** — if ambiguous, ask once upfront
- **Cross-platform verification** — Android change → also check iOS; Windows change → also check Linux + macOS

### Dependencies & Building

- Latest **stable** versions only — no beta/dev/pre-release. OS-level deps must be **optional** with graceful runtime fallback (e.g. `flutter_secure_storage` requires libsecret on Linux — app works without it)
- **Always build via Makefile** — `make run`, `make build-linux`, `make test`, `make analyze`. Never call `flutter build`/`flutter run` directly
- **Always use Context7 MCP** for library/API docs — don't guess APIs, look them up
- **Pin external downloads in CI** — specific release version + SHA256 checksum

### What Not To Do

- Do not install packages without asking
- **Never suppress issues** — no `// NOSONAR`, `// ignore:`, `@SuppressWarnings`. Always fix the root cause
- **Never amend after push** — only new commits. Amend OK only before first push
- **All code must have tests** — target 100% coverage (80% is SonarCloud minimum, not the goal). One test file per source file. Testable by design: extract pure logic from SSH/platform/I/O deps, DI over hardcoded `ref.read()` — [§14 Testing Patterns](docs/ARCHITECTURE.md#14-testing-patterns--di-hooks)
- **Fuzz tests for parsers** — any function that parses untrusted input (JSON `fromJson()`, URI parsing, file format parsing) must have a corresponding fuzz test in `test/fuzz/`. Fuzz tests generate random/malformed inputs and verify the parser never crashes with unhandled exceptions. Run as part of `make test`. See [§14 Fuzz testing](docs/ARCHITECTURE.md#fuzz-testing)
- **Parallel agents** — only `git add` files YOU changed. **Do NOT run tests** — testing is the main process's job

---

## Code Quality Rules

All code must follow **Effective Dart** and pass `dart analyze` with zero issues. `make analyze` must pass before every commit.

- **Cognitive complexity** ≤ 15 per method (SonarCloud S3776). Extract helper methods to reduce
- **No nested ternaries** (SonarCloud S3358). Extract to local variables or use `if`/`else`
- **No `print()`/`debugPrint()`** — use `AppLogger.instance.log(message, name: 'Tag')`. **Never log sensitive data**
- **No generated file edits** — `*.g.dart` and `*.freezed.dart` are excluded from analysis
