#!/usr/bin/env bash
# Install all git hooks. Idempotent.
#
# Hooks are tracked in dev/scripts/hooks/ and installed to .git/hooks/
# on first clone or after changes.
#
# Layout:
#   pre-commit   make check-static + dart format + flutter gen-l10n
#                (skipped for doc-only diffs)
#   commit-msg   conventional-commit format + agent plan-ID gate
#   pre-push     make check-static — local backstop before sharing
#   post-commit  cap rust/target size (background, never fails commit)
#
# Usage:
#   bash dev/scripts/install-hooks.sh
#   make hooks      (Makefile target wrapping the same call)

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

echo "install-hooks: installing hooks..."

# Install each hook
for hook in pre-commit commit-msg pre-push post-commit; do
  if [[ -f "$script_dir/hooks/$hook/install.sh" ]]; then
    bash "$script_dir/hooks/$hook/install.sh"
  fi
done

echo "install-hooks: done. All hooks installed to .git/hooks/"
echo "install-hooks: bypass flags — SKIP_PRECOMMIT=1, SKIP_PREPUSH=1, SKIP_TARGET_GC=1."
