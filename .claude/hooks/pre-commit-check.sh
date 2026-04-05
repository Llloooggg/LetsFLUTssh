#!/bin/bash
# PreToolUse hook: run analyze + tests before git commit
# Blocks the commit if either fails

# cd to repo root (hooks run from project root, but be safe)
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

echo "Running pre-commit checks (analyze + tests)..."
output=$(make check 2>&1)
status=$?

# Show last 30 lines
echo "$output" | tail -30

if [ $status -ne 0 ]; then
    echo '{"continue":false,"stopReason":"Pre-commit check failed. Fix issues before committing."}'
    exit 0
fi

echo '{"continue":true}'
exit 0
