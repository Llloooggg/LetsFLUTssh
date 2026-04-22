# Agent Rules — Reference Tables

Reference material for any AI coding agent operating on this repo. Read the specific section you need, not the whole file.

## Quick Navigation by Task

### Within AGENT_RULES (this file)

| I'm about to... | Read this section |
|---|---|
| Edit code in any module | [§ Docs First — Read Before, Fix Drift, Update After](#docs-first--read-before-fix-drift-update-after) + map the module to its ARCHITECTURE § via [Within ARCHITECTURE.md nav](#within-architecturemd) |
| Write a commit message / bump version | [§ Commits & Versioning](#commits--versioning) + [§ Plan-Item IDs Stay Internal](#plan-item-ids-stay-internal) |
| Open a PR / merge to main | [§ Branching & Release Flow](#branching--release-flow) |
| Add/edit a diagram in docs | [§ Diagrams in Docs](#diagrams-in-docs--mermaid-not-ascii-box-art) — Mermaid only, no ASCII box-art |
| Write or refactor any Dart code | [§ Code Quality — SonarCloud](#code-quality--sonarcloud) + [§ Conventions](#conventions) |
| Call API of an external package (dartssh2, drift, riverpod, xterm, …) | [§ Conventions → External Libraries & APIs](#external-libraries--apis--look-up-dont-guess) — grep repo first, then Context7 / web docs / pub-cache source |
| Add a new dependency or feature that needs an OS capability | [§ Conventions → Self-Contained Binary](#self-contained-binary--end-user-installs-nothing) — bundle > fallback > optional-with-docs |
| Tempted to propose per-platform native rewrite of a working feature ("true X", "real X", "verified X") | [§ Conventions → Don't Escalate Working Baselines](#dont-escalate-working-baselines) — don't escalate; document the gap, don't fill it with code unless the user asks |
| Write or update a test | [§ Testing Methodology](#testing-methodology) |
| Add/change a user-facing string | [§ Conventions → Localization](#localization-i18n) + [§ Localization Tone](#localization-tone--native-it-register-not-dictionary-calques) + [§ Doc Maintenance](#documentation-maintenance-checklist) row "user-facing string" |
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
| Bump a persisted-file format / add a new envelope artefact | [§3.6 → Migration framework](ARCHITECTURE.md#migration-framework-coremigration) + [§3.6 → Developer guide](ARCHITECTURE.md#developer-guide--how-to-ship-a-format-change) — `SchemaVersions` + `Migration` + register in `buildAppMigrationRegistry()` |
| Bump the `.lfs` archive `schema_version` | [§3.9 Import → .lfs format](ARCHITECTURE.md#39-import-coreimport) + [§3.6 → Migration framework](ARCHITECTURE.md#migration-framework-coremigration) — register the `Migration` in `archiveMigrationRegistry` |
| Check data models | [§10 Data Models](ARCHITECTURE.md#10-data-models) |
| Understand CI/CD / workflows | [§15 CI/CD Pipeline](ARCHITECTURE.md#15-cicd-pipeline) |
| Check design decisions / gotchas | [§16 Design Decisions](ARCHITECTURE.md#16-design-decisions--rationale) |
| Check dependencies / versions | [§17 Dependencies](ARCHITECTURE.md#17-dependencies) |
| Write tests / understand DI | [§14 Testing Patterns](ARCHITECTURE.md#14-testing-patterns--di-hooks) |

## Docs First — Read Before, Fix Drift, Update After

**This is the single most important discipline in the project.** The code is temporary; the docs are how intent survives across refactors, contributor handovers, and returning to a module six months later. A codebase with stale or thin docs decays into a graph future readers re-derive from grep — slowly, expensively, and with different conclusions each time. **Treat `ARCHITECTURE.md` as a first-class deliverable, not a byproduct of the code.** Every task — planning, editing, bug-fixing, refactor, review — is also a docs task. Reading, keeping the docs current, and extending them (new §s, cross-links, TOC entries, CLAUDE.md / AGENT_RULES.md nav rows) is load-bearing work, not overhead. When in doubt between "write less doc" and "write more doc", write more.

**Audience — write for humans, always.** `ARCHITECTURE.md`, `README.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md` and every other git-tracked doc that is not explicitly an agent-instruction file are written **for humans** — the solo maintainer, future contributors, outside reviewers, security auditors. Do not pepper these files with LLM-specific asides ("agents should note...", "this helps agents plan...", "for LLM context..."), do not reference `CLAUDE.md` or agent workflows in user-facing docs, do not name AI coding tools in prose that a new contributor is supposed to read to understand the project. Agent-specific guidance belongs in **`CLAUDE.md`, `AGENT_RULES.md`, or `~/.claude/...`** — those are the agent-audience files, and they may freely talk about agents, sessions, plans, and LLM failure modes. The split is absolute: a human opening `ARCHITECTURE.md` should read a normal piece of project documentation, not a prompt. Agents benefit from clean human docs automatically; they do not need asides tagged for them.

**What "describe" means in this project:** every § must cover both *how the thing works* (the mechanism — states, inputs, outputs, invariants, failure modes) **and** *why it is that way* (the rationale — the constraint, the past incident, the alternative that was rejected and why, the trade-off accepted). A § that answers only "how" leaves the next reader to guess at intent; a § that answers only "why" leaves them to re-derive the mechanism. Both are required.

Seven-step discipline for any work (planning **and** editing) that touches a module documented in `ARCHITECTURE.md`:

1. **TOC → specific §, never cover-to-cover.** `ARCHITECTURE.md` is 3000+ lines; reading it whole wastes context and pushes the detail you need out of working memory. The strict order is:
   - **(a) Consult the table of contents first** — the [Within ARCHITECTURE.md nav](#within-architecturemd) in this file, the [CLAUDE.md Action → Read table](../CLAUDE.md#action--read-this-mandatory-before-acting), or the TOC at the top of `docs/ARCHITECTURE.md` itself. The TOC is the index, not optional scaffolding.
   - **(b) From the TOC, pick the exact § that maps to the module you are touching** — `§3.x` for `core/`, `§5.x` for `features/`, `§6` for widgets, `§9` for data flows, `§10` for data models, `§11` for persistence, `§13` for the security model, and so on.
   - **(c) Fetch just that § — use `Read` with `offset`+`limit`.** The `/doc` skill (`.claude/skills/doc/SKILL.md`) is a convenience wrapper that does this: pass it a § id (`3.6`, `§11`, `Tags`, `Session CRUD Flow`) and it grep-locates the heading, computes the range, and reads only that slice. Use it when convenient; either way, **don't `Read` `docs/ARCHITECTURE.md` without a narrowing offset+limit**.
   - **(d) Read only that §, plus any §§ it cross-links to explicitly.** Cross-links (see step 5) are how you widen the read when a topic legitimately spans multiple §s; anything without a link is off-topic for the current task. Widening = another narrow fetch, not a full-file Read.
   - **(e) `/doc` reports no match, grep of headings shows no candidate?** The topic is a **gap**, not a miss — routes to step 2 of this discipline (read the code, fill the gap) and step 7 (proactive write).

   This applies **at the planning stage too** (plan mode, drafting a backlog entry, proposing an approach in chat, answering "how would we do X"): a plan written from grep-only knowledge of the code, or from a cover-to-cover skim, both miss intent and produce plans that fight the existing architecture. Docs capture *intent* (what invariants the module preserves, what failure modes are accepted, why the shape is what it is); code captures only the current state. You need both to plan safely and edit safely.

2. **If the § does not cover your question, or covers it ambiguously, read the code — then fill the gap in the § in the same commit.** Applies to **both planning and editing**: the gap hits you whether you are drafting a plan or changing a file, and the remedy is the same. ARCHITECTURE.md is comprehensive but not exhaustive: a detail the code settles may not be written down yet, or may be written down with a wording that leaves your case open. When that happens, grep / read the implementation, resolve the ambiguity, and **write the answer back into the §** (a new bullet, a tightened sentence, a new sub-section as appropriate). Do not plan or edit from your private reading of the code and leave the § in the same vague state — the next agent will hit the same gap. The § is the canonical record; if the record did not answer you, the record is incomplete, and your commit is the one that completes it (the plan commit if you found the gap while planning, the code commit if you found it while editing).

3. **If you find code-doc drift at any stage (planning or editing), fix the doc in the same commit that reveals it.** Code is the source of truth on current behaviour. If the §X description no longer matches what the file actually does, rewrite the drifted lines so the § matches reality — *before* proposing a plan on top of a stale § and *before* adding new code on top. Never extend a stale § with matching stale additions; that compounds the drift. If the code looks like it drifted *away* from the intended design (a commented-out invariant, a TODO that contradicts the § description, a code path the § calls "forbidden"), flag it and ask the user — do not silently paper over the mismatch in either direction.

4. **After your edits, walk the [Documentation Maintenance Checklist](#documentation-maintenance-checklist) below.** Find every row the diff triggers and update the named §. Ship the doc update in the same commit as the code change — a code change without its matching doc update is an incomplete commit (full rule in [§ Always-On Rules](../CLAUDE.md#always-on-rules-gate-every-action)).

5. **When writing or updating a § in `ARCHITECTURE.md` (or any other git-tracked doc), cross-link to related §s.** Docs are a graph, not a stack of isolated chapters. Any § that mentions behaviour owned by another § — a data model used by a flow, a provider consumed by a widget, a security invariant enforced by a DAO, a platform-specific quirk that shapes an API — must carry a relative markdown link to that other §: `[§9.3 Session CRUD Flow](#93-session-crud-flow)`, `[§10 Data Models → Session](#10-data-models)`, etc. Concrete targets for cross-linking:
   - A §3.x description of a class that persists via a DAO → link to `§11 Persistence`.
   - A §5.x feature description that consumes a provider → link to `§4 State Management`.
   - A §9.x flow diagram that references a model → link to the §10 entry.
   - A §13 security claim that depends on a specific module → link to the §3.x module.
   - Any rule / convention in `AGENT_RULES.md` that is enforced by code in a specific module → link out to the `ARCHITECTURE §` that documents the enforcing code.
   - Any ARCHITECTURE § that describes behaviour shaped by a rule in `AGENT_RULES.md` → link back to that rule.

   When a cross-link target does not exist yet (the related § is too thin, missing, or buried in a general section), **extract it** — create the target § or lift the relevant paragraph into one, then link to it. Better a few extra sub-sections than a § that mentions something the reader cannot jump to. Every new or changed § ships with its outgoing cross-links in the same commit; a § without links is a § stuck in the stack model, and future agents will re-derive the graph from the code instead of from the docs.

6. **When you rename, move, merge, split, or delete a § (or anything with an anchor), update every inbound link in the same commit.** A broken anchor is a stale rule — the link target the reader clicked no longer exists, and whatever rule the link was enforcing silently stops working. Before committing a § restructure:
   - **Grep the whole repo** for the old anchor (`rg -- 'old-anchor-slug'`) — anchors in markdown are the lowercased `§ title` with spaces-as-dashes and punctuation stripped, so `§ Docs First — Read Before, Fix Drift, Update After` becomes `#docs-first--read-before-fix-drift-update-after`. Rename the slug → every file that linked to it needs updating.
   - **Check each of these surfaces** and fix every match:
     - `CLAUDE.md` — Documentation Map, Action → Read table, Always-On Rules. Links to `AGENT_RULES.md` and `ARCHITECTURE.md` sections live here.
     - `docs/AGENT_RULES.md` — Quick Navigation tables (both "Within AGENT_RULES" and "Within ARCHITECTURE.md"), Documentation Maintenance Checklist table, in-§ cross-references, and this § itself.
     - `docs/ARCHITECTURE.md` — TOC at the top, every in-file `[§X](#...)` reference.
     - `README.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md` if they link to docs.
     - Code docstrings or comments that link to a doc anchor.
     - Memory index (`~/.claude/projects/.../memory/MEMORY.md`) if it points at a renamed rule.
   - **When in doubt, link to the file, not the anchor.** If a reference does not need deep-linking, `[AGENT_RULES § Foo](docs/AGENT_RULES.md)` is more rename-resilient than `[AGENT_RULES § Foo](docs/AGENT_RULES.md#foo)`. Prefer anchored links when the anchor is load-bearing (nav tables, checklists); prefer file-level links in prose where the exact landing point is cosmetic.

   This step closes the "I renamed a § and now three files silently link to an empty anchor" failure mode. It applies equally to renaming a § in `ARCHITECTURE.md`, a rule in `AGENT_RULES.md`, a bullet in `CLAUDE.md`, or a file itself (moved `docs/X.md` → update everything that links to the old path).

7. **Extend the docs proactively — don't wait to be blocked.** If while reading an § (even for an unrelated task) you notice that a non-trivial behaviour is under-documented, an important invariant is only implicit in the code, a flow's rationale is missing, or a § only covers "how" without "why" (or vice versa), **write it up** — in the same commit if the scope is small and related, or in a dedicated `docs(architecture): expand §X …` commit if the gap is bigger. You do not need permission to extend the docs; extending them is the default, thinning them is what requires justification. Concrete triggers for a proactive write:
   - The code makes a non-obvious choice (a lock ordering, a specific retry budget, a fallback path) with no matching § paragraph explaining *why* that choice was made.
   - A §-level description says *what* the module does but not *how* it does it, or *how* but not *why*.
   - A §-level description is a single paragraph for a module that has real complexity; split it into sub-sections so each sub-behaviour has a link target.
   - Two §s describe related behaviour without cross-linking (fold into step 5 — add the missing link).
   - A past bugfix commit message explains a subtle constraint that is *not* reflected in the docs; lift the constraint into the § so the next reader sees it without digging through git log.
   - A "magic number" or "seemingly arbitrary default" appears in code without matching explanation in the § — document the value + the reasoning.

   The quality bar: after your proactive write, a new reader opening only the § should be able to answer both *"what does this do?"* and *"why is it shaped this way?"* without opening the code. If they still have to open the code for intent, the § is still too thin.

8. **Writing the § revealed that the code is too complex, tangled, or inefficient? Consider rewriting the code.** The act of documenting a module is also the most honest review it ever gets — the mechanism and rationale you are forced to put into prose either land cleanly or they don't. When they don't — when the § reads like a maze of special cases, when "why" requires three nested "because"s, when the implementation turns out to have redundant paths, duplicate state, or perf traps that only became obvious once you tried to explain them — **treat that as a design signal, not a writing problem**. Do not paper over a confusing implementation with confusing prose. Instead:
   - Stop and ask the user whether the code should be simplified / refactored before the § is finalized. A clean § describing a clean implementation is worth more than a tortured § describing a tortured implementation.
   - If the user agrees, **rewrite the code first**, update the § to describe the cleaner shape, and ship both in the same arc (same commit when small, separate commits when larger — but in the same session).
   - If the user declines the rewrite (intentional complexity: perf hot-path, platform quirk, legacy constraint), write that *reason* into the § as the "why". A § that says "this looks gnarly because X" is fine; a § that is gnarly without acknowledging the gnarliness is not.

   Signs the § is telling you the code needs rewriting, not that your prose needs tightening:
   - The § needs a flowchart just to describe one method's control flow.
   - Two sub-sections describe behaviour that is "the same but for case Y" — the code probably has near-duplicates that could unify.
   - A `why` paragraph cannot find a single coherent constraint — the shape accreted without intent.
   - You find yourself documenting code that is obviously unreachable, unused, or shadowed by a later code path.
   - An invariant you want to state cannot actually be stated as a single sentence because too many code paths can violate it.

   Docs-first is also code-quality-first: the documentation round is one of the cheapest rewrite triggers available, because the cost of noticing is already paid.

This rule binds every code edit **and every plan**, not just "big" ones. "Forgot to check docs", "the docs didn't say", "the related § was hidden", "the link broke because I renamed the target", "the gap wasn't blocking me", and "the code was ugly but technically worked" are all invalid reasons to skip a step: step 1 names the TOC + nav, step 2 names the remedy when the nav points at an empty answer, step 5 names the remedy when cross-references are missing, step 6 names the remedy when you yourself moved the target, step 7 names the remedy when the gap is noticed outside the critical path, and step 8 names the remedy when the docs just taught you the code is wrong.

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
| Changed persistence format (drift schema column/table change) | Update [§11 Persistence](ARCHITECTURE.md#11-persistence--storage) — drift `MigrationStrategy.onUpgrade` step + schemaVersion bump |
| Changed wire format of a persisted file (`config.json`, `credentials.kdf`, hardware-vault blob, `.lfs` archive) **or** added a new envelope artefact | Update [§3.6 → Migration framework → Developer guide](ARCHITECTURE.md#developer-guide--how-to-ship-a-format-change) — bump `SchemaVersions.<x>`, ship a `Migration`, register it in `buildAppMigrationRegistry()` (or `archiveMigrationRegistry`), and add the chain test |
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
3. **Optional OS dep with graceful degradation** — last resort. **⚠ This rung explicitly permits an end-user install step** (copy-pasteable README snippet) for the *optional extra*, provided the core app still works without it. "End-user installs nothing" headline elsewhere in the docs means the core app must launch without setup — it does *not* forbid an optional platform-only upgrade that the user chooses to enable via a documented one-liner. Allowed only if all three hold:
   - The app detects the missing dep at runtime and shows a **short** localized message stating either "X is unavailable on this platform" or "X is unavailable because Y is not installed" — one line, no stack trace, no silent failure, no install commands or links inside the UI (those live in the README).
   - The corresponding control on configuration surfaces is rendered as **disabled with a tooltip carrying the same short reason** (per [§ UI Components → Disable vs hide](#ui-components)), not hidden — the user must see the option exists and why it's off.
   - `README.md` "Installation" lists the copy-pasteable install command per platform that needs it. The UI does not duplicate that text — users who want detail go to the README.

   **Canonical example — Linux biometric unlock.** Fingerprint access on Linux is gated by `fprintd`, a system D-Bus daemon that cannot be shipped as a bundled library (rung 1 fails). Master-password remains the core unlock path whether `fprintd` is present or not (rung 2 is satisfied — the app works without the dep). Rung 3 applies: the Settings biometric toggle is rendered disabled with `fprintd not installed / no enrolled finger` reason when absent, and README's Linux Installation section carries the per-distro snippet (`sudo apt install fprintd …` / `sudo dnf install fprintd …` etc.). Users who want the upgrade run the snippet; everyone else sees an honest disabled row and uses master-password.

Hard-requiring the user to install anything **to launch the core app** (a runtime, a service, a CLI, a native lib) is **forbidden**. Optional platform-only upgrades that meet the three conditions above are not "hard-requiring" — they are the rung-3 escape hatch. If a proposed dependency can't satisfy one of the three rules above, redesign the feature or drop it.

When reviewing a diff that adds a new dependency: check `pubspec.yaml`, then check whether the dep pulls a transitive native requirement (look at the dep's README + `linux/`, `macos/`, `windows/`, `android/`, `ios/` plugin folders). If yes — verify the rule above before approving the change.

### Fallbacks Are Last Resort, Not Default

A weaker code path is a **downgrade of the guarantee**, not a neutral alternative that just needs a label. The ladder when a feature's primary path is unavailable on a platform:

1. **Bundle** (per § Self-Contained Binary above) — if the capability can ship inside the app, ship it. No fallback needed.
2. **Implement per platform** — if a native implementation that meets the bar is achievable at reasonable cost-per-user-served, build it. Authorisation per [§ Don't Escalate Working Baselines](#dont-escalate-working-baselines).
3. **Honestly hide** — if the platform cannot meet the bar at any reasonable cost (no unified API, fragmented drivers, vendor matrix too wide — Linux biometric binding is the canonical example), render the control as **disabled with a reason** (per [§ UI Components](#ui-components)). A hidden-but-honest "Not available on Linux" row is **better** than a weaker path that looks strong.
4. **Weaker path with honest label** — a materially weaker code path (e.g. software-gated where another platform has hardware-gated) is acceptable only when (a) the ladder above has no better answer, (b) the weaker path still delivers non-trivial value on its own, and (c) the UI states exactly what the user got — e.g. labels like `Software-gated`, `DPAPI (software-backed)`, `Keyring (no biometric binding)`. **Never label a weaker path with the same words as the stronger one.**

"No silent fallbacks" (phrased in `SECURITY_BACKLOG.md` cross-cutting ground rules and elsewhere) is the last clause of this rule, not the whole of it. The full rule is: *a fallback that ships without a visible downgrade label is forbidden, **and** a fallback that ships instead of a feasible stronger path is forbidden — label or no label.* "We can just label it" is not a justification for picking a weaker path when a better one is achievable.

**Red flag when reading a proposed diff:** a fallback that is presented as "it's fine, we tell the user" without the ladder above being walked. Walk the ladder. If rungs 1–3 were dismissed, the dismissal reasoning must be in the diff's commit message or the backlog entry, not implicit.

### Native Over Dart When Better (and Zero-Install)

When a feature can be implemented either in pure Dart (`dart:ffi` against a runtime lib, a pub.dev package wrapping a protocol like D-Bus, etc.) **or** as a native platform plugin (Kotlin / Swift / Objective-C / C / Rust exposed via `MethodChannel` or `FFI`), **prefer the native path when it is measurably better on at least one of these axes**:

- **Performance** — runtime speed, startup latency, memory, battery, binary size.
- **Functionality** — the native path unlocks capabilities the Dart path simply cannot reach (direct access to an OS-provided hardware binding, a full biometric prompt with custom allow-fallback behaviour, a framework that has no Dart equivalent — Windows Hello `KeyCredentialManager`, Android `BiometricPrompt.CryptoObject`, iOS `SecAccessControl` flags the flutter-plugin wrapper doesn't expose, etc.).
- **Integration depth** — hooks into OS lifecycle / IPC / sandboxing that Dart packages wrap thinly or not at all.

"Better" means a concrete user-facing benefit the Dart path cannot match at reasonable cost — not a stack-preference argument. **The decision must still satisfy [§ Self-Contained Binary](#self-contained-binary--end-user-installs-nothing) at rung 1 or 2 (end-user installs nothing by hand to launch the core app).** If the native path would push the feature into rung 3 (README snippet for a lib the user has to install), **stop and ask the user first** — the trade-off between "pure-Dart with fewer deps" and "native with better capability/perf but an optional install step" is a user call, not an agent call. Record the authorization (a "yes, do it" in the session or backlog entry) before writing the native path.

Pure Dart / FFI / pub.dev-package is the right default when:
- performance + functionality parity with native is good enough for the use case (majority of settings UI, config, light file I/O, glue code);
- the native path would add N per-platform codepaths without a clear per-user win;
- iteration speed matters more than marginal runtime — ship Dart first, benchmark, promote to native only if the numbers or a missing capability say it matters.

When the decision is live (an authorized feature that could go either way), write the choice + the "why native" or "why Dart" into the commit message or the relevant backlog entry so future agents can see the reasoning instead of re-litigating it. Do **not** silently default to Dart because it is the shorter diff, and do **not** silently default to native because native is shinier.

**Interaction with [§ Don't Escalate Working Baselines](#dont-escalate-working-baselines):** that rule blocks *unsolicited* escalation from a working Dart baseline to a native one. This rule is about choosing the implementation path for a feature the user has already authorised — once the work is greenlit, native-when-better-and-zero-install is the default, not a rewrite proposal.

### Don't Escalate Working Baselines
The project ships across 5 platforms with **deliberately uneven guarantees** in many domains — credential storage, file pickers, notifications, biometrics, IPC, native UI affordances, hardware probes, you name it. Cross-platform packages typically cover the majority of users with known, documented limits on the weaker platforms. The project treats that asymmetry as the **chosen baseline**, not a deficiency to fix. The cost of N parallel native code paths (N× test surface, N× release fragility, N× maintenance) is rarely worth a marginal upgrade on one or two platforms.

**Scope of this rule — read carefully, this is where agents usually trip:**
This rule governs **unsolicited** agent proposals. It does **not** block work the user has already authorized. If the user has put a per-platform upgrade in the backlog, in a plan, in an earlier message this session, or in a direct "yes, do it" reply, that upgrade is **authorized** and the red-flag checks below do not apply to it — just execute. The rule exists so an agent does not invent a three-day native-plugin refactor in response to "fix the typo" — not so the agent second-guesses work the user already asked for.

Before invoking this rule, check: *did the user ask for this per-platform upgrade, now or in a prior plan message?* If yes — proceed. If no, apply the rules below.

Rules for **unsolicited** agent proposals on working baselines:
1. **Don't escalate.** When an existing solution covers most platforms with known limits, leave it alone. The asymmetry is a feature of the budget, not a bug in the design.
2. **Document the gap, don't fill it with code.** If you spot a missing capability, propose adding a row to the relevant per-platform table (`SECURITY.md`, [ARCHITECTURE §12 Platform-Specific](ARCHITECTURE.md#12-platform-specific-behavior), [§13 Security Model](ARCHITECTURE.md#13-security-model)). Don't open a refactor.
3. **Treat phrases like "true X", "real X", "verified X", "proper X" as red flags** when *you* feel tempted to use them to re-pitch a working feature. They almost always translate to "more code, more rope". Ask the user whether the upgrade is wanted before designing it — and if the user has already said yes in this or an earlier session, that ask is already answered.

The default is: leave the working baseline alone unless the user has authorized the upgrade. Once authorized, the upgrade is first-class work — design it, test it, ship it, same as any other feature.

This is a **caveat on** [§ Self-Contained Binary](#self-contained-binary--end-user-installs-nothing) — that section's preference order ("bundle > fallback > optional dep") applies to **new** features. It is **not** a mandate to retroactively replace working optional-dep solutions with bundled or per-platform equivalents *without user authorization*. OS-specific native code is fully acceptable once the user has asked for it, provided the end-user still installs nothing (see Self-Contained Binary rules 1 & 2).

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
- **Dialogs** — `AppDialog` for all modal dialogs. Never use bare `AlertDialog`. Complex dialogs: compose from `AppDialogHeader`/`AppDialogFooter`/`AppButton`. Progress: `AppProgressDialog.show()`. Exception: mobile touch buttons keep `Material`+`InkWell` for ripple
- **Text selection is opt-in on desktop — clickable ≠ selectable.** No global `SelectionArea` wraps the desktop shell — an earlier global wrap broke `ThresholdDraggable` because `SelectionArea`'s `TapAndDragGestureRecognizer` claimed pan ahead of `MultiDragGestureRecognizer`. Wrap specific prose surfaces in `AppSelectionArea` locally: dialog bodies (already wrapped inside `AppDialog`), threat lists, release-notes bodies, help prose. Never wrap a container that also hosts a drag target, `AppButton`, or interactive row. Mobile keeps one `AppSelectionArea(child: MobileShell())` — touch drag recognisers arbitrate differently. **Rule inside any scoped `AppSelectionArea`: every clickable tile / row / header / badge opts out via `SelectionContainer.disabled` on its child** — `HoverRegion` already auto-wraps when a gesture callback is bound; `InkWell` does not, so wrap its child explicitly (see `expandable_tier_card.dart`, `app_data_row.dart`, `tier_threat_block.dart`). In `_SettingsRow` the label + subtitle block opts out too so Data and Transfer sections read the same way — form field labels are not "content to copy". Non-clickable prose (threat rows, descriptions) stays selectable with the I-beam cursor. The guard is load-bearing: when clickable text stays selectable, the `InkWell` click cursor wins over the Selectable text cursor, and users see "half-broken UX — selectable but wrong cursor" — [§6 Widgets API → Selection scoping](ARCHITECTURE.md#selection-scoping)
- **Session panel shortcut / focus / clipboard contract** — shortcut dispatch uses `CallbackShortcuts` (not `Focus.onKeyEvent`), empty-sidebar tap clears the focused pointer but keeps the `FocusNode` focused, folder click is two-phase (focus → toggle), paste resolves its target lazily at paste time, clipboard holds a session id pointer (no TTL, no RAM copy). [§5.3 Session Manager UI → Session panel input model / Session clipboard](ARCHITECTURE.md#53-session-manager-ui-featuressession_manager)
- **Text overflow protection** — localized text in `Row` or fixed-width — wrap with `Flexible`/`Expanded` + `overflow: TextOverflow.ellipsis`. For label columns use `ConstrainedBox(maxWidth:)` instead of fixed `SizedBox(width:)`
- **Accessibility** — wrap interactive list items (session rows, file rows) and panel headers with `Semantics` widget. Use `label` for screen reader text, `button: true` for tappable items, `selected` for selection state, `header: true` for section headings. `StatusIndicator` includes built-in `Semantics`
- **Disable vs hide unavailable controls — depends on surface type.** On *configuration surfaces* (Settings, session-edit forms, preference dialogs), always render the control as **disabled with a tooltip + tap-toast explaining the reason** — never hide it. The user is exploring what the app can do and needs to know the option exists (cross-device install, missing hardware, missing prerequisite). On *action surfaces* (lock screen, context menus, per-row action buttons, action dialogs), **hide** unavailable actions — the user is trying to do a specific task and a greyed button is noise, not information. Disabled state must visibly affect the whole row (opacity on the full container), not just the trailing knob
- **Prefer shared components** — full rule in [§ Reuse First](#reuse-first-project-wide-not-just-ui)

### Localization (i18n)
All user-facing strings MUST use `S.of(context).xxx`. Never hardcode strings in widgets — treat this as a bug. Add keys to `lib/l10n/app_en.arb`, run `flutter gen-l10n`, use `S.of(context).newKey`. Exceptions: constructor defaults (no context), log messages, `_AlreadyRunningApp`. Tests must include `localizationsDelegates: S.localizationsDelegates, supportedLocales: S.supportedLocales` in every `MaterialApp`. See [§8.1 i18n](ARCHITECTURE.md#81-internationalization-i18n)

### Localization Tone — Native IT Register, Not Dictionary Calques
Audience is engineers and sysadmins. Strings must read like a dev explaining to a colleague, not a textbook, not machine-translated output. Two rules, both mandatory.

**1. Technical terms follow each locale's real IT register — not a mechanical "keep English" rule.**

The goal is: write what a native-speaking senior dev would actually type to a colleague. Calques of English compounds into native words almost always read amateur, but over-Latinizing a locale that normally transliterates (JA katakana, KO hangul, ZH Apple consumer terms) also reads off. Rough per-locale guide:

| Locale | Dominant pattern for tech terms |
|---|---|
| RU | Latin for tech (SSH, keychain, hardware, wrapped key). Prose Russian. |
| ES, PT-BR, FR, DE, IT | Latin for dev-tool tech (SSH, Keychain, Hardware, Log, Timeout, Worker, Fingerprint, Passphrase, Scrollback, Release, rate limit). Apple / MS consumer-UI natives (trousseau, Schlüsselbund, llavero) OK only for macOS-specific labels, not dev-tool chrome. |
| TR, ID | Heavy English in dev context. TDK / KBBI / öztürkçe / baku calques read textbook. |
| AR, FA, HI, VI | Latin tech terms inside native prose is normal. Native coinages for SSH/TPM/keychain/forensics/wrapping sound amateur. |
| JA | Katakana (キーチェーン, ハードウェア, スナップショット) for loan words; Latin (SSH, TPM, DMA, CVE, Argon2id) for acronyms. Mirror how native JP dev docs write. |
| KO | Hangul transliteration (키체인, 하드웨어) or Latin — both valid. Match native dev doc convention. |
| ZH | Latin for protocols/acronyms always (SSH, TPM, DMA, CVE, TLS). Common words translate (硬件, 密码). Apple term 钥匙串 OK but `keychain` Latin also works in dev tools. |

**Anti-patterns seen across locales — never do these:**
- Coin a native word for "keychain" when native devs don't use one (RU ключница, VI chuỗi khóa, FA کلیدستان / جاکلیدی, KO 열쇠고리, ZH 钥匙链 as an invented new compound — amateur).
- Translate Unix "pipe" as literal water pipe (RU труба, PT Pipa, TR Boru, AR أنبوب, HI पाइप-as-plumbing, VI Ống, ID Pipa — canonical POSIX error `Broken pipe` is recognized verbatim).
- Translate "worker" as human laborer (PT Trabalhadores, AR العمال, TR İşçi, HI मज़दूर, VI công nhân, ID Pekerja — evokes factory, not concurrency).
- Translate "Paranoid" (tier codename) as psychiatric diagnosis (AR جنون الارتياب, VI Hoang tưởng, KO 편집증 alone without qualifier, FA وسواسی, ES Paranoico — tier names stay English/parenthesized).
- Translate "forensics" as legal/courtroom term (RU криминалистика, PT Perícia, FA جرم‌یابی, AR تحليل جنائي — use "memory dump / RAM dump / RAM forensics" instead).
- Translate "wrapped key" / "sealed blob" as literal wrapping/sealing native idioms (AR المفتاح الملفوف = cabbage roll, ZH 被包装的 = gift-wrapped — keep `wrapped key` / `sealed blob` Latin or use `封装/umhüllt/empacotada`-style crypto-register verb).
- Translate SSH "fingerprint" with biometric word when the app also has biometric auth (ES Huella digital, PT Impressão digital, TR Parmak izi — this collides with biometric-unlock UI in the same screen).

**2. Prose reads as living language, not as word-for-word English grammar.**

- Use action verbs, not noun piles.
- No word-for-word copy of English sentence structure.
- Short sentences > long participle/relative chains.
- No "please" in error messages (RU пожалуйста, ES Por favor, PT Por favor, JA ください-inflation, TR lütfen — drop all).
- No Apple-sir / keigo / ustedeo register inflation beyond what the locale's real dev UIs use.
- Do not mix dialects (PT BR vs PT PT `ficheiros`/`arquivos`; ES tuteo vs ustedeo; DE du vs Sie) — pick one per file and hold.
- Do not use different translations for the same English term in the same file (every audited locale showed this: 3–5 renderings of `keychain`, mixed `log`/`registro`, `Paranoid`/`Paranoico`, `tier`/`kademe`/`katman`/`cấp`/`lớp`, etc.). Pick one term → use everywhere.

**Critical semantic-inversion traps observed** (fix these wherever they appear):
- ES `restablecida` / PT `redefinida` for "connection reset by peer" — both mean `re-established` / `redefined`, opposite of `reset`. Use `reiniciada por el peer` / `encerrada pelo peer`.
- KO `암호문` for "passphrase" — 암호문 means `ciphertext` in crypto. Use `패스프레이즈`.
- JA `解錠` for "decrypt/unwrap" — 解錠 is picking a physical lock. Use `復号`.
- JA `ボルト` for "vault" — ボルト is bolt/volt. Correct is `ボールト`.
- HI `समझौता` for "compromise" — means `agreement/deal`. Use `कॉम्प्रोमाइज़` or rephrase.
- FR `sauvegardé` for "backed by" — false friend, means `backed up (to backup)`. Use `adossé à` / `reposant sur`.

**Self-test before shipping a string:** read it aloud in your head. If it sounds like a textbook or a machine-translation glossary entry → rewrite. If it sounds like a message you'd send a colleague in Slack → ship.

**Do localization work yourself — do not delegate translation to sub-agents.** Sub-agents get a short context brief and miss the conversation register, the user's feedback on prior strings, the per-locale norms already established in this project, and the decisions made earlier in the session. They fall back to "safe" dictionary calques — the exact failure mode we are trying to avoid. Survey-style use (read the 1000-line file, flag candidates) is acceptable; the actual tone decisions and rewrites stay in the main thread.

**Watchlist — terms that routinely get miscalqued** (keep English / native IT form unless the locale's dev community genuinely uses a native equivalent):
SSH, SFTP, SCP, TLS, DNS, proxy, TCP, known_hosts, TPM, TEE, DMA, Secure Enclave, StrongBox, HSM, keychain, keyring, Keystore, Credential Manager, key material, wrapped key, sealed blob, KDF, PBKDF2, Argon2id, AES, HMAC, AEAD, passphrase, fingerprint (disambiguate from biometric), host, host key, port, login, logging/log, worker, scrollback, release, timeout, keep-alive, rate limit, backdoor, plaintext, snapshot, forensics, dump, probe, breaking change, driver, distro, config, credential, slot, vault, kernel, build, runtime, mitigation, lockout, idle.

### Diagrams in Docs — Mermaid, Not ASCII Box-Art
Every diagram in `docs/**/*.md`, `README.md`, `SECURITY.md` and any other git-tracked markdown MUST be a ` ```mermaid ` fenced block (`flowchart`, `stateDiagram-v2`, `sequenceDiagram`, `classDiagram`, etc.). GitHub renders these as SVG; plain ASCII `┌─┐`/`└─┘` box-art gets dumped as monospace and breaks on narrow viewports — do not write new ones. When editing an existing ASCII diagram, convert it to Mermaid in the same commit.

**Scope — what this rule covers:**
- **Diagrams** (nodes + arrows, layered boxes, state graphs, flows) → Mermaid.
- **Single-box info cards** (just "here are the fields of this object") → plain markdown bullets, not a box.

**Scope — what this rule does NOT cover:**
- **Directory trees** (`├── core/` / `└── utils/`) — keep as plain fenced blocks. They read fine in monospace and Mermaid is worse for deep trees.
- **Pipe tables** (`| col | col |`) — GitHub already renders these as HTML tables; leave them alone.
- **Code blocks** (`` ```dart ``, `` ```bash ``, output dumps) — unchanged.

The raw-text trade-off is accepted: a Mermaid source block is readable as a node+edge listing in `cat`/`less`/IDE, the SVG is the GitHub-web benefit. Do not add ASCII "fallbacks" via `<details>` — that doubles the source and rots under edits.

### Plan-Item IDs Stay Internal
Plans, session notes, backlogs, internal docs live **outside git** (`~/.claude/plans/*`, `SECURITY_BACKLOG.md`, `~/.claude/projects/*/memory/*`, etc.). Never reference their identifiers — `P1.2-*`, `A1`, `D1`, `Phase E1`, `Phase G1`, `Phase F2`, `Task 3.2`, and anything of that shape — in any file that lands in `git`:

- Commit titles and bodies
- Code comments and docstrings
- Filenames and section headers
- `README.md`, `ARCHITECTURE.md`, `SECURITY.md`, `CLAUDE.md`, `AGENT_RULES.md`, `CONTRIBUTING.md`, `CHANGELOG.md`
- Any other tracked artefact

If a commit needs to explain "why this change came with that change", describe the reason **prose-wise**: `"ships alongside the overlay methods added to the native plugins"` — not `"wraps up Phase D1"`. Plan IDs are an internal shorthand for in-session tracking only; readers of git history have no access to that context, and any ID reference ages into noise the moment the plan is superseded.

**Review check:** before staging, grep your diff for `/P[0-9]/`, `/Phase [A-Z][0-9]/`, `/Task [0-9]/`, `/[A-Z][0-9] /` — false positives are cheap, leaked IDs are forever.

## Code Quality — SonarCloud

All code must follow **Effective Dart** and pass `dart analyze` with zero issues. `make analyze` must pass before every commit that touches Dart code. **Never suppress** — `// ignore:`, `// NOSONAR`, `@SuppressWarnings` are forbidden, always fix the root cause.

**Skip manual `make analyze` / `make test` when the staged diff is doc-only** (Markdown, `.arb` strings that are also propagated to `app_localizations_*.dart`, images, READMEs, rule files under `docs/`). The pre-commit hook still runs `make check` automatically — running it manually first wastes time and slows the loop. The quick test: if `git diff --name-only --cached | grep -E '\.dart$|pubspec\.yaml'` returns nothing, skip the manual analyzer/test pass and let the hook do its job at commit time.

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

**Everything that can be unit-tested without touching the OS or an external system must be unit-tested.** The inverse is the allow-list for "no unit test": a function is exempt only when it fundamentally requires an OS-specific capability (biometric prompt, OS keychain, native plugin MethodChannel, platform file pickers, single-instance lock, notification APIs, TPM / Secure Enclave / Windows Hello, Linux D-Bus services like `fprintd`) or an integration with an external system (real SSH / SFTP server, real QR camera, real update server, real Dependabot / CI). For exempt functions, the harness-testable **slice** around them still gets tests — isolate the pure-Dart logic (argument validation, shape of the call, post-processing of the return value, error mapping) from the non-testable edge, and test that slice. "I can't test the OS-specific call" does not extend to "therefore I skip tests for this whole file".

Target: 100% coverage (excluding the OS-specific / external-integration edges named above, and integration tests / tests on the actual platform). One test file per source file. Testable by design: extract pure logic from SSH / platform / I/O deps, DI over hardcoded `ref.read()` — [§14 Testing Patterns](ARCHITECTURE.md#14-testing-patterns--di-hooks). If a function cannot be unit-tested and the reason is **not** on the allow-list above, the fix is to refactor until it can be — not to ship without coverage.

- **Tests assert spec, not current output.** Before writing any `expect(...)`, state in one sentence what the function _should_ do for that input — derived from the feature's intent, not from running the code and copying the result. **Never** run the function, observe the output, and paste it into `expect(...)` as the oracle — that's a pinning test and it cements bugs instead of catching them. This applies doubly to parsers, formatters, `localizeError`, and anything touching untrusted input. If the correct behavior is genuinely unclear, stop and ask the user rather than inventing an oracle.
- **When test and code disagree, surface it — don't silently "fix" either side.** If your derived spec says X and the code returns Y, you have one of three situations: (1) real bug in code, (2) wrong spec on your side, (3) ambiguous requirement. You cannot tell which from inside the test file. Stop, report the disagreement to the user with: the input, the spec you derived + where you derived it from (commit, docstring, user-facing string, issue), and the current output. Let the user decide which side is wrong. Only after confirmation: fix code **or** update the spec. A confident "I found a bug, fixing it" on an edge case is exactly how correct behavior gets quietly regressed.
- **Uncovered lines are a marker, not a target.** An uncovered line means "no test verifies the behavior this line implements" — it does NOT mean "write anything that touches this line". Do not write tests whose only goal is to execute the line (calling the function with arbitrary input and `expect(result, isNotNull)` / `isA<T>()` / "doesn't throw"). Ask first: what branch, decision, or contract does this line encode? Write a test that fails if that contract breaks. If you cannot articulate the contract, the line either needs refactoring (the logic is too implicit to test) or a user conversation (you don't understand it yet) — not a coverage-hit wrapper.
- **Fuzz tests for every untrusted-input consumer** — not only parsers. Any function that decodes or validates bytes / strings / maps from outside the app must have a corresponding fuzz target. "Outside" is a tier:
  - **User-supplied files** — import flows (`.lfs` archive, OpenSSH config, known_hosts, PEM key bundles), wizard / dialog text input that feeds a validator, clipboard paste that's parsed.
  - **Network / peer-supplied** — SSH server banner, SFTP path strings, terminal ANSI escape parser (handled by upstream xterm, but our post-processing is ours).
  - **Inter-process** — deep-link URIs, QR payload, OS clipboard, IPC messages.
  - **On-disk state** — config JSON, session JSON, KDF params blob, LFS archive header, biometric vault blob, keychain-stored opaque blobs.
  
  Each target gets either a Dart property-based test in `test/fuzz/` (for logic that has Flutter / pub deps) or a standalone harness in `fuzz/` + seed corpus + CFL wiring in `.clusterfuzzlite/build.sh` (for coverage-guided libFuzzer runs on pure-Dart-compileable logic). New untrusted-input code = new fuzz target in the same commit. See [§14 Fuzz testing](ARCHITECTURE.md#fuzz-testing).
- **UI changes = test updates** — proactively update all tests that reference changed widget names, labels, or finders.

## Commits & Versioning

- **Agent does not commit or push unless the user explicitly asks.** "commit" = commit only, "commit and push" = commit + push.
- **HARD STOP between fixes** — implement fix → write tests → update docs → **stop and ask user to commit**. Do NOT start the next fix until the current one is committed. **Exceptions:**
  - The user signals batch mode — "fix all and push", "don't ask", "go through the plan", "stop asking", or the same intent in any language. Execute end-to-end without pausing between fixes.
  - A series of related doc, rule, or convention edits in a single session — batch into **one** commit at the natural end of the arc instead of firing `/commit` after every sub-chunk. Individual doc chunks each "complete on their own" do not warrant individual commits when the user is mentally treating the whole arc as one pass.
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
