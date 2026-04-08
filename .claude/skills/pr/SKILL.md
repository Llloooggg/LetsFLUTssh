---
name: pr
description: Create a PR from dev to main following project merge flow. Runs version bump, syncs dev with main first, creates PR with --auto merge.
---

## PR workflow for LetsFLUTssh (dev -> main)

Follow the project's branching & release flow strictly.

### Step 1: Verify state
- Confirm we're on `dev` branch. If not, STOP
- `git status` — working tree must be clean. If dirty, STOP and tell user to commit first

### Step 2: Sync dev with main
```bash
git fetch origin main && git merge origin/main
```
If conflicts: STOP and tell user. If fast-forward or clean merge, push: `git push`

### Step 3: Version bump
Run the bump script to calculate and apply the version bump from conventional commits:
```bash
scripts/bump-version.sh
```
- If it says "nothing to bump" — skip (docs/test/ci-only PR, no version change needed)
- If it bumps — push the bump commit: `git push`

### Step 4: Gather PR info
- `git log origin/main..HEAD --oneline` — all commits going into this PR
- `git diff origin/main...HEAD --stat` — changed files summary

### Step 5: Create PR with auto-merge
```bash
gh pr create --base main --head dev --title "TITLE" --body "$(cat <<'EOF'
## Summary
- bullet points from commits

## Test plan
- [ ] CI passes (ci, osv-scan, semgrep-scan, codeql-scan)

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)" && gh pr merge --auto --merge
```

### Step 6: After merge confirmation
Tell user: "After PR merges, sync dev with main: `git fetch origin main && git merge origin/main && git push`"

### Arguments
If user passes a custom title: `$ARGUMENTS`
