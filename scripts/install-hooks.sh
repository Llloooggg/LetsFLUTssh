#!/usr/bin/env bash
# Install the project's git hooks into .git/hooks. Idempotent.
#
# CLAUDE.md / docs/CONTRIBUTING.md tell contributors that committing on
# this repo runs `make check` (analyzer + tests) automatically. That
# requires a pre-commit hook to be present in the local clone — git
# hooks are intentionally not tracked. Run this once after clone.
#
# Usage:
#   bash scripts/install-hooks.sh
#   make hooks      (Makefile target wrapping the same call)

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook_dir="$repo_root/.git/hooks"

if [[ ! -d "$hook_dir" ]]; then
  echo "install-hooks: $hook_dir does not exist. Are you inside a git checkout?" >&2
  exit 1
fi

cat > "$hook_dir/pre-commit" <<'HOOK'
#!/usr/bin/env bash
# Auto-installed by scripts/install-hooks.sh — do not edit by hand.
# Edit scripts/install-hooks.sh and re-run it instead.
set -euo pipefail

if [[ "${SKIP_PRECOMMIT:-0}" == "1" ]]; then
  echo "pre-commit: SKIP_PRECOMMIT=1 set, skipping make check" >&2
  exit 0
fi

# Run analyze + tests. Same gate that CI runs on push.
exec make check
HOOK
chmod +x "$hook_dir/pre-commit"

echo "install-hooks: wrote $hook_dir/pre-commit"
echo "install-hooks: subsequent commits will run \`make check\` first."
echo "install-hooks: SKIP_PRECOMMIT=1 git commit ... bypasses it for emergencies."
