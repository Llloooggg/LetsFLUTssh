#!/usr/bin/env bash
# Pre-push hook: make check-static (backstop before sharing)
#
# Runs before push. Skips if SKIP_PREPUSH=1 or tools unavailable.

set -uo pipefail

if [[ "${SKIP_PREPUSH:-0}" == "1" ]]; then
  echo "pre-push: SKIP_PREPUSH=1 set, skipping" >&2
  exit 0
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Check if make is available
if ! command -v make >/dev/null 2>&1; then
  echo "pre-push: make not found, skipping check-static" >&2
  exit 0
fi

echo "pre-push: make check-static..."
output=$(cd "$repo_root" && make check-static 2>&1)
status=$?
echo "$output" | tail -20
if [ $status -ne 0 ]; then
  echo "pre-push: make check-static failed." >&2
  exit 1
fi

echo "pre-push: all checks passed."
