#!/usr/bin/env bash
# Pre-commit hook: make check-static + dart format + flutter gen-l10n
#
# Runs on every commit. Skipped for doc-only diffs.
#
#   SKIP_PRECOMMIT=1   bypass for an emergency commit

set -euo pipefail

if [[ "${SKIP_PRECOMMIT:-0}" == "1" ]]; then
  echo "pre-commit: SKIP_PRECOMMIT=1 set, skipping" >&2
  exit 0
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Doc-only skip per AGENTS.md
staged=$(git diff --cached --name-only --diff-filter=ACMRT)
if [[ -z "$staged" ]]; then
  echo "pre-commit: no staged files, skipping" >&2
  exit 0
fi
if ! printf '%s\n' "$staged" | grep -qE '\.(dart|rs)$|(^|/)pubspec\.yaml$|(^|/)Cargo\.toml$'; then
  echo "pre-commit: doc-only staged diff, skipping" >&2
  exit 0
fi

# ── make check-static ─
echo "pre-commit: make check-static..."
output=$(cd "$repo_root" && make check-static 2>&1)
status=$?
echo "$output" | tail -20
if [ $status -ne 0 ]; then
  echo "pre-commit: make check-static failed." >&2
  exit 1
fi

# ── dart format ─
dart_files=$(git diff --cached --name-only --diff-filter=ACMR -- '*.dart')
if [ -n "$dart_files" ]; then
  echo "pre-commit: dart format..."
  (cd "$repo_root" && dart format . >/dev/null 2>&1) || { echo "pre-commit: dart format failed." >&2; exit 1; }
fi

# ── flutter gen-l10n (only if .arb files changed) ─
arb_files=$(git diff --cached --name-only --diff-filter=ACMR -- '*.arb')
if [ -n "$arb_files" ]; then
  echo "pre-commit: flutter gen-l10n..."
  (cd "$repo_root" && flutter gen-l10n >/dev/null 2>&1) || { echo "pre-commit: flutter gen-l10n failed." >&2; exit 1; }
fi

echo "pre-commit: all checks passed."
