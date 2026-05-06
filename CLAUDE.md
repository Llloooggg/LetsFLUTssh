# LetsFLUTssh — Development Guide

LetsFLUTssh — lightweight cross-platform SSH/SFTP client (Dart/Flutter, all 5 desktops + mobile). Open-source alt to Xshell/Termius. **Solo developer project.**

## Documentation Map

- **[`docs/AGENT_RULES.md`](docs/AGENT_RULES.md)** — all rules, conventions, doc-maintenance checklist, code-quality, testing methodology, commit/release flow. Read on demand via the navigation tables below — never cover-to-cover.
- **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** — module structure, APIs, data flows, design decisions. 3000+ lines — never read cover-to-cover, jump to specific § via [AGENT_RULES nav](docs/AGENT_RULES.md#within-architecturemd).
- **[`docs/USER_GUIDE.md`](docs/USER_GUIDE.md)** — end-user reference for every shipped feature with step-by-step usage and worked examples. Update whenever a user-visible flow / toggle / surface changes.
- **[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md)** — build instructions, code style (for humans).

---

## Action → Read This (mandatory before acting)

| I'm about to... | MUST read first |
|---|---|
| Plan or edit code in any module (before drafting the plan or opening the file) | [AGENT_RULES § Docs First](docs/AGENT_RULES.md#docs-first--read-before-fix-drift-update-after) — pick the mapped § from the TOC, fetch only it (Read with offset+limit or `/doc` skill); never read `ARCHITECTURE.md` cover-to-cover; fix code-doc drift in the same commit |
| Write/edit any Dart code | [AGENT_RULES § Code Quality — SonarCloud](docs/AGENT_RULES.md#code-quality--sonarcloud) + [§ Conventions](docs/AGENT_RULES.md#conventions) + [§ Logging](docs/AGENT_RULES.md#logging--applogger-auto-sanitized-err-on-more-not-less) |
| Add a log line / notice missing logs around a state transition | [AGENT_RULES § Logging](docs/AGENT_RULES.md#logging--applogger-auto-sanitized-err-on-more-not-less) — always `AppLogger.instance.log`, never `print`/`dart:developer`; sanitizer auto-redacts PEM/IP/user@host/host:port/home paths; for free-form labels (session names, key labels, tag titles) log the marker `<label>` not the value |
| Call API of an external package (dartssh2, drift, riverpod, xterm, …) | [AGENT_RULES § External Libraries & APIs](docs/AGENT_RULES.md#external-libraries--apis--look-up-dont-guess) — never guess signatures: grep repo → Context7 → web docs → pub-cache source |
| Add a new dependency or feature needing an OS capability | [AGENT_RULES § Self-Contained Binary](docs/AGENT_RULES.md#self-contained-binary--end-user-installs-nothing) — bundle > fallback > optional-with-docs (rung 3 permits opt-in end-user install) |
| Choosing between pure-Dart (FFI / pub.dev pkg) and a native plugin (Kotlin / Swift / C / Rust) for an authorized feature | [AGENT_RULES § Native Over Dart When Better](docs/AGENT_RULES.md#native-over-dart-when-better-and-zero-install) — prefer native when it is measurably better on perf / functionality / integration depth **and** zero-install holds. If native would require an opt-in install, ask the user first |
| About to propose a per-platform native rewrite of a working feature | [AGENT_RULES § Don't Escalate Working Baselines](docs/AGENT_RULES.md#dont-escalate-working-baselines) — **first check: has the user already authorized this upgrade (plan, backlog, earlier message)? If yes, just execute.** The rule blocks UNSOLICITED escalations, not user-requested work |
| Write/update a test | [AGENT_RULES § Testing Methodology](docs/AGENT_RULES.md#testing-methodology) + [ARCHITECTURE §14](docs/ARCHITECTURE.md#14-testing-patterns--di-hooks) — everything that doesn't need the OS or an external system must be unit-tested; refactor around the edges rather than skip |
| Add/change a user-facing string | [AGENT_RULES § Conventions → Localization](docs/AGENT_RULES.md#localization-i18n) + [§ Localization Tone](docs/AGENT_RULES.md#localization-tone--native-it-register-not-dictionary-calques) — **all 15 `app_*.arb` files** must be updated; write native IT register per locale, no textbook calques, unify terminology within each file |
| Add a new widget / helper / mixin / style constant / store | [AGENT_RULES § Reuse First](docs/AGENT_RULES.md#reuse-first-project-wide-not-just-ui) — grep shared modules before creating |
| Add/change a UI control | [AGENT_RULES § Reuse First](docs/AGENT_RULES.md#reuse-first-project-wide-not-just-ui) + [§ UI Components](docs/AGENT_RULES.md#ui-components) (disable-vs-hide) |
| Touch theme / fonts / radii / heights | [AGENT_RULES § Theme & UI Constants](docs/AGENT_RULES.md#theme--ui-constants) — never hardcode |
| Add a new file/class/widget/provider in `lib/` | [AGENT_RULES § Doc Maintenance](docs/AGENT_RULES.md#documentation-maintenance-checklist) — find the row, update the named ARCHITECTURE § |
| Ship a user-visible feature / change a flow / add a toggle / move a control | [AGENT_RULES § Doc Maintenance](docs/AGENT_RULES.md#documentation-maintenance-checklist) → "User-visible change" + "New end-user feature" rows. Update [`USER_GUIDE.md`](docs/USER_GUIDE.md): walk-through steps, at least one worked example, platform notes in §17 mobile-differences table. Brand-new feature → add a top-level § linked from the TOC |
| Change the wire format of a persisted file (`config.json`, `credentials.kdf`, hardware-vault blobs, `.lfs` archive contents) **or** add a new envelope artefact | [ARCHITECTURE §3.6 → Migration framework → Developer guide](docs/ARCHITECTURE.md#developer-guide--how-to-ship-a-format-change) — bump `SchemaVersions`, ship a `Migration`, register it in `buildAppMigrationRegistry()` (or `archiveMigrationRegistry`), test the chain. **Drift intra-DB schema changes** (add/rename column, new table) follow the separate drift `MigrationStrategy` flow in [§11 Persistence](docs/ARCHITECTURE.md#11-persistence--storage) |
| Add/edit a diagram in `docs/*.md` / `README.md` / `SECURITY.md` | [AGENT_RULES § Diagrams in Docs](docs/AGENT_RULES.md#diagrams-in-docs--mermaid-not-ascii-box-art) — Mermaid only, no ASCII box-art |
| Write a commit message | [AGENT_RULES § Commits & Versioning](docs/AGENT_RULES.md#commits--versioning) + [§ Plan-Item IDs Stay Internal](docs/AGENT_RULES.md#plan-item-ids-stay-internal) |
| Open a PR / merge to main | [AGENT_RULES § Branching & Release Flow](docs/AGENT_RULES.md#branching--release-flow) |
| Find something in ARCHITECTURE.md | [AGENT_RULES § Quick Navigation → Within ARCHITECTURE.md](docs/AGENT_RULES.md#within-architecturemd) |
| Edit anything under `rust/` (security/transport core) | [ARCHITECTURE §3.14](docs/ARCHITECTURE.md#314-rust-securitytransport-core-rust) — workspace layout (`lfs_core` + `lfs_os_security` + `lfs_frb`), FRB boundary, dependency invariant. **`lfs_core` MUST NOT depend on `flutter_rust_bridge` / `tauri` / any frontend crate**; **`lfs_os_security` is the single audit perimeter for OS-API FFI** (one-way edge below `lfs_core`). Run `make rust-fmt rust-lint rust-test`; if you edited `rust/crates/lfs_frb/src/api/*.rs`, also `make rust-codegen` and stage the regenerated `lib/src/rust/` |
| Add or modify code on the cold-start path (`main.dart` `_mainBody`, `_LetsFLUTsshAppState.initState`, `_MainScreenState.initState`, `loadAppConfigFromDisk`, `AppConfig.fromJson` / `SecurityCapabilities.fromJson`, anything reachable from the first runApp pass) | [ARCHITECTURE § Cold-start ordering](docs/ARCHITECTURE.md#cold-start-ordering--pre-init--post-init-invariant). **STRICT INVARIANT: nothing on the cold-start path may import `lib/src/rust/...` or call FRB.** The first runApp pass is pure Dart so the splash paints during the ~3 s native blob load on Win IoT. FRB-touching listeners + setup wire from `_LetsFLUTsshAppState._wireFrbDependentBootstrapListeners` (or directly in `_bootstrap`) AFTER `_initRustCoreOrFatal` returns. Past violations caused multi-minute hangs in the unlock cascade and silent config overwrites; the fix replaced every defensive `RustLib.instance.initialized` guard with this single ordering rule |

---

## Always-On Rules (gate every action)

These apply to every response without re-reading:

- **Don't commit or push unless the user explicitly asks.** "commit" = commit only, "commit and push" = commit + push.
- **HARD STOP between fixes** — implement → tests → docs → post-fix summary → ask to commit. Batch-mode signals from the user override (one combined summary at the arc's end). Full rule: [AGENT_RULES § Commits & Versioning](docs/AGENT_RULES.md#commits--versioning).
- **Default branch is `dev`.** Never push to `main` directly.
- **All files in English only** — code, comments, commits, docs.
- **No plan-item IDs in public artifacts** — no `P1.2-*` / `Phase E1` / `Task 3.2` in commits, code, filenames, or any tracked doc. Full rule: [AGENT_RULES § Plan-Item IDs Stay Internal](docs/AGENT_RULES.md#plan-item-ids-stay-internal).
- **Never suppress issues** — no `// ignore:`, `// NOSONAR`, `@SuppressWarnings`. Fix root cause.
- **Comments stay short and reflect current state** — one line max, no retrospective (`originally...`, `previously...`, `replaces the legacy...`). Git log holds history; comments hold the present invariant. Long rationale → ARCHITECTURE.md + a one-line link comment. Full rule: [AGENT_RULES § Comments](docs/AGENT_RULES.md#comments--short-and-current).
- **Never amend after push** — new commits only. Amend OK only before first push.
- **Don't install packages without asking.** Latest stable only — no beta/dev/pre-release.
- **End-user install is opt-in, never forced** — core app launches with zero manual setup; platform-only extras are allowed only via the 3-rung ladder (bundle > fallback > optional-with-disabled-toggle + README snippet). Full rule: [AGENT_RULES § Self-Contained Binary](docs/AGENT_RULES.md#self-contained-binary--end-user-installs-nothing).
- **Always build via Makefile** — `make run/build-linux/test/analyze`. Never call `flutter` directly.
- **Skip `make analyze` / `make test` for doc-only commits** — if the staged diff touches no `.dart` files and no `pubspec.yaml`, don't run analyzer or tests manually. The pre-commit hook runs `make check` automatically; running it first on a Markdown-only change is wasted loop time.
- **Cross-platform verification** — Android change → also iOS; Windows change → also Linux + macOS.
- **Best practices by default** — push back on hacky solutions, propose best-practice alternatives.
- **Three pillars: ideal code, security, optimality.** Migration / refactor work goes end-to-end. **The user QAs every release on real hardware** — "I can't test this on my machine right now" is *not* a skip reason; write the code, document the on-device validation matrix, the user's release process catches what a Linux WSL session can't. The only legitimate skip is "the replacement primitive does not exist" (e.g. drift is Dart-only, no Rust analogue). Full rule: [AGENT_RULES § Three Pillars](docs/AGENT_RULES.md#three-pillars--ideal-code-security-optimality).
- **Think systemically** — consider full scope and side effects, not just the literal instruction.
- **Ask before guessing UI placement** — if ambiguous, ask once upfront.
- **Every change ships with docs + tests + translations** — incomplete commit otherwise.
- **Docs first — the highest-priority discipline, binds planning and editing both.** Every § covers both *how* (mechanism) and *why* (rationale). TOC → specific § via `Read offset+limit` or the `/doc` skill — never read `ARCHITECTURE.md` cover-to-cover. Drift / gaps fixed in the same commit. Cross-links every related §. Human-audience docs (`ARCHITECTURE.md`, `README.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`) never carry LLM asides; agent guidance stays in `CLAUDE.md` / `AGENT_RULES.md` / `~/.claude/...`. Full rule: [AGENT_RULES § Docs First](docs/AGENT_RULES.md#docs-first--read-before-fix-drift-update-after).
- **Parallel agents** — only `git add` files YOU changed. Do NOT run tests — testing is the main process's job.
- **Save plans / audits / multi-axis findings to `.claude/plans/`** — every structured artefact the user may want to revisit (audit reports, migration backlogs, multi-agent findings dumps) goes into `.claude/plans/<topic>-<YYYY-MM-DD>.md` (gitignored) and is paired with a TaskList. Never hold large analyses only in chat. `docs/` is human-audience and forbids LLM asides; memory is for cross-session preferences, not project-state snapshots.
