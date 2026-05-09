# LetsFLUTssh — Development Guide

LetsFLUTssh — lightweight cross-platform SSH/SFTP client (Dart/Flutter, all 5 desktops + mobile). Open-source alt to Xshell/Termius. **Solo developer project.**

This file is the single source of truth for agent rules.

## Documentation Map

- **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** — module structure, APIs, data flows, design decisions. 3000+ lines — never read cover-to-cover; jump to specific § via the ARCHITECTURE Quick Navigation below.
- **[`docs/USER_GUIDE.md`](docs/USER_GUIDE.md)** — end-user reference for every shipped feature with step-by-step usage and worked examples. Update whenever a user-visible flow / toggle / surface changes.
- **[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md)** — build instructions, code style for humans.

---

## Action → Read This (mandatory before acting)

| I'm about to... | MUST read first |
|---|---|
| Plan or edit code in any module | § Docs First — pick the mapped § from ARCHITECTURE Quick Navigation, fetch only it (Read with offset+limit or `/doc` skill); fix code-doc drift in the same commit |
| Write/edit any Dart code | § Code Quality — SonarCloud + § Conventions + § Logging |
| Add a log line / notice missing logs | § Logging — always `AppLogger.instance.log`, never `print`/`dart:developer`; sanitizer auto-redacts PEM/IP/user@host/host:port/home paths; for free-form labels (session names, key labels, tag titles) log marker `<label>` not value |
| Call API of an external package | § External Libraries & APIs — never guess: grep repo → Context7 → web docs → pub-cache source |
| Add a new dependency or feature needing OS capability | § Self-Contained Binary — bundle > fallback > optional-with-docs |
| Choose pure-Dart vs native plugin for an authorized feature | § Native Over Dart When Better — prefer native when measurably better AND zero-install holds |
| Propose unsolicited per-platform native rewrite of a working feature | § Don't Escalate Working Baselines — first check if user already authorized; rule blocks UNSOLICITED only |
| Write/update a test | § Testing Methodology + [ARCHITECTURE §14](docs/ARCHITECTURE.md#14-testing-patterns--di-hooks) |
| Add/change a user-facing string | § Localization + § Localization Tone — all 15 `app_*.arb` files |
| Add a new widget / helper / mixin / style constant / store | § Reuse First |
| Add/change a UI control | § Reuse First + § UI Components |
| Touch theme / fonts / radii / heights | § Theme & UI Constants |
| Add a new file/class/widget/provider in `lib/` | § Documentation Maintenance Checklist |
| Ship user-visible feature / change a flow / add a toggle | § Doc Maintenance → "User-visible change" + "New end-user feature" rows; update `USER_GUIDE.md` |
| Change wire format of a persisted file (`config.json`, `credentials.kdf`, hardware-vault blobs, `.lfs` archive) **or** add new envelope artefact | [ARCHITECTURE §3.6 → Migration framework → Developer guide](docs/ARCHITECTURE.md#developer-guide--how-to-ship-a-format-change) — bump `SchemaVersions`, ship a `Migration`, register in `lfs_core::migration::registry::build_app_registry`, test the chain. Archive (`.lfs`) future-version handling is not a registry — `read_archive_to_pending` rejects newer-version archives. Drift intra-DB schema changes follow [§11 Persistence](docs/ARCHITECTURE.md#11-persistence--storage) |
| Add/edit a diagram in any markdown | § Diagrams in Docs — Mermaid only |
| Write a commit message | § Commits & Versioning + § Plan-Item IDs Stay Internal |
| Open a PR / merge to main | § Branching & Release Flow |
| Edit anything under `rust/` | [ARCHITECTURE §3.14](docs/ARCHITECTURE.md#314-rust-securitytransport-core-rust) — workspace layout (`lfs_core` + `lfs_os_security` + `lfs_frb`). **`lfs_core` MUST NOT depend on `flutter_rust_bridge` / `tauri` / any frontend crate**; **`lfs_os_security` is the single audit perimeter for OS-API FFI**. Run `make rust-fmt rust-lint rust-test`; if you edited `rust/crates/lfs_frb/src/api/*.rs`, also `make rust-codegen` and stage the regenerated `lib/src/rust/` |
| Add or modify code on the cold-start path (`main.dart` `_mainBody`, `_LetsFLUTsshAppState.initState`, `_MainScreenState.initState`, `loadAppConfigFromDisk`, `AppConfig.fromJson` / `SecurityCapabilities.fromJson`) | [ARCHITECTURE § Cold-start ordering](docs/ARCHITECTURE.md#cold-start-ordering--pre-init--post-init-invariant). **STRICT INVARIANT: nothing on the cold-start path may import `lib/src/rust/...` or call FRB.** Pre-FRB FRB calls throw `StateError("flutter_rust_bridge has not been initialized")`. FRB-touching listeners + setup wire from `_LetsFLUTsshAppState._wireFrbDependentBootstrapListeners` AFTER `_initRustCoreOrFatal` returns |

### ARCHITECTURE Quick Navigation

| I need to... | Read this section |
|---|---|
| Understand the module layout | [§2 Module Map](docs/ARCHITECTURE.md#2-module-map) |
| Work with SSH connections | [§3.1 SSH](docs/ARCHITECTURE.md#31-ssh-coressh) + [§9.1 SSH Flow](docs/ARCHITECTURE.md#91-ssh-connection-flow) |
| Work with SFTP / file browser | [§3.2 SFTP](docs/ARCHITECTURE.md#32-sftp-coresftp) + [§5.2 File Browser](docs/ARCHITECTURE.md#52-file-browser-featuresfile_browser) |
| Work with transfers | [§3.3 Transfer Queue](docs/ARCHITECTURE.md#33-transfer-queue-coretransfer) + [§9.4 Transfer Flow](docs/ARCHITECTURE.md#94-file-transfer-flow) |
| Work with sessions | [§3.4 Sessions](docs/ARCHITECTURE.md#34-session-management-coresession) + [§9.3 CRUD Flow](docs/ARCHITECTURE.md#93-session-crud-flow) |
| Work with connections | [§3.5 Connection Lifecycle](docs/ARCHITECTURE.md#35-connection-lifecycle-coreconnection) |
| Work with encryption / security | [§3.6 Security](docs/ARCHITECTURE.md#36-security--encryption-coresecurity) + [§13 Security Model](docs/ARCHITECTURE.md#13-security-model) |
| Work with config | [§3.7 Configuration](docs/ARCHITECTURE.md#37-configuration-coreconfig) |
| Work with terminal / tiling | [§5.1 Terminal](docs/ARCHITECTURE.md#51-terminal-with-tiling-featuresterminal) |
| Work with tabs / workspace tiling | [§5.4 Tab & Workspace System](docs/ARCHITECTURE.md#54-tab--workspace-system) |
| Work with mobile features | [§5.6 Mobile](docs/ARCHITECTURE.md#56-mobile-featuresmobile) + [§12 Platform-Specific](docs/ARCHITECTURE.md#12-platform-specific-behavior) |
| Use or create widgets | [§6 Widgets API](docs/ARCHITECTURE.md#6-widgets--public-api-reference) |
| Use utilities | [§7 Utilities API](docs/ARCHITECTURE.md#7-utilities--public-api-reference) |
| Work with theme / colors | [§8 Theme System](docs/ARCHITECTURE.md#8-theme-system) |
| Add/change user-facing strings | [§8.1 i18n](docs/ARCHITECTURE.md#81-internationalization-i18n) |
| Understand Riverpod providers | [§4 State Management](docs/ARCHITECTURE.md#4-state-management--riverpod) |
| Understand persistence (rusqlite + SQLCipher under FRB DAO surface) | [§11 Persistence](docs/ARCHITECTURE.md#11-persistence--storage) |
| Check data models | [§10 Data Models](docs/ARCHITECTURE.md#10-data-models) |
| Understand CI/CD | [§15 CI/CD Pipeline](docs/ARCHITECTURE.md#15-cicd-pipeline) |
| Check design decisions / gotchas | [§16 Design Decisions](docs/ARCHITECTURE.md#16-design-decisions--rationale) |
| Check dependencies / versions | [§17 Dependencies](docs/ARCHITECTURE.md#17-dependencies) |
| Write tests / understand DI | [§14 Testing Patterns](docs/ARCHITECTURE.md#14-testing-patterns--di-hooks) |

---

## Always-On Rules (gate every action)

These apply to every response without re-reading:

- **Don't commit or push unless the user explicitly asks.** "commit" = commit only, "commit and push" = commit + push.
- **HARD STOP between fixes** — implement → tests → docs → post-fix summary → ask to commit. Batch-mode signals override (one combined summary at the arc's end). See § Commits & Versioning.
- **Default branch is `dev`.** Never push to `main` directly.
- **All files in English only** — code, comments, commits, docs.
- **No plan-item IDs in public artifacts** — see § Plan-Item IDs Stay Internal. ARCHITECTURE.md `§N.M` cross-refs are stable doc anchors, not plan IDs — fine to use.
- **Never suppress issues** — no `// ignore:`, `// NOSONAR`, `@SuppressWarnings`. Fix root cause.
- **Comments stay short, current, no fabricated rationale** — one line max, no retrospective. See § Comments.
- **No fabrication anywhere — verify with `git log` / grep / measurement, or don't write the value.** Binds code, docs, tests, migrations, seed data, version strings, default config, performance numbers, "historical" labels, error messages. **When asked to remove fabricated content, remove it cleanly — never replace with new speculation.**
- **Authorization boundaries — never destroy or overwrite tracked state without explicit permission.** Covers: deleting files in `.claude/plans/` / `CHANGELOG.md` / source / docs / tests; dropping DB schemas or tables; force-overwriting uncommitted work; reverting / resetting commits; mass-renaming or reformatting outside the asked diff. **When asked to remove X, remove exactly X** — no slipped-in additions (CHANGELOG entries, "improved" wording, adjacent refactors, extra commits). Surface destructive steps once and wait.
- **Never amend after push** — new commits only. Amend OK only before first push.
- **Don't install packages without asking.** Latest stable only — no beta/dev/pre-release.
- **End-user install is opt-in, never forced** — see § Self-Contained Binary.
- **Always build via Makefile** — `make run/build-linux/test/analyze`. Never call `flutter` directly.
- **Skip `make analyze` / `make test` for doc-only commits** — if the staged diff has no `.dart` / `pubspec.yaml`, skip; pre-commit hook runs `make check` automatically.
- **Cross-platform verification** — Android change → also iOS; Windows → also Linux + macOS.
- **Best practices by default** — push back on hacky solutions. Cost is not a selection criterion: complementary defences = union (defence-in-depth), not pick-cheapest. Don't rank by "cheap/medium/heavy". See § Three Pillars.
- **Three pillars: ideal code, security, optimality.** Migration / refactor goes end-to-end. The user QAs every release on real hardware — "I can't test this on my machine" is NOT a skip reason. Only legitimate skip: "the replacement primitive does not exist".
- **Think systemically** — full scope and side effects, not just literal instruction.
- **Don't cargo-cult "scope discipline" into session-level stopping. Don't leave the arc half-done. Don't defer work.** When user signals batch mode ("do all", "finish it", "go end-to-end", any equivalent in any language) or hands a multi-item plan — execute the queue. Three pillars bind: cost / "tests need rewrite" are not skip reasons. **Anti-patterns:** (a) exit ramps between every step; (b) declaring sweep "subjective" without trying; (c) conflating "WSL can't test platform X" with "no point writing code"; (d) `TODO` / `FIXME` / `XXX` markers as deferrals; (e) ranking alternatives by cost. Don't write yourself a `.claude/plans/` punch list as a substitute for doing the work — those are for arcs the user has explicitly authorised. Keep going until queue empty, real blocker hits, or user stops you.
- **"Full" / "line-by-line" / "every item" reviews mean exactly that — never silently truncate on token budget.** Finish the queue or explicitly ask to chunk. Stopping mid-stream with partial findings is failure. **Status reports must match reality** — never call work "done" while items quietly deferred; name what's left.
- **One logical commit per arc, not a split, unless user asks otherwise.** Don't slice "code" + "test" + "doc" into three messages. Commit prose stays clean: no plan-IDs, no AI-tell phrasing ("I implemented…", "Let me know if you'd like…"), no auto-CHANGELOG entries the user didn't request.
- **Terse output by default.** No preambles ("I'll help you…", "Let me start by…"), no recap-of-what-I-just-did paragraphs after every tool call, no QA / validation matrices, no excessive bold / headers / nested numbered lists. Match shape to the question.
- **Ask before guessing UI placement** — if ambiguous, ask once upfront.
- **Every change ships with docs + tests + translations** — incomplete commit otherwise.
- **Docs first — highest-priority discipline, binds planning and editing both.** Every § covers *how* + *why*. TOC → specific § via offset+limit or `/doc` skill — never read ARCHITECTURE.md cover-to-cover. Drift fixed in same commit. Cross-link related §s. Human-audience docs (ARCHITECTURE/README/SECURITY/CONTRIBUTING/CHANGELOG/USER_GUIDE/FEATURE_BACKLOG/ADDING_A_FEATURE) never carry LLM asides; agent guidance stays in this file. **References are one-directional: this file may link to human docs (factual / architectural reference), but human docs and source-code comments must NOT link back to this file or any other agent-instruction file** — `.claude/skills/*/SKILL.md` are agent files and may reference this one freely. When a passage in a human doc wants to cite a rule, inline the substance instead — humans reading project docs should never be sent to read agent rules.
- **Parallel agents** — only `git add` files YOU changed. Do NOT run tests — testing is the main process's job.
- **Save plans / audits / multi-axis findings to `.claude/plans/`** — every structured artefact (audit reports, migration backlogs, agent findings) goes into `.claude/plans/<topic>-<YYYY-MM-DD>.md` (gitignored), paired with a TaskList. Never hold large analyses only in chat. `docs/` is human-audience and forbids LLM asides; memory is for cross-session preferences, not project-state snapshots.
- **Plans are engineering punch-lists — no QA inside them.** `.claude/plans/*.md` describes implementation steps. Do NOT write "manual test plan" / "validation matrix" / per-platform QA bullets. User owns QA scope.

---

## Docs First — Read Before, Fix Drift, Update After

**The single most important discipline.** Code is temporary; docs are how intent survives across refactors and contributor handovers. Treat `ARCHITECTURE.md` as a first-class deliverable. Every task — planning, editing, bug-fixing, refactor, review — is also a docs task.

**Audience — write for humans, always.** `ARCHITECTURE.md`, `README.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md` and every other git-tracked doc that is not explicitly an agent-instruction file are written **for humans**. No LLM-specific asides ("agents should note...", "for LLM context..."). Agent-specific guidance stays in this file. The split is absolute.

**Every § covers both *how* (mechanism — states, inputs, outputs, invariants, failure modes) and *why* (rationale — constraint, past incident, rejected alternative, trade-off accepted).** A § answering only "how" leaves intent guessable; only "why" leaves mechanism re-derivable.

**Eight-step discipline for any work touching a documented module:**

1. **TOC → specific §, never cover-to-cover.** Use ARCHITECTURE Quick Navigation above, the TOC at the top of `docs/ARCHITECTURE.md`, or the `/doc` skill (which grep-locates the heading and Reads only that slice). Read with `offset`+`limit`. Cross-links widen the read = another narrow fetch, not a full Read. This applies at planning stage too — a plan written from grep-only knowledge of the code misses intent.
2. **If the § doesn't cover your question, or covers it ambiguously: read the code, then fill the gap in the § in the same commit.** ARCHITECTURE.md is comprehensive but not exhaustive. Resolve ambiguity, write the answer back. Don't leave the next agent to re-derive.
3. **If you find code-doc drift at any stage, fix the doc in the same commit.** Code is the source of truth on current behaviour. Don't extend a stale § with matching stale additions. If the code looks like it drifted away from the intended design, flag it and ask the user — don't silently paper over.
4. **After your edits, walk the Documentation Maintenance Checklist.** Update every named § the diff triggers, in the same commit.
5. **When writing/updating a §, cross-link related §s.** Docs are a graph. A §3.x class persisted via DAO → link to §11. A §5.x feature consuming a provider → link to §4. A §13 security claim depending on a module → link to the §3.x. Any rule in this file enforced by code in a specific module → link out to the ARCHITECTURE § that documents the enforcing code (and back). When the cross-link target doesn't exist yet, **extract it** — create the target § or lift the paragraph, then link.
6. **When you rename, move, merge, split, or delete a §, update every inbound link in the same commit.** Grep the repo for the old anchor (`rg -- 'old-anchor-slug'`). Sweep `docs/ARCHITECTURE.md` TOC, `README.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, code docstrings, this file. **When in doubt, link to file not anchor** — `[X](docs/ARCHITECTURE.md)` is more rename-resilient than `[X](docs/ARCHITECTURE.md#x)`. Use anchored links only when the anchor is load-bearing (nav tables, checklists).
7. **Extend the docs proactively.** If you notice non-trivial behaviour under-documented, important invariant only implicit in code, magic number without rationale, or a § missing "why" — write it up in the same commit. You don't need permission to extend docs; extending is the default, thinning requires justification. Quality bar: a new reader opening only the § answers both "what does this do?" and "why is it shaped this way?" without opening the code.
8. **Writing the § revealed the code is too complex/tangled? Consider rewriting the code.** Documenting is the most honest review the module gets. When prose tortures, the implementation tortures. Stop, ask the user about simplifying, rewrite first if agreed, update § to describe the cleaner shape. Signs the § is telling you the code needs rewriting: needs a flowchart for one method's control flow; two sub-sections describe "the same but for case Y"; a `why` paragraph cannot find a coherent constraint; you find unreachable / shadowed code; an invariant cannot be stated as a single sentence.

This rule binds every code edit AND every plan. "Forgot to check docs", "the docs didn't say", "the link broke because I renamed the target", "the code was ugly but technically worked" — all invalid skip reasons.

---

## Documentation Maintenance Checklist

**Every code change MUST be accompanied by documentation updates.** Violation = incomplete commit.

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
| Changed persistence schema (rusqlite SQL: add/rename column, new table, new index) | Update [§11 Persistence](docs/ARCHITECTURE.md#11-persistence--storage). Schema lives in `lfs_core::db::*` and is bootstrapped idempotently on open; structural changes need additive `ALTER TABLE` / `CREATE TABLE IF NOT EXISTS` in the bootstrap path so existing user DBs upgrade without a wipe |
| Changed wire format of persisted file (`config.json`, `credentials.kdf`, hardware-vault blob, `.lfs` archive) **or** added new envelope artefact | Update [§3.6 → Migration framework → Developer guide](docs/ARCHITECTURE.md#developer-guide--how-to-ship-a-format-change) — bump `SchemaVersions::<X>`, ship a `Migration`, register in `lfs_core::migration::registry::build_app_registry`, add chain test |
| Changed security model | Update [§13 Security Model](docs/ARCHITECTURE.md#13-security-model) + SECURITY.md |
| New design decision | Add to [§16 Design Decisions](docs/ARCHITECTURE.md#16-design-decisions--rationale) with rationale |
| New CI workflow / changed pipeline | Update [§15 CI/CD](docs/ARCHITECTURE.md#15-cicd-pipeline) |
| Platform-specific change | Update [§12 Platform-Specific](docs/ARCHITECTURE.md#12-platform-specific-behavior) |
| New DI hook for testing | Update [§14 Testing Patterns](docs/ARCHITECTURE.md#14-testing-patterns--di-hooks) |
| New/changed user-facing string | Add key to `lib/l10n/app_en.arb` **and translate into every other `app_*.arb` file** (15 total: ar, de, en, es, fa, fr, hi, id, ja, ko, pt, ru, tr, vi, zh). Run `flutter gen-l10n`. Use `S.of(context).key`. Missing keys silently fall back to English |
| New/changed shared component | Search `lib/widgets/` and `lib/core/**` for existing equivalent first; extend (add a param) instead of duplicating. Update [§6 Widgets API](docs/ARCHITECTURE.md#6-widgets--public-api-reference) |
| Touched any `rust/**/*.rs` | Update relevant ARCHITECTURE § (§3.1 SSH, §3.6 Security, §3.14 Rust core, etc.) in same commit. Run `make rust-fmt`, `make rust-lint`, `make rust-test`; if FRB API changed, also `make rust-codegen` and stage regenerated `lib/src/rust/` |
| Edited FRB API surface (`rust/crates/lfs_frb/src/api/*.rs`) | Run `make rust-codegen` and stage regenerated Dart bindings in same commit. `pubspec.yaml` (`flutter_rust_bridge:` runtime) and `rust/crates/lfs_frb/Cargo.toml` (`flutter_rust_bridge =` build dep) MUST match codegen CLI version exactly. `lfs_core` MUST NOT depend on `flutter_rust_bridge` directly |
| User-visible change | Update README.md **and** [`USER_GUIDE.md`](docs/USER_GUIDE.md). New flow / toggle / changed UX → update the relevant § with usage steps, examples, platform caveats |
| New end-user feature | Add a top-level § in [`USER_GUIDE.md`](docs/USER_GUIDE.md) linked from its TOC. Walk-through style: numbered steps, ≥1 worked example, platform differences in §17 mobile-differences table |
| Security scope change | Update SECURITY.md |

---

## Conventions

### Three Pillars — Ideal Code, Security, Optimality

The project's three locked priorities. Every migration / refactor / cleanup decision weighs against those three only. "More work" / "tests would need rewriting" / "the existing path works" / "cost > benefit" are NOT valid skip grounds. The bar to skip is one of:

1. **Moving it makes the system worse** — measurable safety / perf / consistency regression.
2. **The replacement cannot exist** — target language/framework lacks the primitive (Riverpod is Dart-only; `BuildContext` cannot live outside Flutter).
3. **The user explicitly authorized the skip** — for that specific item, captured in plan or commit history.

Inconvenience is not a skip reason. Rewrite from scratch when the ideal demands it; the user has authorised the spend.

**Cost is not a selection criterion either.**
- **Complementary defences = union, not pick-one.** Static lint + runtime fallback + observability for the same fault class are layered defence; best practice is all three. "Pick one to keep things simple" is a lower bar than this project asks for.
- **Presenting alternatives ranked by cost is an anti-pattern.** "option A (cheap) / B (medium) / C (heavy)" inverts the selection axis. Rank by best practice. Cost shows up only when telling the user how long the work will take.

**Anti-patterns to suppress:**
- (a) offering exit ramps ("session closed?", "wrap up?", "continue or stop?") between every step
- (b) pre-emptively declaring a sweep "subjective" / "needs your anchor" without trying
- (c) conflating "this WSL box can't test platform X" with "no point writing the code"
- (d) `TODO` / `FIXME` / `XXX` markers in code as deferrals
- (e) ranking alternatives by implementation cost

**When this rule binds:** any batch-mode signal — `до идеала`, `три кита`, `идеал кода`, `even from scratch`, `добиваем`, `Делаем`, or equivalent in any language. Once the signal lands, default to "go end-to-end, don't ask, emit one combined summary at the arc end."

**When it does NOT bind:** one-off bug fix or feature add that is not a migration / refactor / consolidation arc. Pillars apply to the general direction; they don't compel rewriting unrelated code that happens to be touched.

This rule overrides the standard "don't add features beyond what the task requires" guidance for migration / refactor work specifically. In pillars-mode, aggressive completionism is the right posture.

**Legitimate escape-hatch examples** ("moving it makes it worse"): single-instance gate moved to native shell (Linux GtkApplication D-Bus, Windows `CreateMutexW`, macOS `LSMultipleInstancesProhibited`) — Dart shapes ran after engine boot; native gates reject in ms before any Dart code runs. Cold-start handlers (`AppConfig.fromJson`, `SecurityCapabilities.fromJson`, every `*PromptListener.start()`) stay pure Dart, wired post-`_initRustCoreOrFatal`; pre-FRB FRB calls cause multi-minute hangs. The bar is "concrete regression we can point at", not "feels iffy"; reverts ship with measurements.

### Self-Contained Binary — End-User Installs Nothing

**The released app must run with zero manual setup beyond extracting / installing the bundle.** Never introduce a feature that hard-requires the end-user to install something on their OS first.

When a feature needs an OS capability, preference order:
1. **Bundle it** — link statically, vendor the lib, use system frameworks already present on every supported version (sqlite3 via build hooks, AVFoundation for iOS QR, AndroidX CameraX + ZXing for Android QR). Default; pick this unless impossible.
2. **Built-in fallback** — if the OS capability is genuinely platform-specific (OS keychain, biometric API), provide a feature that works without it (master password instead of keychain). User keeps a usable app.
3. **Optional OS dep with graceful degradation** — last resort. **⚠ This rung explicitly permits an end-user install step** (copy-pasteable README snippet) for the *optional extra*, provided the core app still works without it. Allowed only if all three hold:
   - The app detects the missing dep at runtime and shows a **short** localized message stating "X is unavailable on this platform" or "X is unavailable because Y is not installed" — one line, no stack trace, no install commands inside the UI.
   - The corresponding control on configuration surfaces is **disabled with tooltip carrying the same short reason** (per § UI Components → disable-vs-hide).
   - `README.md` "Installation" lists copy-pasteable install command per platform that needs it.

**Canonical example — Linux biometric unlock.** `fprintd` is a system D-Bus daemon that cannot be bundled (rung 1 fails). Master-password remains core (rung 2 satisfied). Rung 3 applies: Settings biometric toggle is disabled with `fprintd not installed` reason; README's Linux Installation has per-distro snippet.

Hard-requiring user installs **to launch the core app** is forbidden. Optional platform-only upgrades meeting the three conditions are not "hard-requiring" — they are the rung-3 escape hatch. When reviewing a diff with new dependency: check `pubspec.yaml`, then check whether dep pulls a transitive native requirement (look at dep's README + `linux/`, `macos/`, `windows/`, `android/`, `ios/` plugin folders).

### Fallbacks Are Last Resort, Not Default

A weaker code path is a **downgrade of the guarantee**, not a neutral alternative. Ladder when a feature's primary path is unavailable on a platform:

1. **Bundle** (per Self-Contained Binary above) — if the capability can ship inside the app, ship it.
2. **Implement per platform** — if a native implementation that meets the bar is achievable at reasonable cost-per-user-served, build it. Authorisation per § Don't Escalate Working Baselines.
3. **Honestly hide** — if the platform cannot meet the bar at any reasonable cost (no unified API, fragmented drivers — Linux biometric binding is canonical), render the control as **disabled with a reason**. A hidden-but-honest "Not available on Linux" row is **better** than a weaker path that looks strong.
4. **Weaker path with honest label** — acceptable only when (a) the ladder above has no better answer, (b) the weaker path delivers non-trivial value on its own, (c) UI states what the user got — labels like `Software-gated`, `DPAPI (software-backed)`, `Keyring (no biometric binding)`. **Never label a weaker path with the same words as the stronger one.**

Full rule: a fallback that ships without a visible downgrade label is forbidden, AND a fallback that ships instead of a feasible stronger path is forbidden — label or no label. "We can just label it" doesn't justify picking a weaker path when a better one is achievable.

### Native Over Dart When Better (and Zero-Install)

When a feature can be implemented in pure Dart (FFI, pub.dev wrapper) **or** as a native platform plugin (Kotlin / Swift / ObjC / C / Rust via MethodChannel/FFI), **prefer native when measurably better on at least one of:**

- **Performance** — runtime speed, startup latency, memory, battery, binary size.
- **Functionality** — native unlocks capabilities Dart cannot reach (Windows Hello `KeyCredentialManager`, Android `BiometricPrompt.CryptoObject`, iOS `SecAccessControl` flags).
- **Integration depth** — OS lifecycle / IPC / sandboxing hooks that Dart packages wrap thinly or not at all.

"Better" means a concrete user-facing benefit Dart cannot match at reasonable cost. **The decision must still satisfy § Self-Contained Binary at rung 1 or 2.** If native pushes into rung 3 (README install snippet), **stop and ask the user** — that trade-off is a user call. Record authorization before writing the native path.

Pure Dart / FFI / pub.dev is right when: parity with native is good enough for the use case (most settings UI, config, glue); native would add N per-platform codepaths without clear per-user win; iteration speed matters more than marginal runtime.

When the choice is live, write the "why native" or "why Dart" into the commit message or backlog entry.

**Interaction with § Don't Escalate:** that rule blocks *unsolicited* escalation from a working Dart baseline. This rule is about choosing the path for a feature the user has already authorised — once greenlit, native-when-better-and-zero-install is the default.

### Don't Escalate Working Baselines

The project ships across 5 platforms with **deliberately uneven guarantees** — credential storage, file pickers, notifications, biometrics. Cross-platform packages cover most users with documented limits on weaker platforms. This asymmetry is the **chosen baseline**, not a deficiency.

**Scope — read carefully:** This rule governs **unsolicited** agent proposals. It does NOT block work the user has already authorized. If the user has put a per-platform upgrade in the backlog, plan, earlier message, or "yes, do it" reply — that upgrade is **authorized** and the red-flag checks below don't apply. Just execute. The rule prevents inventing a 3-day native-plugin refactor in response to "fix the typo".

**Before invoking this rule, check:** *did the user ask for this per-platform upgrade, now or in a prior plan?* If yes — proceed.

For unsolicited proposals on working baselines:
1. **Don't escalate.** Existing solution covers most platforms with known limits — leave it alone.
2. **Document the gap, don't fill it with code.** Propose adding a row to the relevant per-platform table (`SECURITY.md`, ARCHITECTURE §12, §13). Don't open a refactor.
3. **Treat phrases "true X", "real X", "verified X", "proper X" as red flags** when *you* feel tempted to use them to re-pitch a working feature. They translate to "more code, more rope". Ask first.

This is a **caveat on** § Self-Contained Binary: that section's preference order applies to **new** features, not a mandate to retroactively replace working optional-dep solutions.

### External Libraries & APIs — Look Up, Don't Guess

**Never invent method signatures, parameter names, default values, or behaviour from memory.** Hallucinated APIs compile-fail in the best case and silently misbehave in the worst.

Lookup order:
1. **Existing usage in this repo** — `Grep` for the symbol or `import 'package:<pkg>'` first. Project established the canonical idiom; copy that pattern. Canonical examples: russh / russh-sftp under `rust/crates/lfs_core/src/ssh/`, rusqlite under `.../db/`, RustCrypto (`aes-gcm`, `argon2`, `ed25519-dalek`) under `.../crypto/`, OS-bound surfaces under `rust/crates/lfs_os_security/`, FRB bindings under `lib/src/rust/`.
2. **Context7** — `mcp__context7__resolve-library-id` then `mcp__context7__get-library-docs`.
3. **Web docs** — official docs site, package README on pub.dev / crates.io / GitHub.
4. **Source** — read the package source under `~/.pub-cache/` (Dart) or `~/.cargo/registry/` (Rust).

If after all four you still don't know, ask the user. Do not guess.

### Reuse First (project-wide, not just UI)

**Before adding any new widget, helper, mixin, style constant, or store: search `lib/widgets/`, `lib/theme/`, `lib/core/**` for an existing equivalent.** If behaviour is close but not identical, **extend** the shared primitive (add a parameter) instead of forking. A second caller is the trigger to extract; a third caller makes it mandatory.

**Inline implementations in another file are the same as shared components for this rule.** Order:
1. Search `lib/widgets/` — if a shared primitive exists, use it.
2. No shared primitive but visually/behaviourally equivalent **inline block** elsewhere — **lift it to `lib/widgets/` first**, swap the original call site, then build your new caller on top. Shipping a second inline copy "to unblock the current task" leaves every later caller copying the wrong one.
3. Neither shared nor inline precedent — build the new widget in `lib/widgets/` from day one.

The "one-off when pattern doesn't fit" escape hatch covers shape divergence (different layout, different gesture contract), not speed.

What this rule covers (not just UI):
- **Widgets** — `AppIconButton`, `AppDialog` (+ `AppDialogHeader`/`Footer`/`Action`), `HoverRegion`, `AppDataRow`, `AppDataSearchBar`, `StyledFormField`, `SortableHeaderCell`, `ColumnResizeHandle`, `StatusIndicator`, `MobileSelectionBar`, `AppShell`, `ModeButton`, `ConfirmDialog`, `ErrorState`.
- **Theme constants** — `AppTheme.radius{Sm,Md,Lg}`, `AppTheme.barHeight*`, `AppTheme.controlHeight*`, `AppTheme.itemHeight*`, `AppTheme.*ColWidth`, `AppFonts.{tiny,xxs,xs,sm,md,lg,xl}`. Hardcoded sizes/radii/heights/font sizes/padding scales = bug.
- **Cross-feature mixins / helpers** — `SftpBrowserMixin`, `key_file_helper.dart`, `breadcrumb_path.dart`, `column_widths.dart`, `progress_writer.dart`, `shell_helper.dart`. New cross-cutting logic gets a `*_helper.dart` or mixin.
- **Persistence** — every entity follows `Store → DAO` template ([§11](docs/ARCHITECTURE.md#11-persistence--storage)). Don't invent new persistence patterns.

**Non-negotiable triggers** — refactor before committing if:
1. Same string literal in ≥3 places (S1192) → constant or l10n key.
2. Same widget tree (≥5 lines) in ≥2 files → extract widget.
3. Same hardcoded numeric (radius, padding, width, height, fontSize) in ≥2 places → constant in `AppTheme` / `AppFonts`.
4. Same `if/else` block or async pipeline in ≥2 callers → extract helper / mixin.
5. New `*_dialog.dart` / `*_button.dart` / `*_row.dart` that doesn't extend an existing `App*` primitive → check first whether a parameter on the existing primitive solves it.

**Premature-abstraction guard:** triggers mean *consider extraction*, not *extract no matter what*. If the third caller would force a parameter that warps the first two (a flag toggling whole different layout, or coupling unrelated concerns), leave the duplication and add a `// TODO(reuse): N callers — revisit when shape stabilises` comment. Reuse exists to reduce surface area, not grow it.

### Comments — Short and Current

Code comments are **load-bearing** when they exist. They describe a *present* invariant the next reader cannot infer from well-named identifiers. Every line lives forever and gets read every time someone scrolls past.

**1. Short.** One line max. No multi-paragraph blocks. If rationale needs a paragraph, write it into `ARCHITECTURE.md` and point:

```dart
// See ARCHITECTURE.md §3.6 → SecretStore for the plaintext-discipline rule.
```

A long comment is almost always one of: a retrospective (delete the historical part), documentation that should be in ARCHITECTURE.md (move it, link), or a signal the code is too tangled (per Docs First step 8 — propose simplification).

**2. Current state only — no retrospective.** A comment describes the code *as it is now*. Forbidden phrases:

- `originally...` / `previously...` / `the previous Dart-side...` / `earlier revisions...`
- `after the migration...` / `replaces the historical...` / `replaces the legacy...`
- `now retired` / `now Rust-side` / `moved out of...` / `moved to...`
- `the legacy path...` / `before we...` / `we used to...`
- `Mirrors the prior...` / `Matches the prior...` / `the prior Dart implementation`
- `pre-fix...` / `Pre-fix shape...`

The "what was the bug, what is the new shape" prose belongs in the **commit message**, not in the source. Once committed, only the comment gets read — "we used to do X, now we do Y" is wrong-by-construction the moment a reader scans it: X is gone, only Y exists.

The exception is when **the prior shape can come back as a regression** and naming it teaches a future maintainer the trap. Write the *invariant* + a one-line *why*:

```dart
// `\x1B[H` resets the cursor; `\x1B[2J` alone leaves it at the
// last write position and the next paint redraws over stale lines.
```

State the rule, name the trap, move on.

**Acceptable shapes:**
- `// X is staged via SecretStore so plaintext never crosses FRB outbound.` ✓
- `// Idempotent: caller may invoke twice without surprise.` ✓
- `// Cold-start invariant: pure Dart only — see ARCHITECTURE § Cold-start ordering.` ✓

**Editing existing long comments:** same rule. Shorten, drop retrospective, link to ARCHITECTURE.md for rationale.

**Review check.** Before every commit grep the staged diff for `previously`, `pre-fix`, `the prior`, `the earlier`, `Mirrors the prior`, `used to`, `originally`, `legacy` (in narrative voice — `legacy fallback path` describing a runtime alternative is fine; `replaces the legacy` is not).

**3. No fabricated rationale.** Only cite platforms, measurements, failure mechanisms, behavioural claims that are real and verifiable from code, git log, or captured user report. Forbidden:

- **Concrete timings without source:** `~3 s on Win IoT`, `~5 s of dbInit on Windows IoT`, `~500 ms on healthy hosts`. No generic-sounding alternatives either (`non-trivial latency`, `takes time to load`) — those imply you measured something. Document the structural reason instead (the bug class prevented, the contract enforced).
- **Specific platforms named as canonical case** when the project's CI / supported-platforms list does not enumerate the platform.
- **Specific OS subsystems pinned as cause without concrete link** (`Defender real-time scan`, `Gatekeeper signature check`, `SELinux relabel`). Generic `the OS may inspect new binaries` is fine; pinning the subsystem fabricates a falsifiable claim.
- **Causal chains explaining *why* when you have only the *what*.** If the deferral exists in code but the "why" is not in commit message, docs, or user-confirmed bug, document the structural fact and the invariant it enforces.

Same rule applies to Rust `//`/`///`/`//!` and Dart `///` doc comments. Multi-paragraph module-level `//!` get the ARCHITECTURE-link treatment.

### Architecture (non-obvious rules)

- **No SCP** — SFTP covers every transfer use case; `lfs_core::sftp` is the only file-transfer surface.
- SSH keys accepted **both as file and text** (paste PEM).
- `.lfs` export format and import modes — single source of truth: [§3.9 Import](docs/ARCHITECTURE.md#39-import-coreimport).
- Credentials in `CredentialStore` (AES-256-GCM), NOT in plain JSON — [§3.6 Security](docs/ARCHITECTURE.md#36-security--encryption-coresecurity).
- **State placement** — app-wide state → Riverpod `NotifierProvider`; widget-local state (dialog / pane / panel / tab) with constructor-injected args or caches → `ChangeNotifier` + `AnimatedBuilder` (canonical examples: `FilePaneController`, `UnifiedExportController`, `SessionPanelController`, `TransferPanelController`). Side-channel Riverpod overrides for widget-local state = boilerplate with no win — [§4.3](docs/ARCHITECTURE.md#43-widget-local-controllers-changenotifier).

### Logging — AppLogger, Auto-Sanitized, Err On More Not Less

Every log line goes through `AppLogger.instance.log(message, name: 'Tag', error: e, stackTrace: st)`. **Never call `print` or `dart:developer`'s `log` directly** — both bypass the sanitizer (and `print` survives release builds). The logger writes to its own file sink only — no OS-logging mirror. The only log channel is the opt-in file at `<appSupportDir>/logs/letsflutssh.log`.

Output is threshold-gated at runtime (Settings → Logging level: `Off` / `Error` / `Warn` / `Info` / `Debug`). Default is `Off` (privacy-first). `logCritical` bypasses the threshold so crash breadcrumbs land even when routine logging is disabled.

**Every message passes through `AppLogger.sanitize` automatically** — `redactSecrets` scrubs PEM private keys and long base64 runs, then `sanitizeErrorMessage` redacts IPv4/IPv6, `user@host`, `host:port`, Windows `C:\Users\<name>` and Unix `/home/<name>` paths, plus `as <user>` / `user=<user>` / `login=<user>` shapes. You do NOT pre-sanitize by hand. The sanitizer cannot catch **free-form user-chosen strings** (session labels, key labels, tag names, snippet titles, folder names) — for those, log marker `<label>` not the value. See [ARCHITECTURE § Error Handling Architecture](docs/ARCHITECTURE.md#error-handling-architecture).

**Add logs generously.** Default sink is off so there is no log-spam cost; only opted-in users pay the write. Log at every load-bearing state transition:
- entry/exit of any operation touching disk/DB/network/subprocess/native plugin — mention success or failure
- every branch of user-consequential `try/catch`, including swallowed-and-continued
- every decision on ambiguous input (archive kind detected, migration applied, TOFU branch, fallback chosen)
- every place a previous bug could surface — if the fix added a guard, log the guard firing

Test: "could a user hand me the log and could I tell what happened without reproducing?" — if no, add lines until yes.

**Name tags are module-scoped, not file-scoped**: `'FilePane'`, `'Session'`, `'KdfParams'`, `'MigrationRunner'`, `'KnownHosts'`, `'SecureClipboard'`. Grep existing `name:` usage before inventing.

**Never compose a message embedding a raw password, passphrase, or private-key byte.** Sanitizer catches PEM + long base64 but a short passphrase falls through. Log `'Password verify failed'`, never `'Password verify failed: $typedPassword'`. `AppLogger.instance.log('X failed: $e', name: 'Tag', error: e)` is fine (sanitizer handles exception text); `'X failed with pass $password: $e'` is not.

**Critical paths use `logCritical`.** Global crash handlers (`FlutterError.onError`, `PlatformDispatcher.onError`, `runZonedGuarded`), migration fatals, DB integrity-probe failures — so the file line lands even with logging off.

**Pick severity deliberately.** Four values (`D` debug / `I` info / `W` warn / `E` error). Auto-rules:
- `log(..., error: e)` **without** explicit `level:` auto-promotes to `LogLevel.error`. Don't add `level: LogLevel.error` redundantly.
- `logCritical` is always `error` — do not pass `level:`.
- Everything else defaults to `info`.

**Level guide:**
- **info** (default) — routine state transition. "Session loaded", "tier switched", "DB opened", "SFTP connected". One line per meaningful event, never per-frame / per-packet.
- **warn** — degraded but recoverable. Fallback paths, missing optional state, rate-limit kick-ins, skipped duplicates, probe failures routing to a weaker default. The operation continued; user keeps a working app with weaker guarantee. **Override the auto-promote** when a recoverable path also carries an exception: `log('X failed, falling back', error: e, level: LogLevel.warn)` — otherwise viewer tints red and user thinks fallback broke.
- **error** — failure user cares about. Migration fatal, DB corruption, lost credentials, unrecoverable connection drop, crash breadcrumb. Operation aborted or entered recovery requiring user action.

**No debug/verbose rung** — taxonomy stops at info. Per-packet/per-frame tracing for a specific bug → wrap behind a local flag you ship and revert.

**Picking warn vs error:** "Did the user lose anything irrecoverable, or did the code route around silently?" If user keeps using the feature with weaker fallback → warn. If feature unavailable / data at risk → error.

**Picking info vs warn:** "Would a user pasting 20 lines from the viewer into a bug report want this line in those 20?" Yes + succeeded → info. Degraded → warn. Per-packet/per-frame should not land in the log at all.

**All levels are user-visible.** Once the user picks any threshold, every line at or above lands in the same file they can export. Write every I/W/E line as if read out of context: full noun, short verb, concrete subject.

**Dev / beta-tester builds override threshold at compile time:** `--dart-define=LETSFLUTSSH_LOG_LEVEL=<level>` (value `info` / `warn` / `error`). `make run` wires this to `info` by default. Release builds ship without — never set the flag in a release.

### Theme & UI Constants

OneDark theme: centralized in `app_theme.dart`, semantic color constants, no hardcoded `Colors` — [§8 Theme](docs/ARCHITECTURE.md#8-theme-system).

- **Font sizes** — never hardcode `fontSize`. Use `AppFonts.tiny`/`xxs`/`xs`/`sm`/`md`/`lg`/`xl` (mobile +2 px).
- **Border radius** — never hardcode `BorderRadius.circular(N)`. Use `AppTheme.radiusSm` (4), `radiusMd` (6), `radiusLg` (8). Exception: pill-shaped elements.
- **Heights** — never hardcode height literals. Use `AppTheme` constants: `barHeight{Sm,Md,Lg}`, `controlHeight{Xs..Xl}`, `itemHeight{Xs..Xl}`.

### UI Components

- **Buttons & hover** — `AppIconButton` for all icon buttons. `HoverRegion` for custom hover containers. Never use bare `IconButton`, `InkWell` for buttons, or manual `MouseRegion`+`GestureDetector`+`setState(_hovered)`. Exception: `context_menu.dart`, mobile touch buttons — [§6 Widgets API](docs/ARCHITECTURE.md#6-widgets--public-api-reference).
- **Dialogs** — `AppDialog` for all modal dialogs. Never bare `AlertDialog`. Complex dialogs: compose from `AppDialogHeader`/`AppDialogFooter`/`AppButton`. Progress: `AppProgressDialog.show()`. Exception: mobile touch buttons keep `Material`+`InkWell` for ripple.
- **Text selection is opt-in on desktop — clickable ≠ selectable.** No global `SelectionArea` wraps the desktop shell (prior global wrap broke `ThresholdDraggable` because `SelectionArea`'s `TapAndDragGestureRecognizer` claimed pan ahead of `MultiDragGestureRecognizer`). Wrap specific prose surfaces in `AppSelectionArea` locally: dialog bodies, threat lists, release-notes bodies, help prose. Never wrap a container that also hosts a drag target, `AppButton`, or interactive row. Mobile keeps one `AppSelectionArea(child: MobileShell())`. **Inside any scoped `AppSelectionArea`: every clickable tile / row / header / badge opts out via `SelectionContainer.disabled`** — `HoverRegion` already auto-wraps; `InkWell` does not, wrap its child explicitly. Form field labels also opt out — they are not "content to copy". When clickable text stays selectable, the click cursor wins over the I-beam — half-broken UX. — [§6 Selection scoping](docs/ARCHITECTURE.md#selection-scoping).
- **Session panel shortcut / focus / clipboard contract** — shortcut dispatch uses `CallbackShortcuts` (not `Focus.onKeyEvent`), empty-sidebar tap clears the focused pointer but keeps `FocusNode` focused, folder click is two-phase (focus → toggle), paste resolves target lazily at paste time, clipboard holds session id pointer (no TTL, no RAM copy). [§5.3](docs/ARCHITECTURE.md#53-session-manager-ui-featuressession_manager).
- **Text overflow protection** — localized text in `Row` or fixed-width — wrap with `Flexible`/`Expanded` + `overflow: TextOverflow.ellipsis`. For label columns use `ConstrainedBox(maxWidth:)` instead of fixed `SizedBox(width:)`.
- **Accessibility** — wrap interactive list items (session rows, file rows) and panel headers with `Semantics`. Use `label` for screen reader text, `button: true` for tappable, `selected` for selection state, `header: true` for sections. `StatusIndicator` includes built-in `Semantics`.
- **Disable vs hide unavailable controls — depends on surface type.** On *configuration surfaces* (Settings, session-edit forms, preference dialogs), always render disabled with tooltip + tap-toast explaining the reason — never hide. The user is exploring what the app can do and needs to know the option exists. On *action surfaces* (lock screen, context menus, per-row action buttons, action dialogs), **hide** unavailable actions — a greyed button is noise, not information. Disabled state must visibly affect the whole row (opacity on full container).
- **Prefer shared components** — full rule in § Reuse First.

### Localization (i18n)

All user-facing strings MUST use `S.of(context).xxx`. Never hardcode strings in widgets — treat as a bug. Add keys to `lib/l10n/app_en.arb`, run `flutter gen-l10n`, use `S.of(context).newKey`. Exceptions: constructor defaults (no context), log messages, `_AlreadyRunningApp`. Tests must include `localizationsDelegates: S.localizationsDelegates, supportedLocales: S.supportedLocales` in every `MaterialApp`. See [§8.1 i18n](docs/ARCHITECTURE.md#81-internationalization-i18n).

### Localization Tone — Native IT Register, Not Dictionary Calques

Audience is engineers and sysadmins. Strings must read like a dev explaining to a colleague, not a textbook, not machine-translated. Two rules.

**1. Technical terms follow each locale's real IT register — not a mechanical "keep English" rule.**

Per-locale guide:

| Locale | Dominant pattern for tech terms |
|---|---|
| RU | Latin for tech (SSH, keychain, hardware, wrapped key). Prose Russian. |
| ES, PT-BR, FR, DE, IT | Latin for dev-tool tech (SSH, Keychain, Hardware, Log, Timeout, Worker, Fingerprint, Passphrase, Scrollback, Release, rate limit). Apple/MS consumer-UI natives (trousseau, Schlüsselbund, llavero) OK only for macOS-specific labels, not dev-tool chrome. |
| TR, ID | Heavy English in dev context. TDK / KBBI / öztürkçe / baku calques read textbook. |
| AR, FA, HI, VI | Latin tech terms inside native prose is normal. Native coinages for SSH/TPM/keychain/forensics/wrapping sound amateur. |
| JA | Katakana (キーチェーン, ハードウェア) for loan words; Latin (SSH, TPM, DMA, CVE, Argon2id) for acronyms. |
| KO | Hangul transliteration (키체인, 하드웨어) or Latin — both valid. Match native dev doc convention. |
| ZH | Latin for protocols/acronyms always (SSH, TPM, DMA, CVE, TLS). Common words translate (硬件, 密码). Apple term 钥匙串 OK but `keychain` Latin also works. |

**Anti-patterns — never:**
- Coin a native word for "keychain" when native devs don't use one (RU ключница, VI chuỗi khóa, FA کلیدستان, KO 열쇠고리, ZH 钥匙链).
- Translate Unix "pipe" as literal water pipe (RU труба, PT Pipa, TR Boru, AR أنبوب — canonical POSIX `Broken pipe` is recognized verbatim).
- Translate "worker" as human laborer (PT Trabalhadores, AR العمال, TR İşçi — evokes factory, not concurrency).
- Translate "Paranoid" (tier codename) as psychiatric diagnosis (AR جنون الارتياب, VI Hoang tưởng — tier names stay English/parenthesized).
- Translate "forensics" as legal/courtroom (RU криминалистика, PT Perícia — use "memory dump / RAM dump / RAM forensics").
- Translate "wrapped key" / "sealed blob" with literal wrapping idioms (AR المفتاح الملفوف = cabbage roll, ZH 被包装的 = gift-wrapped — keep Latin or use crypto-register verb).
- Translate SSH "fingerprint" with biometric word when the app also has biometric auth (ES Huella digital, PT Impressão digital — collides with biometric-unlock UI).

**2. Prose reads as living language, not word-for-word English grammar.**

- Use action verbs, not noun piles. Short sentences > long participle/relative chains.
- No "please" in error messages (RU пожалуйста, ES Por favor, JA ください, TR lütfen — drop all).
- No Apple-sir / keigo / ustedeo register inflation beyond what the locale's real dev UIs use.
- Don't mix dialects (PT BR vs PT PT; ES tuteo vs ustedeo; DE du vs Sie) — pick one per file.
- Don't use different translations for the same English term in the same file. Pick one term → use everywhere.

**Critical semantic-inversion traps (fix wherever they appear):**
- ES `restablecida` / PT `redefinida` for "connection reset by peer" — both mean re-established/redefined, opposite. Use `reiniciada por el peer` / `encerrada pelo peer`.
- KO `암호문` for "passphrase" — means `ciphertext`. Use `패스프레이즈`.
- JA `解錠` for "decrypt/unwrap" — picking a physical lock. Use `復号`.
- JA `ボルト` for "vault" — means bolt/volt. Use `ボールト`.
- HI `समझौता` for "compromise" — means agreement/deal. Use `कॉम्प्रोमाइज़` or rephrase.
- FR `sauvegardé` for "backed by" — false friend, means backed up. Use `adossé à` / `reposant sur`.

**Self-test before shipping:** read it aloud. If it sounds like a textbook or machine-translation glossary → rewrite. If it sounds like a Slack message to a colleague → ship.

**Do localization yourself — don't delegate translation to sub-agents.** Sub-agents miss conversation register, prior-string feedback, per-locale norms, in-session decisions; they fall back to "safe" dictionary calques (the failure mode we avoid). Survey use (read 1000-line file, flag candidates) is fine; tone decisions stay in the main thread.

**Watchlist — terms that routinely get miscalqued** (keep English / native IT form unless the locale's dev community genuinely uses a native equivalent): SSH, SFTP, SCP, TLS, DNS, proxy, TCP, known_hosts, TPM, TEE, DMA, Secure Enclave, StrongBox, HSM, keychain, keyring, Keystore, Credential Manager, key material, wrapped key, sealed blob, KDF, PBKDF2, Argon2id, AES, HMAC, AEAD, passphrase, fingerprint (disambiguate from biometric), host, host key, port, login, logging/log, worker, scrollback, release, timeout, keep-alive, rate limit, backdoor, plaintext, snapshot, forensics, dump, probe, breaking change, driver, distro, config, credential, slot, vault, kernel, build, runtime, mitigation, lockout, idle.

### Diagrams in Docs — Mermaid, Not ASCII Box-Art

Every diagram in `docs/**/*.md`, `README.md`, `SECURITY.md` and any other git-tracked markdown MUST be a ` ```mermaid ` fenced block (`flowchart`, `stateDiagram-v2`, `sequenceDiagram`, `classDiagram`). GitHub renders these as SVG; ASCII `┌─┐`/`└─┘` box-art breaks on narrow viewports. When editing an existing ASCII diagram, convert in the same commit.

**Covered:** diagrams (nodes + arrows, layered boxes, state graphs, flows) → Mermaid. **Not covered:** directory trees (`├── core/`) → keep plain fenced (Mermaid is worse for deep trees); pipe tables (`| col |`) → GitHub already renders as HTML; code blocks (`` ```dart ``) → unchanged.

Single-box info cards ("here are the fields of this object") → plain markdown bullets, not a box. Don't add ASCII "fallbacks" via `<details>` — that doubles the source and rots under edits.

### Plan-Item IDs Stay Internal

Plans, session notes, backlogs live **outside git** (`~/.claude/plans/*`, `SECURITY_BACKLOG.md`, `~/.claude/projects/*/memory/*`). Never reference their identifiers — `P1.2-*`, `A1`, `D1`, `Phase E1`, `Phase G1`, `Phase F2`, `Task 3.2`, `Phase 4.2 stage 6.1`, `stage 6.6`, anything of that shape — in any file that lands in git:

- Commit titles and bodies (most common leak — guard hardest)
- Code comments and docstrings — including `// stage 6 transitional`, "TODO retire after stage X". If reason-for-being is "the migration plan asked for it", phrase it as the *behavioural* reason.
- Filenames and section headers
- README.md, ARCHITECTURE.md, SECURITY.md, this file, CONTRIBUTING.md, CHANGELOG.md, any tool-specific agent-instruction file
- Any other tracked artefact

This applies **even when the plan document lives in git** — such documents are temporary scaffolding.

**Cross-references to ARCHITECTURE.md sections by `§N.M` numerals are FINE** — both inside the doc and from commit messages, code comments, or other tracked artefacts. ARCHITECTURE.md is a stable, long-lived document.

If a commit needs to explain "why this came with that", describe prose-wise: `"ships alongside the overlay methods added to the native plugins"` — not `"wraps up Phase D1"`.

**Review check:** before staging, grep your diff *and the staged commit message* for `/P[0-9]/`, `/Phase [0-9A-Z]/`, `/stage [0-9]/`, `/Task [0-9]/`, `/[A-Z][0-9] /`. Do NOT grep for `§[0-9]` or `Section [0-9]`: those are stable doc anchors.

---

## Code Quality — SonarCloud

All code must follow **Effective Dart** and pass `dart analyze` with zero issues. `make analyze` must pass before every commit touching Dart code. **Never suppress** — `// ignore:`, `// NOSONAR`, `@SuppressWarnings` are forbidden.

**Skip manual `make analyze` / `make test` when the staged diff is doc-only** (Markdown, `.arb` strings, images, READMEs, rule files under `docs/`). Pre-commit hook still runs `make check` automatically. Quick test: if `git diff --name-only --cached | grep -E '\.dart$|pubspec\.yaml'` returns nothing, skip.

### Rules that bite most often

Write code that already obeys these on first draft — don't write, wait for the scanner, then refactor.

- **S3776 — cognitive complexity ≤ 15.** Each `if` / `for` / `while` / `switch case` / `&&` / `||` adds; nesting multiplies. A widget `build()` with tall `children: [ if … else ... if … for (…) widget(a ? b : c) ]` blows the budget fast. When in doubt:
  - Extract each conditional child into a `Widget _buildFoo(…)` helper.
  - Pull repeated inline computations into a local `final already = …;` before the `return`.
  - Any `for (var i = 0; i < list.length; i++) ComplexWidget(...)` → extract `_buildRow(i)`.
  - **Non-widget patterns:**
    - **Top-level `if (enable) { … } else { … }` with non-trivial branches** → split on the boolean: `_toggleFoo(enable)` delegates to `_enableFoo()` / `_disableFoo()`.
    - **Long `if (error is X) return …;` chains** → group by category, extract `_tryLocalizeFooError` helpers returning `String?`.
    - **Async methods chaining 3+ phases with nested mounted/null guards** → extract each phase into `Future<T?> _phaseFoo(…)` returning `null` on cancel/failure. Caller becomes a straight-line pipeline.
    - **Optional archive/JSON entries with nested `if (requested) { if (present) { if (valid) { … } } }`** → extract `_entryReader` returning `T?`. Caller becomes `final x = requested ? _readFoo(archive) : null;`.
- **S3358 — no nested ternaries.** Patterns like `busy ? null : (forKeys ? _a : _b)` must be rewritten as `if`/`else if`/`else` assigning to a local, or a `switch` expression. Watch the subtle case where outer ternary's branch is a widget constructor whose argument is itself a ternary — `active ? Icon(asc ? up : down) : null` is already S3358. Extract the trailing widget into a `_directionIcon(col)` helper.
- **S1854 — dead/unused values.** Don't `final x = ...;` then overwrite `x` unconditionally. Use `late final x; if (…) x = …; else x = …;` or `if`/`else`-assigned local.
- **S1192 — string literals duplicated ≥3 times.** Pull into `static const _kFoo = '…'` or l10n key.
- **S1481 — unused local vars / S1172 — unused parameters.** Delete or prefix with `_`.
- **No `print()` / `debugPrint()`** — use `AppLogger.instance.log(message, name: 'Tag')`. Errors surfacing to UI go through `localizeError()` so PEM/base64 are redacted.
- **No generated file edits** — `*.g.dart` and `*.freezed.dart` are excluded; change the source.

**Shape before scanner.** If a method body is more than ~30 lines or has three nested conditional blocks, split before committing. Widget `build()` over that threshold should already have named `_buildFoo` helpers.

---

## Testing Methodology

**Everything that can be unit-tested without touching the OS or an external system must be unit-tested.** Allow-list for "no unit test": OS-specific capability (biometric prompt, OS keychain, native plugin MethodChannel, platform file pickers, single-instance lock, notification APIs, TPM / Secure Enclave / Windows Hello, Linux D-Bus services like `fprintd`) or integration with external system (real SSH/SFTP server, real QR camera, real update server, real Dependabot/CI). For exempt functions, the harness-testable **slice** around them still gets tests — isolate pure-Dart logic (argument validation, shape of the call, post-processing, error mapping) from the non-testable edge.

Target: 100% coverage (excluding OS-specific edges + integration tests). One test file per source file. Testable by design: extract pure logic, DI over hardcoded `ref.read()` — [§14](docs/ARCHITECTURE.md#14-testing-patterns--di-hooks). If a function cannot be unit-tested and the reason is **not** on the allow-list, refactor until it can be — don't ship without coverage.

- **Tests assert spec, not current output.** Before writing any `expect(...)`, state in one sentence what the function _should_ do for that input — derived from the feature's intent, not from running the code. **Never** run, observe output, paste into `expect(...)` — that's a pinning test that cements bugs. If correct behavior is unclear, stop and ask.
- **When test and code disagree, surface it — don't silently "fix" either side.** You have one of three: (1) real bug in code, (2) wrong spec on your side, (3) ambiguous requirement. You cannot tell from inside the test file. Stop, report with: input, spec + where derived, current output. Let the user decide.
- **Failing tests after a code change: diagnose before editing the test.** Default reaction: read the test and ask "is this catching a regression my change introduced?" — not "how do I update the assertions?" Triage: (1) re-derive the test's intended contract; (2) compare to what your change promised; (3) if the test still checks a contract your change did NOT intend to break, the code is wrong; (4) only when the test pins an internal detail you deliberately reshaped do you rewrite — and the new assertion expresses the **new** contract intent-first, not pasted from current output.
- **Uncovered lines are a marker, not a target.** Don't write tests whose only goal is to execute the line (`expect(result, isNotNull)` / `isA<T>()` / "doesn't throw"). Ask: what branch / decision / contract does this line encode? Write a test that fails if that contract breaks.
- **Fuzz tests for every untrusted-input consumer** — not only parsers. Any function decoding/validating bytes/strings/maps from outside the app needs a fuzz target. "Outside" tiers:
  - **User-supplied files** — import flows (`.lfs` archive, OpenSSH config, known_hosts, PEM key bundles), wizard text, clipboard paste.
  - **Network / peer-supplied** — SSH server banner, SFTP path strings, terminal ANSI escape parser (post-processing).
  - **Inter-process** — deep-link URIs, QR payload, OS clipboard, IPC.
  - **On-disk state** — config JSON, session JSON, KDF params, LFS archive header, biometric vault blob, keychain blobs.
  
  Each target gets a Dart property-based test in `test/fuzz/` (Flutter/pub deps) or standalone harness in `fuzz/` + seed corpus + CFL wiring in `.clusterfuzzlite/build.sh` (libFuzzer). New untrusted-input code = new fuzz target in the same commit. See [§14 Fuzz testing](docs/ARCHITECTURE.md#fuzz-testing).
- **UI changes = test updates** — proactively update all tests referencing changed widget names, labels, or finders.

---

## Commits & Versioning

- **Agent does not commit or push unless the user explicitly asks.** "commit" = commit only, "commit and push" = commit + push.
- **HARD STOP between fixes** — implement fix → write tests → update docs → **emit a post-fix summary** → **stop and ask user to commit**. Do NOT start the next fix until current is committed. **Exceptions:**
  - User signals batch mode — "fix all and push", "don't ask", "go through the plan", "stop asking", or same intent in any language. Execute end-to-end without pausing.
  - Series of related doc/rule/convention edits in a single session — batch into **one** commit at the natural arc end.
- **Post-fix summary is mandatory.** Before the "commit?" prompt OR at the natural end of a batched arc, state for each bug:
  1. **Symptom** — user-visible behaviour that was wrong (their literal complaint).
  2. **Root cause** — why it happened (stale state, missing branch, wrong invariant, race), named with file/function/field.
  3. **Fix** — what you changed to address the root cause, not just "I edited file X".
  
  Don't skip because the diff "speaks for itself" — user reads the summary to decide whether you understood the bug. If you cannot write the root cause clearly, you have not understood it. One bug per paragraph, ≤5 lines. **Batch mode** — single combined report at arc end, not per sub-commit.
- Format per [CONTRIBUTING.md](docs/CONTRIBUTING.md#commit-messages). Messages drive auto-changelog — keep user-readable.
- **Use `type(scope):` with parenthesized scope** for module-specific commits (`refactor(import): ...`, `test(known-hosts): ...`, `feat(installer): ...`). Drop scope only when genuinely cross-cutting. Scope: lowercase, alphanumeric + dashes.
- **Version bumps are automatic.** `/pr` skill runs `scripts/bump-version.sh` — parses conventional commits since last tag, bumps `pubspec.yaml` (patch for fix/refactor/perf/build/deps, minor for feat, major for BREAKING CHANGE; chore/docs/test/ci/Revert = no bump). Don't bump manually. Dependabot PRs are bumped by CI (`dependabot-auto.yml`).
- **Never amend after push** — only new commits. Amend OK only before first push.
- **Green CI before merging to main** — pre-commit hook runs `make check` automatically.

---

## Branching & Release Flow

- **Default working branch is `dev`.** Never push directly to `main`.
- Repository is **public** on GitHub.

| Scenario | What to do |
|---|---|
| App change (feat/fix/refactor) | `bump-version.sh` on dev → PR `dev` → `main` → CI → auto-tag → release |
| Tests/docs/CI only | Merge to `main` — no bump, no tag, no release |
| Dependabot deps | Auto: PR to main → bump in branch → merge → CI → auto-tag → release |
| Manual build | `gh workflow run build-release.yml` — fails if CI hasn't passed |
| Failed build (re-trigger) | `gh workflow run build-release.yml --ref v{VERSION}` |
