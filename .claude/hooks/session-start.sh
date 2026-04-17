#!/bin/bash
# SessionStart hook: dump concise git state so Claude doesn't spend early
# turns re-running `git status` / `git log`. Output is injected as context.

set -e
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 0

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
main_branch="main"

uncommitted=$(git status --porcelain 2>/dev/null | head -40)
uncommitted_count=$(git status --porcelain 2>/dev/null | wc -l)

# Commits on current branch ahead of main (useful for PR planning).
# Skip when HEAD is already main.
ahead=""
if [ "$branch" != "$main_branch" ] && git rev-parse --verify "$main_branch" >/dev/null 2>&1; then
    ahead=$(git log "${main_branch}..HEAD" --oneline 2>/dev/null | head -20)
fi

recent=$(git log --oneline -5 2>/dev/null)

echo "# Git state snapshot (SessionStart hook)"
echo
echo "**Branch:** \`${branch}\`"
echo
if [ -n "$uncommitted" ]; then
    echo "**Uncommitted (${uncommitted_count}):**"
    echo '```'
    echo "$uncommitted"
    echo '```'
else
    echo "**Uncommitted:** none (clean working tree)"
fi
echo
if [ -n "$ahead" ]; then
    echo "**Ahead of ${main_branch}:**"
    echo '```'
    echo "$ahead"
    echo '```'
else
    echo "**Recent commits:**"
    echo '```'
    echo "$recent"
    echo '```'
fi
exit 0
