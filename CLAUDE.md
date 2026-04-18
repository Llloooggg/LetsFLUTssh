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
| Write/edit any Dart code | [AGENT_RULES § Code Quality — SonarCloud](docs/AGENT_RULES.md#code-quality--sonarcloud) + [§ Conventions](docs/AGENT_RULES.md#conventions) |
| Call API of an external package (dartssh2, drift, riverpod, xterm, …) | [AGENT_RULES § External Libraries & APIs](docs/AGENT_RULES.md#external-libraries--apis--look-up-dont-guess) — never guess signatures: grep repo → Context7 → web docs → pub-cache source |
| Add a new dependency or feature needing an OS capability | [AGENT_RULES § Self-Contained Binary](docs/AGENT_RULES.md#self-contained-binary--end-user-installs-nothing) — bundle > fallback > optional-with-docs (never hard-require user install) |
| About to propose a per-platform native rewrite of a working feature | [AGENT_RULES § Don't Escalate Working Baselines](docs/AGENT_RULES.md#dont-escalate-working-baselines) — **first check: has the user already authorized this upgrade (plan, backlog, earlier message)? If yes, just execute.** The rule blocks UNSOLICITED escalations, not user-requested work |
| Write/update a test | [AGENT_RULES § Testing Methodology](docs/AGENT_RULES.md#testing-methodology) + [ARCHITECTURE §14](docs/ARCHITECTURE.md#14-testing-patterns--di-hooks) |
| Add/change a user-facing string | [AGENT_RULES § Conventions → Localization](docs/AGENT_RULES.md#localization-i18n) — **all 15 `app_*.arb` files** must be updated |
| Add a new widget / helper / mixin / style constant / store | [AGENT_RULES § Reuse First](docs/AGENT_RULES.md#reuse-first-project-wide-not-just-ui) — grep shared modules before creating |
| Add/change a UI control | [AGENT_RULES § Reuse First](docs/AGENT_RULES.md#reuse-first-project-wide-not-just-ui) + [§ UI Components](docs/AGENT_RULES.md#ui-components) (disable-vs-hide) |
| Touch theme / fonts / radii / heights | [AGENT_RULES § Theme & UI Constants](docs/AGENT_RULES.md#theme--ui-constants) — never hardcode |
| Add a new file/class/widget/provider in `lib/` | [AGENT_RULES § Doc Maintenance](docs/AGENT_RULES.md#documentation-maintenance-checklist) — find the row, update the named ARCHITECTURE § |
| Write a commit message | [AGENT_RULES § Commits & Versioning](docs/AGENT_RULES.md#commits--versioning) |
| Open a PR / merge to main | [AGENT_RULES § Branching & Release Flow](docs/AGENT_RULES.md#branching--release-flow) |
| Find something in ARCHITECTURE.md | [AGENT_RULES § Quick Navigation → Within ARCHITECTURE.md](docs/AGENT_RULES.md#within-architecturemd) |

---

## Always-On Rules (gate every action)

These apply to every response without re-reading:

- **Don't commit or push unless the user explicitly asks.** "commit" = commit only, "commit and push" = commit + push.
- **HARD STOP between fixes** — implement → tests → docs → **ask to commit**. Don't start the next fix until current is committed. Overrides: (a) user signals batch mode ("fix all and push", "don't ask", "go through the plan", "stop asking", or the same intent in any language) → batch end-to-end; (b) series of related doc/rule/convention edits in one session → one commit at the arc's end, not per chunk.
- **Default branch is `dev`.** Never push to `main` directly.
- **All files in English only** — code, comments, commits, docs.
- **Never suppress issues** — no `// ignore:`, `// NOSONAR`, `@SuppressWarnings`. Fix root cause.
- **Never amend after push** — new commits only. Amend OK only before first push.
- **Don't install packages without asking.** Latest stable only — no beta/dev/pre-release.
- **End-user install is opt-in, never forced.** The core feature set must run with zero manual setup. Platform-only extras (e.g. Linux biometric unlock) may legitimately require the user to install an OS-level dep — allowed only if (1) bundled statically, (2) a built-in fallback exists, or (3) the dep is **optional** with a disabled-with-reason toggle in-UI **and** a per-platform install snippet in `README.md`. Rung 3 **does** permit an end-user install step; the rule forbids *hard-requiring* one for the core app to launch. Full rule: [AGENT_RULES § Self-Contained Binary](docs/AGENT_RULES.md#self-contained-binary--end-user-installs-nothing).
- **Always build via Makefile** — `make run/build-linux/test/analyze`. Never call `flutter` directly.
- **Skip `make analyze` / `make test` for doc-only commits** — if the staged diff touches no `.dart` files and no `pubspec.yaml`, don't run analyzer or tests manually. The pre-commit hook runs `make check` automatically; running it first on a Markdown-only change is wasted loop time.
- **Cross-platform verification** — Android change → also iOS; Windows change → also Linux + macOS.
- **Best practices by default** — push back on hacky solutions, propose best-practice alternatives.
- **Think systemically** — consider full scope and side effects, not just the literal instruction.
- **Ask before guessing UI placement** — if ambiguous, ask once upfront.
- **Every change ships with docs + tests + translations** — incomplete commit otherwise.
- **Parallel agents** — only `git add` files YOU changed. Do NOT run tests — testing is the main process's job.
