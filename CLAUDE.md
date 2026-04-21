# LetsFLUTssh — Development Guide

LetsFLUTssh — lightweight cross-platform SSH/SFTP client (Dart/Flutter, all 5 desktops + mobile). Open-source alt to Xshell/Termius. **Solo developer project.**

## Documentation Map

- **[`docs/AGENT_RULES.md`](docs/AGENT_RULES.md)** — all rules, conventions, doc-maintenance checklist, code-quality, testing methodology, commit/release flow. Read on demand via the navigation tables below — never cover-to-cover.
- **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** — module structure, APIs, data flows, design decisions. 3000+ lines — never read cover-to-cover, jump to specific § via [AGENT_RULES nav](docs/AGENT_RULES.md#within-architecturemd).
- **[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md)** — build instructions, code style (for humans).

---

## Action → Read This (mandatory before acting)

| I'm about to... | MUST read first |
|---|---|
| Plan or edit code in any module (before drafting the plan or opening the file) | [AGENT_RULES § Docs First](docs/AGENT_RULES.md#docs-first--read-before-fix-drift-update-after) — pick the mapped § from the TOC, fetch only it (Read with offset+limit or `/doc` skill); never read `ARCHITECTURE.md` cover-to-cover; fix code-doc drift in the same commit |
| Write/edit any Dart code | [AGENT_RULES § Code Quality — SonarCloud](docs/AGENT_RULES.md#code-quality--sonarcloud) + [§ Conventions](docs/AGENT_RULES.md#conventions) |
| Call API of an external package (dartssh2, drift, riverpod, xterm, …) | [AGENT_RULES § External Libraries & APIs](docs/AGENT_RULES.md#external-libraries--apis--look-up-dont-guess) — never guess signatures: grep repo → Context7 → web docs → pub-cache source |
| Add a new dependency or feature needing an OS capability | [AGENT_RULES § Self-Contained Binary](docs/AGENT_RULES.md#self-contained-binary--end-user-installs-nothing) — bundle > fallback > optional-with-docs (rung 3 permits opt-in end-user install) |
| Choosing between pure-Dart (FFI / pub.dev pkg) and a native plugin (Kotlin / Swift / C / Rust) for an authorized feature | [AGENT_RULES § Native Over Dart When Better](docs/AGENT_RULES.md#native-over-dart-when-better-and-zero-install) — prefer native when it is measurably better on perf / functionality / integration depth **and** zero-install holds. If native would require an opt-in install, ask the user first |
| About to propose a per-platform native rewrite of a working feature | [AGENT_RULES § Don't Escalate Working Baselines](docs/AGENT_RULES.md#dont-escalate-working-baselines) — **first check: has the user already authorized this upgrade (plan, backlog, earlier message)? If yes, just execute.** The rule blocks UNSOLICITED escalations, not user-requested work |
| Write/update a test | [AGENT_RULES § Testing Methodology](docs/AGENT_RULES.md#testing-methodology) + [ARCHITECTURE §14](docs/ARCHITECTURE.md#14-testing-patterns--di-hooks) — everything that doesn't need the OS or an external system must be unit-tested; refactor around the edges rather than skip |
| Add/change a user-facing string | [AGENT_RULES § Conventions → Localization](docs/AGENT_RULES.md#localization-i18n) — **all 15 `app_*.arb` files** must be updated |
| Add a new widget / helper / mixin / style constant / store | [AGENT_RULES § Reuse First](docs/AGENT_RULES.md#reuse-first-project-wide-not-just-ui) — grep shared modules before creating |
| Add/change a UI control | [AGENT_RULES § Reuse First](docs/AGENT_RULES.md#reuse-first-project-wide-not-just-ui) + [§ UI Components](docs/AGENT_RULES.md#ui-components) (disable-vs-hide) |
| Touch theme / fonts / radii / heights | [AGENT_RULES § Theme & UI Constants](docs/AGENT_RULES.md#theme--ui-constants) — never hardcode |
| Add a new file/class/widget/provider in `lib/` | [AGENT_RULES § Doc Maintenance](docs/AGENT_RULES.md#documentation-maintenance-checklist) — find the row, update the named ARCHITECTURE § |
| Change the wire format of a persisted file (`config.json`, `credentials.kdf`, hardware-vault blobs, `.lfs` archive contents) **or** add a new envelope artefact | [ARCHITECTURE §3.6 → Migration framework → Developer guide](docs/ARCHITECTURE.md#developer-guide--how-to-ship-a-format-change) — bump `SchemaVersions`, ship a `Migration`, register it in `buildAppMigrationRegistry()` (or `archiveMigrationRegistry`), test the chain. **Drift intra-DB schema changes** (add/rename column, new table) follow the separate drift `MigrationStrategy` flow in [§11 Persistence](docs/ARCHITECTURE.md#11-persistence--storage) |
| Add/edit a diagram in `docs/*.md` / `README.md` / `SECURITY.md` | [AGENT_RULES § Diagrams in Docs](docs/AGENT_RULES.md#diagrams-in-docs--mermaid-not-ascii-box-art) — Mermaid only, no ASCII box-art |
| Write a commit message | [AGENT_RULES § Commits & Versioning](docs/AGENT_RULES.md#commits--versioning) + [§ Plan-Item IDs Stay Internal](docs/AGENT_RULES.md#plan-item-ids-stay-internal) |
| Open a PR / merge to main | [AGENT_RULES § Branching & Release Flow](docs/AGENT_RULES.md#branching--release-flow) |
| Find something in ARCHITECTURE.md | [AGENT_RULES § Quick Navigation → Within ARCHITECTURE.md](docs/AGENT_RULES.md#within-architecturemd) |

---

## Always-On Rules (gate every action)

These apply to every response without re-reading:

- **Don't commit or push unless the user explicitly asks.** "commit" = commit only, "commit and push" = commit + push.
- **HARD STOP between fixes** — implement → tests → docs → **ask to commit**. Don't start the next fix until current is committed. Overrides: (a) user signals batch mode ("fix all and push", "don't ask", "go through the plan", "stop asking", or the same intent in any language) → batch end-to-end; (b) series of related doc/rule/convention edits in one session → one commit at the arc's end, not per chunk.
- **Default branch is `dev`.** Never push to `main` directly.
- **All files in English only** — code, comments, commits, docs.
- **No plan-item IDs in public artifacts** — no `P1.2-*` / `Phase E1` / `Task 3.2` in commits, code, filenames, or any tracked doc. Full rule: [AGENT_RULES § Plan-Item IDs Stay Internal](docs/AGENT_RULES.md#plan-item-ids-stay-internal).
- **Never suppress issues** — no `// ignore:`, `// NOSONAR`, `@SuppressWarnings`. Fix root cause.
- **Never amend after push** — new commits only. Amend OK only before first push.
- **Don't install packages without asking.** Latest stable only — no beta/dev/pre-release.
- **End-user install is opt-in, never forced** — core app launches with zero manual setup; platform-only extras are allowed only via the 3-rung ladder (bundle > fallback > optional-with-disabled-toggle + README snippet). Full rule: [AGENT_RULES § Self-Contained Binary](docs/AGENT_RULES.md#self-contained-binary--end-user-installs-nothing).
- **Always build via Makefile** — `make run/build-linux/test/analyze`. Never call `flutter` directly.
- **Skip `make analyze` / `make test` for doc-only commits** — if the staged diff touches no `.dart` files and no `pubspec.yaml`, don't run analyzer or tests manually. The pre-commit hook runs `make check` automatically; running it first on a Markdown-only change is wasted loop time.
- **Cross-platform verification** — Android change → also iOS; Windows change → also Linux + macOS.
- **Best practices by default** — push back on hacky solutions, propose best-practice alternatives.
- **Think systemically** — consider full scope and side effects, not just the literal instruction.
- **Ask before guessing UI placement** — if ambiguous, ask once upfront.
- **Every change ships with docs + tests + translations** — incomplete commit otherwise.
- **Docs first — the highest-priority discipline, binds planning and editing both.** Docs are a first-class deliverable, not a byproduct. Every § must cover both *how it works* (mechanism, states, invariants, failure modes) **and** *why it is that way* (rationale, constraint, rejected alternative). Before any plan or edit: consult the TOC ([AGENT_RULES § Within ARCHITECTURE.md](docs/AGENT_RULES.md#within-architecturemd) or the TOC at the top of `docs/ARCHITECTURE.md`), pick the specific § that maps to the module, fetch only that § (via `Read offset+limit` or the `/doc` skill helper — `.claude/skills/doc/SKILL.md`). **Never read `docs/ARCHITECTURE.md` cover-to-cover; never `Read` it without `offset`+`limit`.** Widen via cross-links (another narrow fetch), never via a full-file Read. Then:
  - **§ does not cover your case / ambiguous** → read the code, resolve it, write the answer back into the § in the same commit (include both *how* and *why*).
  - **Drift** → fix the § to match reality, also in the same commit.
  - **Writing/updating a §** → cross-link every related § you mention (docs are a graph, not a stack).
  - **Rename / move / delete a § or anchor** → grep the repo for the old anchor and fix every inbound link in the same commit — `CLAUDE.md`, `AGENT_RULES.md` nav tables, `ARCHITECTURE.md` TOC + in-file refs, `README.md`, `SECURITY.md`, docstrings, memory index.
  - **Noticed a doc gap even outside the current task** (under-documented behaviour, missing rationale, "how" without "why", magic numbers without explanation) → extend the § proactively. You do not need permission to write more docs; thinning them is what requires justification.
  - **Writing the § revealed that the code is too complex / tangled / redundant / inefficient** → surface it to the user, propose a rewrite before finalizing the §. Tortured prose describing tortured code is a design signal, not a writing problem. Docs-first is also code-quality-first.
  - **Audience — human first, always.** `ARCHITECTURE.md`, `README.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md` and other git-tracked docs are written for humans. Agent-specific guidance lives in `CLAUDE.md` / `AGENT_RULES.md` / `~/.claude/...` — never leak LLM asides into the human-facing docs.

  Full rule: [AGENT_RULES § Docs First](docs/AGENT_RULES.md#docs-first--read-before-fix-drift-update-after).
- **Parallel agents** — only `git add` files YOU changed. Do NOT run tests — testing is the main process's job.
