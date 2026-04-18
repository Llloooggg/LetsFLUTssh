# LetsFLUTssh — Development Guide

## Project Overview

LetsFLUTssh — lightweight cross-platform SSH/SFTP client with GUI, written in Dart/Flutter.
Open-source alternative to Xshell/Termius. Platforms: Windows, Linux, macOS, Android, iOS.

**Solo developer project** — no team, no second reviewer.

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
- **Use `type(scope):` with parenthesized scope** for commits that touch a specific module (e.g. `refactor(import): ...`, `test(known-hosts): ...`, `feat(installer): ...`). Drop the scope only when the change is genuinely cross-cutting and no single module name fits. Scope must be lowercase, alphanumeric + dashes
- **HARD STOP between fixes** — implement fix → write tests → update docs → **stop and ask user to commit**. Do NOT start the next fix until the current one is committed. **Exception:** when the user explicitly asks to fix everything at once ("fix all and push"), execute end-to-end without pausing between fixes
- **Green CI before merging to main** — pre-commit hook runs `make check` automatically
- **Claude default branch is `dev`.** Always work on `dev` unless explicitly told otherwise. Never push directly to `main`
- Repository is **public** on GitHub

### Work Style

- **All files in English only** — code, comments, commits, docs. No exceptions
- **Best practices by default** — push back on hacky solutions, propose best-practice alternatives
- **Think systemically** — consider full scope and side effects, not just the literal instruction
- **UI changes = test updates** — proactively update all tests that reference changed widget names, labels, or finders
- **Every change ships with docs + tests + translations.** A code change is incomplete until: (1) ARCHITECTURE.md / relevant docs updated per [doc maintenance checklist](docs/CLAUDE_RULES.md#documentation-maintenance-checklist), (2) tests added/updated (aim for 100% coverage), (3) **every `lib/l10n/app_*.arb` file** updated for any new/changed user-facing string — not just `app_en.arb`. All 15 supported locales (ar, de, en, es, fa, fr, hi, id, ja, ko, pt, ru, tr, vi, zh) must contain the new keys with proper translations. Missing keys in non-en locales fall back silently to English and ship broken UX
- **Prefer shared components over one-off widgets.** The project is architecturally moving toward reuse — before adding new widgets/helpers/styles, search `lib/widgets/` and `lib/core/**` for an existing component. If behaviour is close but not identical, extend the shared component (add a param) rather than duplicating. Hardcoded column widths, button styles, padding scales, tile layouts, dialog shapes, form rows — all live in shared modules. Only introduce a local one-off when the shared pattern genuinely doesn't fit; then document why. Canonical examples: `AppIconButton`, `AppDialog`, `HoverRegion`, `AppTheme.radius*`, `AppFonts.*`, `AppTheme.*ColWidth` constants
- **Disable vs hide unavailable controls — depends on surface type.** On *configuration surfaces* (Settings, session-edit forms, preference dialogs), always render the control as **disabled with a tooltip + tap-toast explaining the reason** — never hide it. The user is exploring what the app can do and needs to know the option exists (cross-device install, missing hardware, missing prerequisite). On *action surfaces* (lock screen, context menus, per-row action buttons, action dialogs), **hide** unavailable actions — the user is trying to do a specific task and a greyed button is noise, not information. Disabled state must visibly affect the whole row (opacity on the full container), not just the trailing knob
- **Ask before guessing UI placement** — if ambiguous, ask once upfront
- **Cross-platform verification** — Android change → also check iOS; Windows change → also check Linux + macOS

### Dependencies & Building

- Latest **stable** versions only — no beta/dev/pre-release. OS-level deps must be **optional** with graceful runtime fallback (e.g. `flutter_secure_storage` requires libsecret on Linux — app works without it)
- **Always build via Makefile** — `make run`, `make build-linux`, `make test`, `make analyze`. Never call `flutter build`/`flutter run` directly
- **Pin external downloads in CI** — specific release version + SHA256 checksum

### What Not To Do

- Do not install packages without asking
- **Never suppress issues** — no `// NOSONAR`, `// ignore:`, `@SuppressWarnings`. Always fix the root cause
- **Never amend after push** — only new commits. Amend OK only before first push
- **All code must have tests** — target 100% coverage (excluding integration tests and tests on the actual platform). One test file per source file. Testable by design: extract pure logic from SSH/platform/I/O deps, DI over hardcoded `ref.read()` — [§14 Testing Patterns](docs/ARCHITECTURE.md#14-testing-patterns--di-hooks)
- **Tests assert spec, not current output.** Before writing any `expect(...)`, state in one sentence what the function _should_ do for that input — derived from the feature's intent, not from running the code and copying the result. **Never** run the function, observe the output, and paste it into `expect(...)` as the oracle — that's a pinning test and it cements bugs instead of catching them. This applies doubly to parsers, formatters, `localizeError`, and anything touching untrusted input. If the correct behavior is genuinely unclear, stop and ask the user rather than inventing an oracle
- **When test and code disagree, surface it — don't silently "fix" either side.** If your derived spec says X and the code returns Y, you have one of three situations: (1) real bug in code, (2) wrong spec on your side, (3) ambiguous requirement. You cannot tell which from inside the test file. Stop, report the disagreement to the user with: the input, the spec you derived + where you derived it from (commit, docstring, user-facing string, issue), and the current output. Let the user decide which side is wrong. Only after confirmation: fix code **or** update the spec. A confident "I found a bug, fixing it" on an edge case is exactly how correct behavior gets quietly regressed
- **Uncovered lines are a marker, not a target.** An uncovered line means "no test verifies the behavior this line implements" — it does NOT mean "write anything that touches this line". Do not write tests whose only goal is to execute the line (calling the function with arbitrary input and `expect(result, isNotNull)` / `isA<T>()` / "doesn't throw"). Ask first: what branch, decision, or contract does this line encode? Write a test that fails if that contract breaks. If you cannot articulate the contract, the line either needs refactoring (the logic is too implicit to test) or a user conversation (you don't understand it yet) — not a coverage-hit wrapper
- **Fuzz tests for parsers** — any function that parses untrusted input (JSON `fromJson()`, URI parsing, file format parsing) must have a corresponding fuzz test in `test/fuzz/`. Fuzz tests generate random/malformed inputs and verify the parser never crashes with unhandled exceptions. Run as part of `make test`. See [§14 Fuzz testing](docs/ARCHITECTURE.md#fuzz-testing)
- **Parallel agents** — only `git add` files YOU changed. **Do NOT run tests** — testing is the main process's job

---

## Code Quality Rules

All code must follow **Effective Dart** and pass `dart analyze` with zero issues. `make analyze` must pass before every commit. **Never suppress** — `// ignore:`, `// NOSONAR`, `@SuppressWarnings` are forbidden, always fix the root cause.

### SonarCloud rules that bite most often

Write code that already obeys these on first draft — don't write it, wait for the scanner to complain, and then refactor.

- **S3776 — cognitive complexity ≤ 15.** Each `if` / `for` / `while` / `switch case` / `&&` / `||` adds to the score, and nesting multiplies. A single widget `build()` with a tall `children: [ if … else ... if … for (…) widget(a ? b : c) ]` blows the budget fast. When in doubt:
  - Extract each conditional child into a `Widget _buildFoo(…)` helper (empty state, header row, list, footer → one helper each).
  - Pull repeated inline computations (`X ? s.foo : null`, `X ? fgDim : null`) into a local `final already = …;` before the `return DataCheckboxRow(…)`.
  - Any `for (var i = 0; i < list.length; i++) ComplexWidget(a: list[i].x, b: … ? … : …, c: … ? … : null)` → extract a `_buildRow(i)` helper.
  - **Non-widget patterns that still trip S3776** (learned the hard way, don't repeat):
    - **Top-level `if (enable) { … } else { … }` with non-trivial branches** → split the method on the boolean, e.g. `_toggleFoo(enable)` delegates to `_enableFoo()` / `_disableFoo()`. Each branch gets its own cognitive budget.
    - **Long `if (error is X) return …;` chains in a single function** → group by category and extract `_tryLocalizeFooError` helpers that return `String?`; the top-level function becomes a flat "try category → fall through" sequence.
    - **Async methods that chain 3+ phases with nested mounted / null guards** (e.g. pick file → ask password → decrypt → preview → apply) → extract each phase into a `Future<T?> _phaseFoo(…)` helper that returns `null` on cancel/failure; the caller becomes a straight-line pipeline of `await … ; if (x == null) return;` steps.
    - **Optional archive / JSON entries with nested `if (requested) { if (present) { if (valid) { … } } }`** → extract an `_entryReader` that returns `T?` and does the size/validity check at its own scope. Caller becomes `final x = requested ? _readFoo(archive) : null;`.
- **S3358 — no nested ternaries.** Patterns like `busy ? null : (forKeys ? _a : _b)` or `value == true ? doX() : value == false ? doY() : doZ()` must be rewritten as `if` / `else if` / `else` assigning to a local, or a `switch` expression. A single non-nested ternary is fine. **Also watch for the subtle case** where an outer ternary's branch is a widget constructor whose argument is itself a ternary — `active ? Icon(asc ? up : down) : null` is already S3358. Extract the whole trailing widget into a `_directionIcon(col)` helper that short-circuits on the inactive case.
- **S1854 — dead / unused values.** Don't `final x = ...;` then overwrite `x` unconditionally before use. In Dart `late final x; if (…) x = …; else x = …;` or an `if`/`else`-assigned local is the idiomatic fix.
- **S1192 — string literals duplicated ≥ 3 times.** Pull them into a `static const _kFoo = '…'` or an existing localization key.
- **S1481 — unused local vars / S1172 — unused parameters.** Either delete or prefix with `_`. Don't leave them around "just in case".
- **No `print()` / `debugPrint()`** — use `AppLogger.instance.log(message, name: 'Tag')`. **Never log sensitive data** (keys, passwords, raw PEM). Errors surfacing to the UI go through `localizeError()` so PEM / base64 are redacted.
- **No generated file edits** — `*.g.dart` and `*.freezed.dart` are excluded from analysis; change the source instead.

### Shape before scanner

If a method's body is more than ~30 lines or has three nested conditional blocks, split it up before committing. Widget `build()` methods over that threshold should already have named `_buildFoo` helpers for each section.
