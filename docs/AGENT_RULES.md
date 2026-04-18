# Agent Rules — Reference Tables

Reference material for any AI coding agent operating on this repo. Read the specific section you need, not the whole file.

## Quick Navigation by Task

### Within AGENT_RULES (this file)

| I'm about to... | Read this section |
|---|---|
| Write a commit message / bump version | [§ Commits & Versioning](#commits--versioning) |
| Open a PR / merge to main | [§ Branching & Release Flow](#branching--release-flow) |
| Write or refactor any Dart code | [§ Code Quality — SonarCloud](#code-quality--sonarcloud) + [§ Conventions](#conventions) |
| Call API of an external package (dartssh2, drift, riverpod, xterm, …) | [§ Conventions → External Libraries & APIs](#external-libraries--apis--look-up-dont-guess) — grep repo first, then Context7 / web docs / pub-cache source |
| Add a new dependency or feature that needs an OS capability | [§ Conventions → Self-Contained Binary](#self-contained-binary--end-user-installs-nothing) — bundle > fallback > optional-with-docs |
| Write or update a test | [§ Testing Methodology](#testing-methodology) |
| Add/change a user-facing string | [§ Conventions → Localization](#localization-i18n) + [§ Doc Maintenance](#documentation-maintenance-checklist) row "user-facing string" |
| Add a new widget / helper / mixin / style constant / store | [§ Conventions → Reuse First](#reuse-first-project-wide-not-just-ui) — search shared modules first |
| Add/change a UI control | [§ Conventions → Reuse First](#reuse-first-project-wide-not-just-ui) + [§ UI Components](#ui-components) (disable-vs-hide) |
| Add a new file in `lib/` | [§ Doc Maintenance](#documentation-maintenance-checklist) (which §s of ARCHITECTURE.md to update) |
| Touch theme / fonts / radii / heights | [§ Conventions → Theme & UI Constants](#theme--ui-constants) |

### Within ARCHITECTURE.md

| I need to... | Read this section |
|---|---|
| Understand the module layout | [§2 Module Map](ARCHITECTURE.md#2-module-map) |
| Work with SSH connections | [§3.1 SSH](ARCHITECTURE.md#31-ssh-coressh) + [§9.1 SSH Flow](ARCHITECTURE.md#91-ssh-connection-flow) |
| Work with SFTP / file browser | [§3.2 SFTP](ARCHITECTURE.md#32-sftp-coresftp) + [§5.2 File Browser](ARCHITECTURE.md#52-file-browser-featuresfile_browser) |
| Work with transfers | [§3.3 Transfer Queue](ARCHITECTURE.md#33-transfer-queue-coretransfer) + [§9.4 Transfer Flow](ARCHITECTURE.md#94-file-transfer-flow) |
| Work with sessions | [§3.4 Sessions](ARCHITECTURE.md#34-session-management-coresession) + [§9.3 CRUD Flow](ARCHITECTURE.md#93-session-crud-flow) |
| Work with connections | [§3.5 Connection Lifecycle](ARCHITECTURE.md#35-connection-lifecycle-coreconnection) |
| Work with encryption/security | [§3.6 Security](ARCHITECTURE.md#36-security--encryption-coresecurity) + [§13 Security Model](ARCHITECTURE.md#13-security-model) |
| Work with config | [§3.7 Configuration](ARCHITECTURE.md#37-configuration-coreconfig) |
| Add/change keyboard shortcuts | [§3.11 Keyboard Shortcuts](ARCHITECTURE.md#311-keyboard-shortcuts-coreshortcut_registrydart) |
| Work with terminal / tiling | [§5.1 Terminal](ARCHITECTURE.md#51-terminal-with-tiling-featuresterminal) |
| Work with tabs / workspace tiling | [§5.4 Tab & Workspace System](ARCHITECTURE.md#54-tab--workspace-system) |
| Work with mobile features | [§5.6 Mobile](ARCHITECTURE.md#56-mobile-featuresmobile) + [§12 Platform-Specific](ARCHITECTURE.md#12-platform-specific-behavior) |
| Use or create widgets | [§6 Widgets API](ARCHITECTURE.md#6-widgets--public-api-reference) |
| Use utilities | [§7 Utilities API](ARCHITECTURE.md#7-utilities--public-api-reference) |
| Work with theme / colors | [§8 Theme System](ARCHITECTURE.md#8-theme-system) |
| Add/change user-facing strings | [§8.1 i18n](ARCHITECTURE.md#81-internationalization-i18n) |
| Understand Riverpod providers | [§4 State Management](ARCHITECTURE.md#4-state-management--riverpod) |
| Understand data persistence / drift DB | [§11 Persistence](ARCHITECTURE.md#11-persistence--storage) |
| Work with database / DAOs | [§2 Module Map](ARCHITECTURE.md#2-module-map) (`core/db/`) + [§11 Persistence](ARCHITECTURE.md#11-persistence--storage) |
| Work with snippets | `core/snippets/` + `features/snippets/` + `providers/snippet_provider.dart` |
| Work with tags | `core/tags/` + `features/tags/` + `providers/tag_provider.dart` |
| Check data models | [§10 Data Models](ARCHITECTURE.md#10-data-models) |
| Understand CI/CD / workflows | [§15 CI/CD Pipeline](ARCHITECTURE.md#15-cicd-pipeline) |
| Check design decisions / gotchas | [§16 Design Decisions](ARCHITECTURE.md#16-design-decisions--rationale) |
| Check dependencies / versions | [§17 Dependencies](ARCHITECTURE.md#17-dependencies) |
| Write tests / understand DI | [§14 Testing Patterns](ARCHITECTURE.md#14-testing-patterns--di-hooks) |

## Documentation Maintenance Checklist

**Every code change MUST be accompanied by documentation updates.** Violation = incomplete commit.

| What changed | Update |
|---|---|
| New file in `lib/` | Add to [§2 Module Map](ARCHITECTURE.md#2-module-map) + relevant §3/§5 section |
| New/changed class, public API | Update the corresponding §3-§8 section in ARCHITECTURE.md |
| New/changed data model | Update [§10 Data Models](ARCHITECTURE.md#10-data-models) |
| New/changed provider | Update [§4 Provider Catalog](ARCHITECTURE.md#42-provider-catalog) + dependency graph |
| New/changed widget | Update [§6 Widgets API](ARCHITECTURE.md#6-widgets--public-api-reference) |
| New/changed utility | Update [§7 Utilities API](ARCHITECTURE.md#7-utilities--public-api-reference) |
| Changed data flow | Update relevant [§9 Data Flow](ARCHITECTURE.md#9-data-flow-diagrams) diagram |
| New dependency added | Update [§17 Dependencies](ARCHITECTURE.md#17-dependencies) |
| Changed persistence format | Update [§11 Persistence](ARCHITECTURE.md#11-persistence--storage) |
| Changed security model | Update [§13 Security Model](ARCHITECTURE.md#13-security-model) + SECURITY.md |
| New design decision | Add to [§16 Design Decisions](ARCHITECTURE.md#16-design-decisions--rationale) with rationale |
| New CI workflow / changed pipeline | Update [§15 CI/CD](ARCHITECTURE.md#15-cicd-pipeline) |
| Platform-specific change | Update [§12 Platform-Specific](ARCHITECTURE.md#12-platform-specific-behavior) |
| New DI hook for testing | Update [§14 Testing Patterns](ARCHITECTURE.md#14-testing-patterns--di-hooks) |
| New/changed user-facing string | Add key to `lib/l10n/app_en.arb` **and translate into every other `app_*.arb` file** (ar, de, es, fa, fr, hi, id, ja, ko, pt, ru, tr, vi, zh — 15 total). Run `flutter gen-l10n`. Use `S.of(context).key`. Missing keys in non-en locales silently fall back to English — ship broken UX |
| New/changed shared component | Before adding a new widget/helper, search `lib/widgets/` and `lib/core/**` for an existing equivalent. Extend the shared component (add a param) instead of duplicating. Update [§6 Widgets API](ARCHITECTURE.md#6-widgets--public-api-reference) |
| Architecture changed | Update CLAUDE.md if navigation links affected |
| User-visible change | Update README.md |
| Security scope change | Update SECURITY.md |

## Conventions

### Self-Contained Binary — End-User Installs Nothing
**The released app must run with zero manual setup beyond extracting / installing the bundle.** Never introduce a feature that hard-requires the end-user to install something on their OS first.

When a feature needs an OS capability, the preference order is:
1. **Bundle it** — link statically, vendor the lib, use system frameworks already present on every supported version (`sqlite3` via `pubspec.yaml` build hooks, `AVFoundation` for iOS QR scan, `AndroidX CameraX + ZXing` for Android QR scan). This is the default; pick this unless impossible.
2. **Built-in fallback** — if the OS capability is genuinely platform-specific (OS keychain, biometric API), provide a feature that works without it (master password instead of keychain). User keeps a usable app, the platform-only path is just a UX upgrade.
3. **Optional OS dep with graceful degradation** — last resort. Allowed *only* if both:
   - The app detects the missing dep at runtime and surfaces a clear, localized in-UI message naming what's missing and what's lost (not a stack trace, not a silent failure).
   - `README.md` "Installation" lists a copy-pasteable install command per platform that needs it.

Hard-requiring the user to install anything (a runtime, a service, a CLI, a native lib) is **forbidden**. If a proposed dependency can't satisfy one of the three rules above, redesign the feature or drop it.

When reviewing a diff that adds a new dependency: check `pubspec.yaml`, then check whether the dep pulls a transitive native requirement (look at the dep's README + `linux/`, `macos/`, `windows/`, `android/`, `ios/` plugin folders). If yes — verify the rule above before approving the change.

### External Libraries & APIs — Look Up, Don't Guess
**Never invent method signatures, parameter names, default values, or behaviour of any external package from memory.** Hallucinated APIs compile-fail in the best case and silently misbehave in the worst (wrong default for a keepalive timer, missed `await`, dropped error class).

Lookup order before calling an unfamiliar API:
1. **Existing usage in this repo** — `Grep` for the symbol or `import 'package:<pkg>'` first. The project already established the canonical idiom; copy that pattern instead of looking elsewhere. Canonical examples: dartssh2 (`core/ssh/`), drift (`core/db/`), pointycastle (`core/security/aes_gcm.dart`), riverpod (`providers/`), xterm (`features/terminal/`), `app_links`, `flutter_secure_storage`, `sqlite3` build hooks (`pubspec.yaml`).
2. **Context7 MCP** (if available) — `resolve-library-id` then `get-library-docs` for the exact package + topic. Pull docs into context before writing the call.
3. **Web docs** — `WebFetch` on the package's `pub.dev` page, official documentation site, or `README.md` in the GitHub repo. Pin version-specific behaviour to the version in `pubspec.yaml`.
4. **Source on disk** — read the resolved package source under `.dart_tool/pub-cache/hosted/pub.dev/<pkg>-<version>/lib/` when docs are thin or contradictory.
5. **Ask the user** if all of the above leave the contract unclear — never guess.

Specifically high-risk surfaces (already burned by hallucination in past sessions, listed in [ARCHITECTURE §16.2 API Gotchas](ARCHITECTURE.md#162-api-gotchas)): `SSHConnectionState` (NOT Flutter's `ConnectionState`), dartssh2 host-key callback signature, dartssh2 SFTP `attr.mode?.value` / `remoteFile.writeBytes()`, xterm `hardwareKeyboardOnly`. When working in `core/ssh/`, `core/sftp/`, or `features/terminal/` — assume every signature is non-obvious and verify.

### Reuse First (project-wide, not just UI)
**Before adding any new widget, helper, mixin, style constant, or store: search `lib/widgets/`, `lib/theme/`, `lib/core/**` for an existing equivalent.** If behaviour is close but not identical, **extend** the shared primitive (add a parameter) instead of forking. A second caller is the trigger to extract a shared helper; a third caller makes it mandatory. Local one-offs are allowed only when the shared pattern genuinely doesn't fit, and the reason must be obvious in code.

What this rule covers (not just UI):
- **Widgets** — `AppIconButton`, `AppDialog` (+ `AppDialogHeader`/`Footer`/`Action`), `HoverRegion`, `AppDataRow`, `AppDataSearchBar`, `StyledFormField`, `SortableHeaderCell`, `ColumnResizeHandle`, `StatusIndicator`, `MobileSelectionBar`, `AppShell`, `ModeButton`, `ConfirmDialog`, `ErrorState`.
- **Theme constants** — `AppTheme.radius{Sm,Md,Lg}`, `AppTheme.barHeight*`, `AppTheme.controlHeight*`, `AppTheme.itemHeight*`, `AppTheme.*ColWidth`, `AppFonts.{tiny,xxs,xs,sm,md,lg,xl}`. Hardcoded sizes, radii, heights, font sizes, padding scales = bug.
- **Cross-feature mixins / helpers** — `SftpBrowserMixin`, `key_file_helper.dart`, `breadcrumb_path.dart`, `column_widths.dart`, `progress_writer.dart`, `shell_helper.dart`. New cross-cutting logic gets a `*_helper.dart` or mixin, not inline copies.
- **Persistence** — every entity follows the same `Store → DAO` template ([§11 Persistence](ARCHITECTURE.md#11-persistence--storage)). Don't invent a new persistence pattern for a new entity.

Non-negotiable triggers — if any of these appear in a diff, refactor before committing:
1. Same string literal in ≥3 places (S1192) → constant or l10n key.
2. Same widget tree (≥5 lines) in ≥2 files → extract widget.
3. Same hardcoded numeric (radius, padding, width, height, fontSize) in ≥2 places → constant in `AppTheme` / `AppFonts`.
4. Same `if/else` block or async pipeline in ≥2 callers → extract helper / mixin.
5. New `*_dialog.dart` / `*_button.dart` / `*_row.dart` that doesn't extend an existing `App*` primitive → check first whether a parameter on the existing primitive solves it.

**Premature-abstraction guard:** triggers above mean *consider extraction*, not *extract no matter what*. If the third caller would force a parameter that warps the first two (e.g. a flag toggling a whole different layout, or coupling unrelated concerns), leave the duplication and add a `// TODO(reuse): N callers — revisit when shape stabilises` comment instead. Reuse exists to reduce surface area, not to grow it.

Reference: full project-wide formulation in [ARCHITECTURE §1 Reuse principle](ARCHITECTURE.md#1-high-level-overview).

### Architecture (non-obvious rules)
- **No SCP** — dartssh2 doesn't support it; SFTP covers all use cases
- SSH keys accepted **both as file and text** (paste PEM)
- `.lfs` export format and import modes — single source of truth: [§3.9 Import](ARCHITECTURE.md#39-import-coreimport)
- Credentials in `CredentialStore` (AES-256-GCM), NOT in plain JSON — [§3.6 Security](ARCHITECTURE.md#36-security--encryption-coresecurity)
- **State placement** — app-wide state → Riverpod `NotifierProvider`; widget-local state (dialog / pane / panel / tab) with constructor-injected args or caches → `ChangeNotifier` + `AnimatedBuilder` (canonical examples: `FilePaneController`, `UnifiedExportController`, `SessionPanelController`, `TransferPanelController`). Side-channel Riverpod overrides for widget-local state = boilerplate with no win — [§4.3 Widget-local controllers](ARCHITECTURE.md#43-widget-local-controllers-changenotifier)

### Theme & UI Constants
OneDark theme: centralized in `app_theme.dart`, semantic color constants, no hardcoded `Colors` — [§8 Theme](ARCHITECTURE.md#8-theme-system)

- **Font sizes** — never hardcode `fontSize`. Use `AppFonts.tiny`/`xxs`/`xs`/`sm`/`md`/`lg`/`xl` (mobile +2 px)
- **Border radius** — never hardcode `BorderRadius.circular(N)`. Use `AppTheme.radiusSm` (4), `radiusMd` (6), `radiusLg` (8). Exception: pill-shaped elements
- **Heights** — never hardcode height literals. Use `AppTheme` constants: `barHeight{Sm,Md,Lg}`, `controlHeight{Xs..Xl}`, `itemHeight{Xs..Xl}`

### UI Components
- **Buttons & hover** — `AppIconButton` for all icon buttons. `HoverRegion` for custom hover containers. Never use bare `IconButton`, `InkWell` for buttons, or manual `MouseRegion`+`GestureDetector`+`setState(_hovered)`. Exception: `context_menu.dart`, mobile touch buttons — [§6 Widgets API](ARCHITECTURE.md#6-widgets--public-api-reference)
- **Dialogs** — `AppDialog` for all modal dialogs. Never use bare `AlertDialog`. Complex dialogs: compose from `AppDialogHeader`/`AppDialogFooter`/`AppDialogAction`. Progress: `AppProgressDialog.show()`. Exception: mobile touch buttons keep `Material`+`InkWell` for ripple
- **Text overflow protection** — localized text in `Row` or fixed-width — wrap with `Flexible`/`Expanded` + `overflow: TextOverflow.ellipsis`. For label columns use `ConstrainedBox(maxWidth:)` instead of fixed `SizedBox(width:)`
- **Accessibility** — wrap interactive list items (session rows, file rows) and panel headers with `Semantics` widget. Use `label` for screen reader text, `button: true` for tappable items, `selected` for selection state, `header: true` for section headings. `StatusIndicator` includes built-in `Semantics`
- **Disable vs hide unavailable controls — depends on surface type.** On *configuration surfaces* (Settings, session-edit forms, preference dialogs), always render the control as **disabled with a tooltip + tap-toast explaining the reason** — never hide it. The user is exploring what the app can do and needs to know the option exists (cross-device install, missing hardware, missing prerequisite). On *action surfaces* (lock screen, context menus, per-row action buttons, action dialogs), **hide** unavailable actions — the user is trying to do a specific task and a greyed button is noise, not information. Disabled state must visibly affect the whole row (opacity on the full container), not just the trailing knob
- **Prefer shared components** — full rule in [§ Reuse First](#reuse-first-project-wide-not-just-ui)

### Localization (i18n)
All user-facing strings MUST use `S.of(context).xxx`. Never hardcode strings in widgets — treat this as a bug. Add keys to `lib/l10n/app_en.arb`, run `flutter gen-l10n`, use `S.of(context).newKey`. Exceptions: constructor defaults (no context), log messages, `_AlreadyRunningApp`. Tests must include `localizationsDelegates: S.localizationsDelegates, supportedLocales: S.supportedLocales` in every `MaterialApp`. See [§8.1 i18n](ARCHITECTURE.md#81-internationalization-i18n)

## Code Quality — SonarCloud

All code must follow **Effective Dart** and pass `dart analyze` with zero issues. `make analyze` must pass before every commit. **Never suppress** — `// ignore:`, `// NOSONAR`, `@SuppressWarnings` are forbidden, always fix the root cause.

### Rules that bite most often

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

## Testing Methodology

Target: 100% coverage (excluding integration tests and tests on the actual platform). One test file per source file. Testable by design: extract pure logic from SSH/platform/I/O deps, DI over hardcoded `ref.read()` — [§14 Testing Patterns](ARCHITECTURE.md#14-testing-patterns--di-hooks).

- **Tests assert spec, not current output.** Before writing any `expect(...)`, state in one sentence what the function _should_ do for that input — derived from the feature's intent, not from running the code and copying the result. **Never** run the function, observe the output, and paste it into `expect(...)` as the oracle — that's a pinning test and it cements bugs instead of catching them. This applies doubly to parsers, formatters, `localizeError`, and anything touching untrusted input. If the correct behavior is genuinely unclear, stop and ask the user rather than inventing an oracle.
- **When test and code disagree, surface it — don't silently "fix" either side.** If your derived spec says X and the code returns Y, you have one of three situations: (1) real bug in code, (2) wrong spec on your side, (3) ambiguous requirement. You cannot tell which from inside the test file. Stop, report the disagreement to the user with: the input, the spec you derived + where you derived it from (commit, docstring, user-facing string, issue), and the current output. Let the user decide which side is wrong. Only after confirmation: fix code **or** update the spec. A confident "I found a bug, fixing it" on an edge case is exactly how correct behavior gets quietly regressed.
- **Uncovered lines are a marker, not a target.** An uncovered line means "no test verifies the behavior this line implements" — it does NOT mean "write anything that touches this line". Do not write tests whose only goal is to execute the line (calling the function with arbitrary input and `expect(result, isNotNull)` / `isA<T>()` / "doesn't throw"). Ask first: what branch, decision, or contract does this line encode? Write a test that fails if that contract breaks. If you cannot articulate the contract, the line either needs refactoring (the logic is too implicit to test) or a user conversation (you don't understand it yet) — not a coverage-hit wrapper.
- **Fuzz tests for parsers** — any function that parses untrusted input (JSON `fromJson()`, URI parsing, file format parsing) must have a corresponding fuzz test in `test/fuzz/`. Fuzz tests generate random/malformed inputs and verify the parser never crashes with unhandled exceptions. Run as part of `make test`. See [§14 Fuzz testing](ARCHITECTURE.md#fuzz-testing).
- **UI changes = test updates** — proactively update all tests that reference changed widget names, labels, or finders.

## Commits & Versioning

- **Agent does not commit or push unless the user explicitly asks.** "commit" = commit only, "commit and push" = commit + push.
- **HARD STOP between fixes** — implement fix → write tests → update docs → **stop and ask user to commit**. Do NOT start the next fix until the current one is committed. **Exception:** when the user explicitly asks to fix everything at once ("fix all and push"), execute end-to-end without pausing between fixes.
- Format per [CONTRIBUTING.md](CONTRIBUTING.md#commit-messages). Messages drive auto-changelog — keep them user-readable.
- **Use `type(scope):` with parenthesized scope** for commits that touch a specific module (e.g. `refactor(import): ...`, `test(known-hosts): ...`, `feat(installer): ...`). Drop the scope only when the change is genuinely cross-cutting and no single module name fits. Scope must be lowercase, alphanumeric + dashes.
- **Version bumps are automatic.** The `/pr` skill runs `scripts/bump-version.sh` before creating PR — it parses conventional commits since the last tag and bumps `pubspec.yaml` (patch for fix/refactor/perf/build/deps, minor for feat, major for BREAKING CHANGE; chore/docs/test/ci/Revert = no bump). **Do NOT bump version manually** — just use correct conventional commit prefixes. Dependabot PRs are bumped by CI (`dependabot-auto.yml`).
- **Never amend after push** — only new commits. Amend OK only before first push.
- **Green CI before merging to main** — pre-commit hook runs `make check` automatically.

## Branching & Release Flow

- **Default working branch is `dev`.** Always work on `dev` unless explicitly told otherwise. Never push directly to `main`.
- Repository is **public** on GitHub.

| Scenario                    | What to do                                                          |
| --------------------------- | ------------------------------------------------------------------- |
| App change (feat/fix/refac) | `bump-version.sh` on dev → PR `dev` → `main` → CI → auto-tag → release |
| Tests/docs/CI only          | Merge to `main` — no bump, no tag, no release                      |
| Dependabot deps             | Auto: PR to main → bump in branch → merge → CI → auto-tag → release |
| Manual build                | `gh workflow run build-release.yml` — fails if CI hasn't passed     |
| Failed build (re-trigger)   | `gh workflow run build-release.yml --ref v{VERSION}`                |
