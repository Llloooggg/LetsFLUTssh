#!/usr/bin/env bash
# Install the project's git hooks into .git/hooks. Idempotent.
#
# CLAUDE.md / docs/CONTRIBUTING.md tell contributors that committing on
# this repo runs `make check` (format-check + lint + workflow lint +
# release hardening + unused-deps + tests, for both Dart and Rust)
# automatically. That requires a pre-commit hook to be present in the
# local clone — git hooks are intentionally not tracked. Run this once
# after clone.
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

# Doc-only skip per CLAUDE.md: when nothing in the staged diff is
# .dart / .rs / pubspec.yaml / Cargo.toml, `make check` is wasted
# work — analyzer and tests have nothing to test. Saves ~minute on
# every docs / hook / ARB / CI-config commit.
staged=$(git diff --cached --name-only --diff-filter=ACMRT)
if [[ -z "$staged" ]]; then
  echo "pre-commit: no staged files, skipping make check" >&2
  exit 0
fi
if ! printf '%s\n' "$staged" | grep -qE '\.(dart|rs)$|(^|/)pubspec\.yaml$|(^|/)Cargo\.toml$'; then
  echo "pre-commit: doc-only staged diff, skipping make check (per CLAUDE.md)" >&2
  exit 0
fi

# Same gate CI runs on push: format-check + lint + workflow lint +
# release hardening + unused-deps + tests, for both Dart and Rust.
exec make check
HOOK
chmod +x "$hook_dir/pre-commit"

# Agent-only plan-ID gate. Symlinked so editing
# scripts/agent-plan-id-gate.sh picks up immediately. Fires only
# on agent commits (Co-Authored-By: Claude trailer present);
# maintainer's own commits skip the check entirely.
ln -sf "../../scripts/agent-plan-id-gate.sh" "$hook_dir/commit-msg"
chmod +x "$repo_root/scripts/agent-plan-id-gate.sh"

echo "install-hooks: wrote $hook_dir/pre-commit"
echo "install-hooks: linked $hook_dir/commit-msg -> scripts/agent-plan-id-gate.sh"
echo "install-hooks: pre-commit runs \`make check\` (skipped for doc-only staged diffs); commit-msg gate fires only on agent commits."
echo "install-hooks: SKIP_PRECOMMIT=1 git commit ... bypasses make check for emergencies."
