---
name: commit
description: Create a git commit following project conventions. Checks docs. Pre-commit hook handles analyzer + tests. Use when user says "commit" or "commit and push".
---

## Commit workflow for LetsFLUTssh

Follow these steps strictly. This is a gated workflow — do NOT skip steps.

### Step 1: Gather state (parallel)
- `git status` (no -uall flag)
- `git diff --cached` and `git diff` to see all changes
- `git log --oneline -5` for recent commit style

### Step 2: Analyze changes
Determine:
1. **Type**: feat / fix / refactor / test / docs / chore / ci
2. **Docs updated?** — Check per the documentation maintenance table in CLAUDE.md. If code changed but docs didn't, WARN the user

Note: Version bumps are automated by `scripts/bump-version.sh` (runs during `/pr`). Do NOT bump version manually.

### Step 3: Pre-commit checks
- Do NOT run `make analyze` or `make test` manually — the pre-commit hook runs `make check` automatically and blocks the commit if anything fails

### Step 4: Draft commit message
- Format: `type: short description`
- Keep it user-readable (drives auto-changelog)
- If both app changes and docs in same commit, prefix describes the app change

### Step 5: Confirm with user
- If the user explicitly said "комить" / "commit" (i.e. gave a direct command), skip confirmation — proceed straight to Step 6
- Otherwise, show: files to be committed, commit message — and ask for confirmation

### Step 6: Commit
- `git add` only the relevant files (not `git add -A`)
- Commit with the message. Use HEREDOC format:
```
git commit -m "$(cat <<'EOF'
type: description

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Step 7: Push (only if user said "commit and push")
- Push to current branch
- If user only said "commit", do NOT push

### Arguments
If the user passes arguments like `-m "message"`, use that message but still run all checks.
