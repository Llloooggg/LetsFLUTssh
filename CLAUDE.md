# LetsFLUTssh — Development Guide

Lightweight cross-platform SSH/SFTP client (Dart/Flutter, all 5 desktops + mobile). Open-source alt to Xshell/Termius. **Solo developer project.** This file is the single source of truth for agent rules.

## Documentation Map

- **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** — module structure, APIs, data flows, design decisions. 3000+ lines.
- **[`docs/USER_GUIDE.md`](docs/USER_GUIDE.md)** — end-user reference. Update whenever a user-visible flow / toggle / surface changes.
- **[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md)** — build instructions, code style for humans.

**Lookup discipline.** Never read `ARCHITECTURE.md` cover-to-cover. Use the `/doc <topic|§N.M>` skill (greps the heading, reads only that slice) or open the TOC at the top of the file and `Read` with `offset`+`limit`. Cross-links widen the read = another narrow fetch, not a full Read. References below as `§N.M` mean "look it up via /doc"; bare links are kept only where the anchor is load-bearing.

---

## Always-On Rules

Apply on every response without re-reading.

- **Don't commit or push unless asked.** "commit" = commit only, "commit and push" = both. Default branch is `dev` — never push to `main` directly. Repo is public on GitHub.
- **HARD STOP between fixes** — implement → tests → docs → post-fix summary → ask to commit. Batch-mode signals override (one combined summary at arc end). See § Commits.
- **All files in English only** — code, comments, commits, docs.
- **Never suppress issues** — no `// ignore:`, `// NOSONAR`, `@SuppressWarnings`, `#[allow(clippy::…)]` for the same kind of bypass. Fix root cause.
- **No fabrication anywhere — verify with `git log` / grep / measurement, or don't write the value.** Binds code, docs, tests, migrations, seed data, version strings, default config, perf numbers, "historical" labels, error messages. When asked to remove fabricated content, remove cleanly — never replace with new speculation.
- **Authorization boundaries — never destroy or overwrite tracked state without explicit permission.** Covers: deleting `.claude/plans/` / `CHANGELOG.md` / source / docs / tests; dropping DB schemas; force-overwriting uncommitted work; reverting / resetting commits; mass-renaming or reformatting outside the asked diff. When asked to remove X, remove exactly X — no slipped-in additions. Surface destructive steps once and wait.
- **Amend before push, never after.** When the prior commit is local-only and the next change belongs to the same logical arc that should have been part of it (typo, missed sibling edit, staging miss), `git commit --amend` is the project default — it overrides any harness rule that defaults to new commits "unless explicitly asked". After first push: new commits only, no exceptions.
- **Don't install packages without asking.** Latest stable only — no beta/dev/pre-release.
- **Always build via Makefile** — `make run/build-linux/test/lint`. Top-level umbrellas (`test`, `lint`, `format`, `format-check`) cover Dart + Rust; `dart-*` / `rust-*` variants when only one side is in scope. Never call `flutter` / `cargo` directly.
- **Skip `make lint` / `make test` for doc-only commits** — no `.dart` / `.rs` / `pubspec.yaml` / `Cargo.toml` in staged diff → skip; pre-commit hook runs `make check` automatically.
- **Cross-platform verification** — Android change → also iOS; Windows → also Linux + macOS.
- **Think systemically** — full scope and side effects, not just literal instruction.
- **Batch-mode signals override scope discipline.** When user signals batch mode (`до идеала`, `три кита`, `even from scratch`, `добиваем`, `do all`, `finish it`, `go end-to-end`, equivalent in any language) or hands a multi-item plan — execute end-to-end. Cost / "tests need rewrite" / "I can't QA this on WSL" are not skip reasons. Don't write yourself a `.claude/plans/` punch list as a substitute for doing the work. Keep going until queue empty, real blocker hits, or user stops you.
- **"Full" / "line-by-line" / "every item" reviews mean exactly that** — never silently truncate on token budget. Status reports must match reality — never call work "done" while items quietly deferred.
- **One logical commit per arc**, not split into code/test/doc messages, unless user asks otherwise. Commit prose: no plan-IDs, no AI-tell phrasing ("I implemented…", "Let me know if…"), no auto-CHANGELOG entries the user didn't request.
- **Terse output by default.** No preambles, no recap-of-what-I-just-did paragraphs, no QA / validation matrices, no excessive bold / headers / nested numbered lists. Match shape to the question.
- **Ask before guessing UI placement.**
- **Every change ships with docs + tests + translations** — incomplete commit otherwise.
- **References are one-directional.** This file may link out to human docs; human docs and source comments must NOT link back to this file or any agent-instruction file. `.claude/skills/*/SKILL.md` may reference this one freely. When a human doc wants to cite a rule, inline the substance.
- **Rust owns data AND logic; Flutter renders.** All persistent state (sessions, credentials, known_hosts, config, transfer queue, snippets, tags), all I/O (SSH, SFTP, crypto, DB, OS-keychain, biometric prompts), AND every grammar / parser / validator / format-checker / decision tree lives in `lfs_core` / `lfs_os_security`. Flutter holds **only the rendering surface** — focus, hover, scroll, dialog visibility, the raw textual buffer behind a TextField until the user submits, animation controllers. No exceptions. No carve-outs for "form-level validation", "trivial grammar checks", "fast-path for the common case", "test contexts that don't load FRB", or "test-infrastructure quirks". If a sync FRB call hangs under `pumpAndSettle`, fix the test infrastructure — write a `pumpUntilFrbSettles` helper, file an upstream FRB issue, bootstrap the DB / app state the test needs. Don't put grammar Dart-side to work around it. If it's a rule about what input means or how output should look, it lives in Rust. Data flow is one-way for truth: Rust → FRB → Riverpod/ChangeNotifier → widgets. **Don't cache Rust-owned data in Dart singletons / static fields / module-level `late` vars / Riverpod NotifierProviders that wrap a Rust store** — always re-fetch via FRB (or subscribe to the Rust-side `BusEvent` stream) so a Rust-side mutation can't drift from a stale Dart copy. Mutations always go Rust-side; Dart sends an FRB call and re-reads, never patches a local copy.
- **Editing under `rust/`** — `lfs_core` MUST NOT depend on `flutter_rust_bridge` / `tauri` / any frontend crate; `lfs_os_security` is the single audit perimeter for OS-API FFI. After edits: `make rust-format rust-lint rust-test`; if FRB API surface (`rust/crates/lfs_frb/src/api/*.rs`) changed, also `make rust-codegen` and stage regenerated `lib/src/rust/`. `pubspec.yaml` `flutter_rust_bridge:` runtime and `rust/crates/lfs_frb/Cargo.toml` build dep MUST match codegen CLI version exactly. Layout: §3.14.
- **Cold-start path — STRICT INVARIANT**: nothing on cold-start imports `lib/src/rust/...` or calls FRB. Pre-FRB FRB calls throw `StateError("flutter_rust_bridge has not been initialized")`. Wire FRB-touching listeners from `_LetsFLUTsshAppState._wireFrbDependentBootstrapListeners` AFTER `_initRustCoreOrFatal` returns. See § Cold-start ordering.
- **Persisted-file wire format change** — bump `SchemaVersions`, ship `Migration`, register in `lfs_core::migration::registry::build_app_registry`, test the chain. `.lfs` future-version handling is rejection-only (`read_archive_to_pending` rejects newer-version archives — not a registry). Intra-DB schema changes follow drift bootstrap. Developer guide: §3.6.
- **Parallel agents** — only `git add` files YOU changed. Do NOT run tests — main process's job.
- **Save plans / audits / multi-axis findings to `.claude/plans/<topic>-<YYYY-MM-DD>.md`** (gitignored), paired with a TaskList. Never hold large analyses only in chat. `docs/` is human-audience and forbids LLM asides; memory is for cross-session preferences, not project-state snapshots.
- **Plans are engineering punch-lists — no QA inside them.** No "manual test plan" / "validation matrix" / per-platform QA bullets. User owns QA scope.
- **No plan-item IDs in git-tracked artefacts** — no `P1.2-*`, `Phase E1`, `Task 3.2`, `stage 6.6` shapes in commits, code, docs, filenames, headers, even when the plan itself is in git. ARCHITECTURE.md `§N.M` cross-refs are fine — stable doc anchors. Prose-wise: `"ships alongside the overlay methods added to the native plugins"`. Before staging, grep diff and commit message for `/P[0-9]/`, `/Phase [0-9A-Z]/`, `/stage [0-9]/`, `/Task [0-9]/`, `/[A-Z][0-9] /`.

---

## Docs First — Read Before, Fix Drift, Update After

**The single most important discipline.** Code is temporary; docs are how intent survives. Treat `ARCHITECTURE.md` as a first-class deliverable. Every task — planning, editing, bug-fixing, refactor, review — is also a docs task.

**Audience — write for humans, always.** `ARCHITECTURE.md`, `README.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md` and every other git-tracked doc are written for humans. No LLM asides. Agent-specific guidance stays in this file. The split is absolute.

**Every § covers both *how* (mechanism — states, inputs, outputs, invariants, failure modes) and *why* (rationale — constraint, past incident, rejected alternative, trade-off accepted).** Only-how leaves intent guessable; only-why leaves mechanism re-derivable.

**Discipline:**

1. **TOC → specific §, never cover-to-cover** (see Lookup discipline above). Applies at planning stage too.
2. **If the § is missing or ambiguous: read the code, then fill the gap in the § in the same commit.**
3. **If you find code-doc drift, fix the doc in the same commit.** Code is source of truth on current behaviour. Don't extend a stale § with matching stale additions. If code drifted from intended design, flag and ask — don't paper over.
4. **Walk the Documentation Maintenance Checklist after edits** — update every triggered §, same commit.
5. **Cross-link related §s.** Docs are a graph. When the cross-link target doesn't exist, **extract it** — create the § or lift the paragraph, then link. When you rename, move, merge, split, or delete a §, update every inbound link in the same commit (`rg -- 'old-anchor-slug'`). When in doubt, link to file not anchor.
6. **Extend docs proactively.** Non-trivial behaviour under-documented, important invariant only implicit in code, magic number without rationale, § missing "why" → write it up. Extending is the default; thinning requires justification.
7. **If writing the § revealed the code is too tangled, propose rewriting the code.** Documenting is the most honest review the module gets. Signs: needs a flowchart for one method's control flow; two sub-sections describe "same but for case Y"; "why" paragraph cannot find a coherent constraint; invariant cannot be stated as a single sentence.

"Forgot to check docs", "the docs didn't say", "the link broke because I renamed the target", "the code was ugly but technically worked" — all invalid skip reasons.

---

## Documentation Maintenance Checklist

**Every code change MUST be accompanied by documentation updates.** Violation = incomplete commit.

General rule: whatever you change in `lib/` or `rust/`, update the corresponding §3–§10 in ARCHITECTURE.md (module map, API tables, data models, providers, widgets, utilities, data flows). Plus these non-obvious triggers:

| Trigger | Action |
|---|---|
| Changed persistence schema (rusqlite SQL: column / table / index) | Update §11. Schema lives in `lfs_core::db::*`, bootstrapped idempotently on open; structural changes need additive `ALTER TABLE` / `CREATE TABLE IF NOT EXISTS` so existing user DBs upgrade without wipe |
| Changed wire format of persisted file (`config.json`, `credentials.kdf`, hardware-vault blob, `.lfs` archive) **or** added new envelope artefact | Bump `SchemaVersions::<X>`, ship `Migration`, register in `lfs_core::migration::registry::build_app_registry`, add chain test (§3.6) |
| Edited FRB API surface (`rust/crates/lfs_frb/src/api/*.rs`) | Run `make rust-codegen`, stage regenerated `lib/src/rust/` in same commit |
| Touched any `rust/**/*.rs` | Run `make rust-format rust-lint rust-test`, update relevant ARCHITECTURE § |
| Changed security model | Update §13 + SECURITY.md |
| New design decision | Add to §16 with rationale |
| New CI workflow / changed pipeline | Update §15 |
| Platform-specific change | Update §12 |
| New/changed user-facing string | Add key to `lib/l10n/app_en.arb` **and translate into every other `app_*.arb`** (15 total: ar, de, en, es, fa, fr, hi, id, ja, ko, pt, ru, tr, vi, zh). Run `flutter gen-l10n`. Use `S.of(context).key` |
| User-visible change | Update README.md **and** USER_GUIDE.md — relevant § with usage steps, examples, platform caveats |
| New end-user feature | Add a top-level § in USER_GUIDE.md linked from its TOC |

---

## Conventions

### Three Pillars + Capability Ladder

Locked priorities: **ideal code, security, optimality**. Every migration / refactor / cleanup decision weighs against these only. Inconvenience is not a skip reason. Bar to skip is one of:

1. **Moving it makes the system worse** — measurable safety / perf / consistency regression. Examples: single-instance gate moved to native shell (D-Bus / `CreateMutexW` / `LSMultipleInstancesProhibited`) because Dart shapes ran post-engine-boot; cold-start handlers stay pure Dart because pre-FRB FRB calls hang for minutes. Bar is "concrete regression we can point at".
2. **The replacement primitive cannot exist** — language/framework lacks it (Riverpod is Dart-only; `BuildContext` cannot live outside Flutter).
3. **The user explicitly authorized the skip** for that specific item.

**Cost is not a selection criterion.** Complementary defences = union (defence-in-depth), not pick-cheapest. Static lint + runtime fallback + observability for the same fault class are all three. Ranking alternatives by implementation cost ("cheap / medium / heavy") is an anti-pattern. Rank by best practice. Cost shows up only when telling the user how long the work will take.

**Capability ladder** — when a feature needs an OS capability or has a primary path unavailable on a platform, pick the highest rung that works:

1. **Bundle** — link statically, vendor the lib, use system frameworks present on every supported version (sqlite3 via build hooks, AVFoundation iOS QR, AndroidX CameraX + ZXing Android QR). Default; pick this unless impossible.
2. **Built-in fallback** — when the OS capability is genuinely platform-specific (OS keychain, biometric API), provide a feature that works without it (master password instead of keychain). User keeps a usable app.
3. **Per-platform native implementation** — Kotlin / Swift / ObjC / C / Rust via MethodChannel/FFI. Prefer native over Dart when measurably better on perf, functionality (Windows Hello `KeyCredentialManager`, Android `BiometricPrompt.CryptoObject`, iOS `SecAccessControl`), or integration depth. Authorisation per "Don't Escalate" below.
4. **Honestly hide** — when the platform cannot meet the bar at any reasonable cost (no unified API, fragmented drivers — Linux biometric binding is canonical), render the control as **disabled with a reason**. A hidden-but-honest "Not available on Linux" row is better than a weaker path that looks strong.
5. **Optional OS dep with graceful degradation** — last resort, the only rung that permits an end-user install step. Allowed only if all three hold: (a) app detects missing dep at runtime, shows short localized "X unavailable because Y is not installed" — one line, no stack trace, no install commands in UI; (b) configuration-surface control disabled with tooltip carrying the same reason; (c) `README.md` "Installation" lists copy-pasteable command per affected platform. Canonical: Linux biometric — `fprintd` cannot be bundled, master-password remains core, Settings toggle disabled with reason, README has per-distro snippet.
6. **Weaker path with honest label** — only when (a) the ladder above has no better answer, (b) the weaker path delivers non-trivial value on its own, (c) UI states what the user got — `Software-gated`, `DPAPI (software-backed)`, `Keyring (no biometric binding)`. **Never label a weaker path with the same words as the stronger one.**

Hard-requiring user installs to launch the core app is forbidden. When choosing a path for an authorised feature, write "why native" or "why Dart" into the commit message or backlog entry.

**Surface every improvement path — never bury it.** When you notice drift from the three pillars, suboptimal code, architectural inconsistency, dead code, weakening labels missing on a softer path, or any opportunity to bring something closer to ideal — raise it to the operator in the same response, even when it's outside the literal task. One sentence is enough ("noticed X is suboptimal because Y; want me to handle it?"). The operator decides scope; your job is to make the choice visible. **Never silently park an improvement** as "working = OK", "low priority", "out of scope of current task", "kept native today", "defensible because it's small", or "deliberately deferred" without operator confirmation in this conversation or a prior plan. Don't unilaterally expand the literal task into a multi-day refactor either — surface, then wait for the call. Treat phrases "true X", "real X", "verified X", "proper X" as red flags when *you* feel tempted to use them to re-pitch a stable decision; but honest drift always gets named.

**Anti-patterns to suppress:**
- Offering exit ramps ("session closed?", "wrap up?", "continue or stop?") between every step.
- Pre-emptively declaring a sweep "subjective" / "needs your anchor" without trying.
- Conflating "this WSL box can't test platform X" with "no point writing the code".
- `TODO` / `FIXME` / `XXX` markers as deferrals.
- Ranking alternatives by implementation cost.
- A fallback shipping without a visible downgrade label, or instead of a feasible stronger path.

This rule overrides "don't add features beyond what the task requires" for migration / refactor work. **For one-off bug fixes**, pillars apply to general direction; they don't compel rewriting unrelated code that happens to be touched.

### External Libraries & APIs — Look Up, Don't Guess

**Never invent method signatures, parameter names, default values, or behaviour from memory.** Lookup order:
1. **Existing usage in this repo** — `Grep` for the symbol or `import 'package:<pkg>'`. Canonical: russh / russh-sftp under `rust/crates/lfs_core/src/ssh/`, rusqlite under `.../db/`, RustCrypto (`aes-gcm`, `argon2`, `ed25519-dalek`) under `.../crypto/`, OS-bound surfaces under `rust/crates/lfs_os_security/`, FRB bindings under `lib/src/rust/`.
2. **Context7** — `mcp__context7__resolve-library-id` then `mcp__context7__get-library-docs`.
3. **Web docs** — official site, package README on pub.dev / crates.io / GitHub.
4. **Source** — `~/.pub-cache/` (Dart) or `~/.cargo/registry/` (Rust).

If still unknown, ask. Do not guess.

### Reuse First (project-wide)

**Before adding any widget, helper, mixin, style constant, or store: search `lib/widgets/`, `lib/theme/`, `lib/core/**` for an existing equivalent.** Behaviour close but not identical → **extend** the shared primitive (add a parameter), don't fork. Inline implementation in another file counts the same: lift it to `lib/widgets/` first, swap the original call site, then build your new caller on top. Shipping a second inline copy "to unblock" leaves every later caller copying the wrong one.

**Coverage:** widgets (`AppIconButton`, `AppDialog` + `AppDialogHeader`/`Footer`/`Action`, `HoverRegion`, `AppDataRow`, `AppDataSearchBar`, `StyledFormField`, `SortableHeaderCell`, `ColumnResizeHandle`, `StatusIndicator`, `MobileSelectionBar`, `AppShell`, `ModeButton`, `ConfirmDialog`, `ErrorState`); theme constants (`AppTheme.radius{Sm,Md,Lg}`, `barHeight*`, `controlHeight*`, `itemHeight*`, `*ColWidth`, `AppFonts.{tiny,xxs,xs,sm,md,lg,xl}`); cross-feature mixins / `*_helper.dart` files; persistence (Store → DAO template per §11).

**Non-negotiable extraction triggers** — refactor before committing if:
1. Same string literal in ≥3 places (S1192) → constant or l10n key.
2. Same widget tree (≥5 lines) in ≥2 files → extract widget.
3. Same hardcoded numeric (radius, padding, width, height, fontSize) in ≥2 places → constant in `AppTheme` / `AppFonts`.
4. Same `if/else` block or async pipeline in ≥2 callers → extract helper / mixin.
5. New `*_dialog.dart` / `*_button.dart` / `*_row.dart` not extending an existing `App*` primitive → check first whether a parameter on the existing primitive solves it.

**Premature-abstraction guard:** triggers mean *consider extraction*, not *extract no matter what*. If the third caller would force a parameter that warps the first two, leave the duplication and add `// TODO(reuse): N callers — revisit when shape stabilises`. Reuse exists to reduce surface area, not grow it.

### Comments — Short, Current, No Fabricated Rationale

Comments are load-bearing when they exist — a present invariant the next reader cannot infer from well-named identifiers.

**1. Short.** ≤5 lines, thought finishes inside the budget. One coherent point: name a trap, state an invariant + its why, call out a non-obvious ordering. Never multi-paragraph. If the thought needs more room, write it into `ARCHITECTURE.md` and point: `// See ARCHITECTURE.md §3.6 → SecretStore for the plaintext-discipline rule.`

**2. Current state only — no retrospective.** A comment describes the code *as it is now*. Forbidden phrases: `originally...`, `previously...`, `after the migration...`, `replaces the legacy...`, `now retired`, `the legacy path...`, `before we...`, `we used to...`, `Mirrors the prior...`, `pre-fix...`. The "what was the bug, what is the new shape" prose belongs in the **commit message**.

Exception — when the prior shape can come back as a regression, name the trap. State the invariant + a one-line why:
```dart
// `\x1B[H` resets the cursor; `\x1B[2J` alone leaves it at the
// last write position and the next paint redraws over stale lines.
```

Review check: grep staged diff for `previously`, `pre-fix`, `the prior`, `the earlier`, `Mirrors the prior`, `used to`, `originally`, `legacy` (in narrative voice — `legacy fallback path` describing a runtime alternative is fine; `replaces the legacy` is not).

**3. No fabricated rationale.** Only cite platforms, measurements, failure mechanisms, behavioural claims real and verifiable from code, git log, or captured user report. Forbidden: concrete timings without source (`~3 s on Win IoT`); generic-sounding alternatives that imply measurement (`non-trivial latency`); specific OS subsystems pinned as cause without link (`Defender real-time scan`, `Gatekeeper signature check`); causal chains explaining *why* when you have only the *what*. Document the structural reason (the bug class prevented, the contract enforced).

Same rule applies to Rust `//`/`///`/`//!` and Dart `///` doc comments.

### Architecture (non-obvious rules)

- **No SCP** — SFTP covers every transfer use case; `lfs_core::sftp` is the only file-transfer surface.
- SSH keys accepted **both as file and text** (paste PEM).
- `.lfs` export format and import modes — single source of truth: §3.9.
- Credentials in `CredentialStore` (AES-256-GCM), NOT in plain JSON — §3.6.
- **State placement** — app-wide UI state → Riverpod `NotifierProvider` reading from FRB; widget-local UI state (dialog / pane / panel / tab) with constructor-injected args or caches → `ChangeNotifier` + `AnimatedBuilder` (canonical: `FilePaneController`, `UnifiedExportController`, `SessionPanelController`, `TransferPanelController`). Side-channel Riverpod overrides for widget-local state = boilerplate with no win — §4.3. **Persistent state never lives in either** — see "Rust owns data" in Always-On.

### Logging — AppLogger, Auto-Sanitized

Every log line goes through `AppLogger.instance.log(message, name: 'Tag', error: e, stackTrace: st)`. **Never `print` or `dart:developer`'s `log` directly** — both bypass the sanitizer (and `print` survives release builds). The only log channel is the opt-in file at `<appSupportDir>/logs/letsflutssh.log`. Default threshold `Off` (privacy-first); `logCritical` bypasses for crash breadcrumbs.

**Auto-sanitization** scrubs PEM private keys, long base64 runs, IPv4/IPv6, `user@host`, `host:port`, Windows `C:\Users\<name>` and Unix `/home/<name>` paths, `as <user>` / `user=<user>` / `login=<user>` shapes. You do NOT pre-sanitize. Sanitizer cannot catch **free-form user-chosen strings** (session labels, key labels, tag names, snippet titles, folder names) — log marker `<label>` not the value. Details: § Error Handling Architecture.

**Add logs generously** at every load-bearing state transition (entry/exit of disk/DB/network/subprocess/native ops; every branch of user-consequential `try/catch`, including swallowed-and-continued; every decision on ambiguous input; every place a previous bug could surface). Default sink is off — only opted-in users pay the write. Test: "could a user hand me the log and could I tell what happened without reproducing?"

**Never embed a raw password, passphrase, or private-key byte** in a message. Log `'Password verify failed'`, never `'Password verify failed: $typedPassword'`. Sanitizer handles exception text — `log('X failed: $e', error: e)` is fine.

**Levels** — `info` default; `warn` for degraded-but-recoverable; `error` for unrecoverable / data at risk. Auto-rules: `log(..., error: e)` without explicit `level:` auto-promotes to error — override with `level: LogLevel.warn` for recoverable paths that carry an exception, otherwise viewer tints red. `logCritical` is always error. No debug rung — per-packet/per-frame tracing wraps behind a local flag you ship and revert.

**Tag names are module-scoped, not file-scoped**: `'FilePane'`, `'Session'`, `'KdfParams'`, `'MigrationRunner'`, `'KnownHosts'`, `'SecureClipboard'`. Grep existing `name:` usage before inventing.

**Critical paths use `logCritical`** — global crash handlers (`FlutterError.onError`, `PlatformDispatcher.onError`, `runZonedGuarded`), migration fatals, DB integrity-probe failures.

**Dev / beta builds override threshold at compile time** via `--dart-define=LETSFLUTSSH_LOG_LEVEL=<info|warn|error>`. `make run` wires this to `info` by default. Never set in release.

### Theme & UI Constants

OneDark theme: centralized in `app_theme.dart`, semantic color constants, no hardcoded `Colors` — §8.

- **Font sizes** — never hardcode `fontSize`. Use `AppFonts.{tiny,xxs,xs,sm,md,lg,xl}` (mobile +2 px).
- **Border radius** — never hardcode `BorderRadius.circular(N)`. Use `AppTheme.radius{Sm,Md,Lg}` (4/6/8). Exception: pill-shaped elements.
- **Heights** — never hardcode height literals. Use `AppTheme.barHeight{Sm,Md,Lg}`, `controlHeight{Xs..Xl}`, `itemHeight{Xs..Xl}`.

### UI Components

- **Buttons & hover** — `AppIconButton` for all icon buttons. `HoverRegion` for custom hover containers. Never bare `IconButton`, `InkWell`-as-button, or manual `MouseRegion`+`GestureDetector`+`setState(_hovered)`. Exception: `context_menu.dart`, mobile touch buttons.
- **Dialogs** — `AppDialog` for all modal dialogs. Never bare `AlertDialog`. Complex dialogs compose from `AppDialogHeader`/`AppDialogFooter`/`AppButton`. Progress: `AppProgressDialog.show()`. Exception: mobile touch buttons keep `Material`+`InkWell` for ripple.
- **Text selection is opt-in on desktop — clickable ≠ selectable.** No global `SelectionArea` wraps the desktop shell (it broke `ThresholdDraggable` — `SelectionArea`'s pan recogniser claimed gestures ahead of `MultiDragGestureRecognizer`). Wrap specific prose surfaces in `AppSelectionArea` locally: dialog bodies, threat lists, release-notes bodies, help prose. Never wrap a container hosting a drag target, `AppButton`, or interactive row. Mobile keeps one `AppSelectionArea(child: MobileShell())`. Inside any scoped `AppSelectionArea`, every clickable tile / row / header / badge opts out via `SelectionContainer.disabled` — `HoverRegion` auto-wraps; `InkWell` does not, wrap its child explicitly. Form field labels also opt out. — § Selection scoping.
- **Session panel shortcut / focus / clipboard contract** — shortcut dispatch uses `CallbackShortcuts` (not `Focus.onKeyEvent`); empty-sidebar tap clears the focused pointer but keeps `FocusNode` focused; folder click is two-phase (focus → toggle); paste resolves target lazily at paste time; clipboard holds session id pointer (no TTL, no RAM copy). §5.3.
- **Text overflow** — localized text in `Row` or fixed-width → wrap with `Flexible`/`Expanded` + `overflow: TextOverflow.ellipsis`. For label columns use `ConstrainedBox(maxWidth:)` not fixed `SizedBox(width:)`.
- **Accessibility** — wrap interactive list items (session rows, file rows) and panel headers with `Semantics` (`label`, `button: true`, `selected`, `header: true`). `StatusIndicator` has built-in `Semantics`.
- **Disable vs hide unavailable controls — depends on surface type.** *Configuration surfaces* (Settings, session-edit forms, preference dialogs) → render disabled with tooltip + tap-toast explaining the reason; user is exploring what the app can do. *Action surfaces* (lock screen, context menus, per-row action buttons, action dialogs) → hide; a greyed button is noise. Disabled state must visibly affect the whole row (opacity on full container).

### Localization (i18n)

All user-facing strings MUST use `S.of(context).xxx`. Never hardcode in widgets — treat as a bug. Add keys to `lib/l10n/app_en.arb`, run `flutter gen-l10n`. Exceptions: constructor defaults (no context), log messages, `_AlreadyRunningApp`. Tests must include `localizationsDelegates: S.localizationsDelegates, supportedLocales: S.supportedLocales` in every `MaterialApp`. See §8.1.

**Tone — native IT register, not dictionary calques.** Audience is engineers and sysadmins; strings should read like a dev to a colleague, not a textbook. Per-locale dominant pattern for tech terms:

| Locales | Pattern |
|---|---|
| RU, ES, PT-BR, FR, DE, IT | Latin for dev-tool tech (SSH, Keychain, Hardware, Log, Timeout, Worker, Fingerprint, Passphrase, Scrollback, rate limit). Apple/MS consumer-UI natives only for OS-specific labels |
| TR, ID | Heavy English in dev context. TDK / KBBI / öztürkçe calques read textbook |
| AR, FA, HI, VI | Latin tech terms inside native prose is normal; native coinages for SSH/TPM/keychain/forensics/wrapping sound amateur |
| JA | Katakana (キーチェーン, ハードウェア) for loan words; Latin (SSH, TPM, DMA, CVE, Argon2id) for acronyms |
| KO | Hangul transliteration (키체인, 하드웨어) or Latin — both valid; match native dev doc convention |
| ZH | Latin for protocols/acronyms always; common words translate (硬件, 密码); Apple 钥匙串 OK but `keychain` Latin also works |

**Never:** coin a native word for "keychain" when devs don't (RU ключница, VI chuỗi khóa, FA کلیدستان, KO 열쇠고리, ZH 钥匙链); translate Unix "pipe" as water pipe (RU труба, PT Pipa, TR Boru, AR أنبوب); translate "worker" as human laborer (PT Trabalhadores, AR العمال, TR İşçi); translate "forensics" as legal/courtroom (RU криминалистика, PT Perícia — use "memory dump"); translate SSH "fingerprint" with biometric word (collides with biometric-unlock UI); use "please" in error messages (RU пожалуйста, ES Por favor, JA ください, TR lütfen — drop all); mix dialects (PT BR vs PT PT; ES tuteo vs ustedeo; DE du vs Sie) — pick one per file; use different translations for the same English term in the same file.

**Critical semantic-inversion traps:**
- ES `restablecida` / PT `redefinida` for "connection reset by peer" → opposite meaning. Use `reiniciada por el peer` / `encerrada pelo peer`.
- KO `암호문` for "passphrase" → means `ciphertext`. Use `패스프레이즈`.
- JA `解錠` for "decrypt/unwrap" → physical lock-picking. Use `復号`.
- JA `ボルト` for "vault" → bolt/volt. Use `ボールト`.
- HI `समझौता` for "compromise" → agreement/deal. Use `कॉम्प्रोमाइज़`.
- FR `sauvegardé` for "backed by" → false friend. Use `adossé à`.

**Watchlist — keep English / native IT form unless the locale's dev community uses a native equivalent:** SSH, SFTP, SCP, TLS, DNS, proxy, TCP, known_hosts, TPM, TEE, DMA, Secure Enclave, StrongBox, HSM, keychain, keyring, Keystore, Credential Manager, key material, wrapped key, sealed blob, KDF, PBKDF2, Argon2id, AES, HMAC, AEAD, passphrase, fingerprint, host, host key, port, login, log, worker, scrollback, release, timeout, keep-alive, rate limit, backdoor, plaintext, snapshot, forensics, dump, probe, breaking change, driver, distro, config, credential, slot, vault, kernel, build, runtime, mitigation, lockout, idle.

Self-test: read aloud. Sounds like a textbook → rewrite. Sounds like a Slack message to a colleague → ship. **Do localization yourself** — don't delegate translation to sub-agents (they fall back to safe dictionary calques). Survey use (read 1000-line file, flag candidates) is fine; tone decisions stay in the main thread.

### Diagrams in Docs — Mermaid, Not ASCII Box-Art

Every diagram in `docs/**/*.md`, `README.md`, `SECURITY.md` and any tracked markdown MUST be a ` ```mermaid ` fenced block (`flowchart`, `stateDiagram-v2`, `sequenceDiagram`, `classDiagram`). GitHub renders as SVG; ASCII `┌─┐`/`└─┘` breaks on narrow viewports. Convert in the same commit when editing existing ASCII.

Not covered: directory trees (keep plain fenced — Mermaid is worse for deep trees); pipe tables (GitHub renders as HTML); code blocks. Single-box info cards → plain markdown bullets. Don't add ASCII fallbacks via `<details>` — doubles the source and rots.

---

## Code Quality — SonarCloud

All code follows **Effective Dart** and passes `dart analyze` with zero issues. `make lint` must pass before every commit touching Dart or Rust. **Never suppress.** Write code that already obeys these on first draft:

- **S3776 — cognitive complexity ≤ 15.** Common fixes: extract conditional children into `_buildFoo(…)`; pull repeated computations into a local `final already = …;` before `return`; split `if (enable) { … } else { … }` into `_enableFoo()` / `_disableFoo()`; long `if (error is X)` chains → group by category, extract `_tryLocalizeFooError` returning `String?`; async chains with nested mounted/null guards → extract each phase into `Future<T?> _phaseFoo(…)`.
- **S3358 — no nested ternaries.** Rewrite as `if`/`else if`/`else` assigning to a local, or a `switch` expression. Subtle: `active ? Icon(asc ? up : down) : null` is already S3358 — extract to `_directionIcon(col)`.
- **S1854 — dead/unused values.** Don't `final x = ...;` then overwrite; use `late final x;` with `if`/`else` assignment.
- **S1192 — string literal duplicated ≥3 times.** → constant or l10n key.
- **S1481 / S1172 — unused locals / parameters.** Delete or prefix with `_`.
- **No `print()` / `debugPrint()`** — `AppLogger` always. Errors surfacing to UI go through `localizeError()`.
- **No generated file edits** — `*.g.dart`, `*.freezed.dart` excluded; change source.

**Shape before scanner.** Method body >~30 lines or three nested conditional blocks → split before committing. Widget `build()` over that should already have named `_buildFoo` helpers.

---

## Testing Methodology

**Everything that can be unit-tested without touching the OS or an external system must be unit-tested.** Allow-list for "no unit test": OS-specific capability (biometric prompt, OS keychain, native plugin MethodChannel, platform file pickers, single-instance lock, notification APIs, TPM / Secure Enclave / Windows Hello, Linux D-Bus services like `fprintd`) or integration with external system (real SSH/SFTP server, real QR camera, real update server). For exempt functions, the harness-testable **slice** still gets tests — isolate pure-Dart logic from the non-testable edge.

Target: 100% coverage (excluding OS-specific edges + integration tests). One test file per source file. Testable by design: extract pure logic, DI over hardcoded `ref.read()` — §14. If a function cannot be unit-tested and the reason is not on the allow-list, refactor.

- **Tests assert spec, not current output.** Before any `expect(...)`, state in one sentence what the function _should_ do — derived from feature intent. **Never** run, observe, paste — that's a pinning test that cements bugs. If correct behavior is unclear, stop and ask.
- **When test and code disagree, surface it — don't silently "fix" either side.** Three options: real bug, wrong spec, ambiguous requirement. Stop, report with input + spec + where derived + current output. Let the user decide.
- **Failing tests after a change: diagnose before editing the test.** Re-derive the test's intended contract; compare to what your change promised; if test still checks a contract you did NOT intend to break, the code is wrong; only when the test pins an internal detail you deliberately reshaped do you rewrite — and the new assertion expresses the **new** contract intent-first.
- **Uncovered lines are a marker, not a target.** Don't write tests whose only goal is to execute the line (`isNotNull` / `isA<T>()` / "doesn't throw"). Ask: what branch / decision / contract does this line encode?
- **Fuzz tests for every untrusted-input consumer** — not only parsers. Tiers: user-supplied files (import, wizard text, clipboard); network / peer-supplied (SSH banner, SFTP path strings, terminal ANSI); inter-process (deep-link URIs, QR payload, OS clipboard, IPC); on-disk state (config JSON, KDF params, LFS archive header, vault blobs). Each target gets a Dart property-based test in `test/fuzz/` or standalone harness in `fuzz/` + seed corpus + CFL wiring in `.clusterfuzzlite/build.sh`. New untrusted-input code = new fuzz target same commit. See § Fuzz testing.
- **UI changes = test updates** — proactively update all tests referencing changed widget names, labels, finders.

---

## Commits & Versioning

- **HARD STOP between fixes.** Implement → tests → docs → **post-fix summary** → ask to commit. Don't start the next fix until current is committed. Exceptions: batch-mode signal; series of related doc/rule edits in a single session — batch into one commit at natural arc end.
- **Post-fix summary is mandatory.** Per bug: **Symptom** (user-visible behaviour that was wrong), **Root cause** (why, named with file/function/field), **Fix** (what you changed). One bug per paragraph, ≤5 lines. Batch mode → single combined report at arc end. The user reads the summary to decide whether you understood the bug — don't skip because the diff "speaks for itself".
- Format per CONTRIBUTING.md → Commit messages. Drives auto-changelog — keep user-readable. Use `type(scope):` with parenthesized scope for module-specific commits (`refactor(import): ...`, `test(known-hosts): ...`); drop scope only when genuinely cross-cutting.
- **Version bumps are automatic.** `/pr` skill runs `scripts/bump-version.sh` — parses conventional commits since last tag, bumps `pubspec.yaml` (patch for fix/refactor/perf/build/deps, minor for feat, major for BREAKING CHANGE; chore/docs/test/ci/Revert = no bump). Don't bump manually.
- **Green CI before merging to main** — pre-commit hook runs `make check` automatically.

---

## Branching & Release Flow

Default working branch is `dev` — never push directly to `main`.

| Scenario | Action |
|---|---|
| App change (feat/fix/refactor) | bump on dev → PR `dev` → `main` → CI → auto-tag → release |
| Tests/docs/CI only | Merge to `main` — no bump, no tag, no release |
| Dependabot deps | Auto: PR to main → bump in branch → merge → CI → auto-tag → release |
| Manual build | `gh workflow run build-release.yml` — fails if CI hasn't passed |
| Re-trigger failed build | `gh workflow run build-release.yml --ref v{VERSION}` |
