# LetsFLUTssh — Development Guide

LetsFLUTssh — lightweight cross-platform SSH/SFTP client (Dart/Flutter, all 5 desktops + mobile). Open-source alt to Xshell/Termius. **Solo developer project.**

## Documentation Map

- **[`docs/CLAUDE_RULES.md`](docs/CLAUDE_RULES.md)** — all rules, conventions, doc-maintenance checklist, code-quality, testing methodology, commit/release flow. Read on demand via the navigation tables below — never cover-to-cover.
- **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** — module structure, APIs, data flows, design decisions. 3000+ lines — never read cover-to-cover, jump to specific § via [CLAUDE_RULES nav](docs/CLAUDE_RULES.md#within-architecturemd).
- **[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md)** — build instructions, code style (for humans).

---

## Action → Read This (mandatory before acting)

| I'm about to... | MUST read first |
|---|---|
| Write/edit any Dart code | [CLAUDE_RULES § Code Quality — SonarCloud](docs/CLAUDE_RULES.md#code-quality--sonarcloud) + [§ Conventions](docs/CLAUDE_RULES.md#conventions) |
| Write/update a test | [CLAUDE_RULES § Testing Methodology](docs/CLAUDE_RULES.md#testing-methodology) + [ARCHITECTURE §14](docs/ARCHITECTURE.md#14-testing-patterns--di-hooks) |
| Add/change a user-facing string | [CLAUDE_RULES § Conventions → Localization](docs/CLAUDE_RULES.md#localization-i18n) — **all 15 `app_*.arb` files** must be updated |
| Add a new widget / helper / mixin / style constant / store | [CLAUDE_RULES § Reuse First](docs/CLAUDE_RULES.md#reuse-first-project-wide-not-just-ui) — grep shared modules before creating |
| Add/change a UI control | [CLAUDE_RULES § Reuse First](docs/CLAUDE_RULES.md#reuse-first-project-wide-not-just-ui) + [§ UI Components](docs/CLAUDE_RULES.md#ui-components) (disable-vs-hide) |
| Touch theme / fonts / radii / heights | [CLAUDE_RULES § Theme & UI Constants](docs/CLAUDE_RULES.md#theme--ui-constants) — never hardcode |
| Add a new file/class/widget/provider in `lib/` | [CLAUDE_RULES § Doc Maintenance](docs/CLAUDE_RULES.md#documentation-maintenance-checklist) — find the row, update the named ARCHITECTURE § |
| Write a commit message | [CLAUDE_RULES § Commits & Versioning](docs/CLAUDE_RULES.md#commits--versioning) |
| Open a PR / merge to main | [CLAUDE_RULES § Branching & Release Flow](docs/CLAUDE_RULES.md#branching--release-flow) |
| Find something in ARCHITECTURE.md | [CLAUDE_RULES § Quick Navigation → Within ARCHITECTURE.md](docs/CLAUDE_RULES.md#within-architecturemd) |

---

## Always-On Rules (gate every action)

These apply to every response without re-reading:

- **Don't commit or push unless the user explicitly asks.** "commit" = commit only, "commit and push" = commit + push.
- **HARD STOP between fixes** — implement → tests → docs → **ask to commit**. Don't start the next fix until current is committed. Override: "fix all and push" / "не спрашивай" → batch end-to-end.
- **Default branch is `dev`.** Never push to `main` directly.
- **All files in English only** — code, comments, commits, docs.
- **Never suppress issues** — no `// ignore:`, `// NOSONAR`, `@SuppressWarnings`. Fix root cause.
- **Never amend after push** — new commits only. Amend OK only before first push.
- **Don't install packages without asking.** Latest stable only — no beta/dev/pre-release. OS-level deps must be optional with graceful fallback.
- **Always build via Makefile** — `make run/build-linux/test/analyze`. Never call `flutter` directly.
- **Cross-platform verification** — Android change → also iOS; Windows change → also Linux + macOS.
- **Best practices by default** — push back on hacky solutions, propose best-practice alternatives.
- **Think systemically** — consider full scope and side effects, not just the literal instruction.
- **Ask before guessing UI placement** — if ambiguous, ask once upfront.
- **Every change ships with docs + tests + translations** — incomplete commit otherwise.
- **Parallel agents** — only `git add` files YOU changed. Do NOT run tests — testing is the main process's job.
