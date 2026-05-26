#!/usr/bin/env bash
# commit-msg hook entry point. Chains two gates, installed together as
# .git/hooks/commit-msg by dev/scripts/install-hooks.sh:
#   1. conventional-commit subject format — every commit (mirrors CI's
#      commit-lint job via the shared conventional-commit-check.sh).
#   2. agent plan-ID gate — agent commits only (self-gates on the
#      `Co-Authored-By: Claude` trailer).
# Either gate failing aborts the commit.
set -euo pipefail

# Installed as a symlink in .git/hooks, so locate the sibling scripts
# via the repo root (git runs hooks with CWD at the working-tree top).
# BASH_SOURCE would resolve to .git/hooks — the symlink's dir, not here.
scripts="$(git rev-parse --show-toplevel)/dev/scripts"

bash "$scripts/conventional-commit-check.sh" --file "$1"
exec bash "$scripts/agent-plan-id-gate.sh" "$1"
