#!/usr/bin/env bash
# Install the project's git hooks into .git/hooks. Idempotent.
#
# Hooks are intentionally not tracked, so each clone runs this once
# (AGENTS.md / docs/CONTRIBUTING.md point contributors here). Layout —
# fast static checks fire locally on commit and again on push as a
# backstop; the slow test suite runs only in CI, the real gate:
#   pre-commit   make check-static (format + lint + workflow/hardening
#                lint + unused-deps; no tests) — skipped for doc-only diffs
#   pre-push     make check-static + dart format + flutter gen-l10n
#                (if .arb staged) — local backstop catching format /
#                lint slips before they hit CI. Tests are NOT run locally;
#                CI runs the full suite on every PR to main/dev.
#   commit-msg   conventional-commit format (all commits) + agent
#                plan-ID gate (agent commits only)
#   post-commit  cap rust/target size (local housekeeping)
#
# Usage:
#   bash dev/scripts/install-hooks.sh
#   make hooks      (Makefile target wrapping the same call)

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
hook_dir="$repo_root/.git/hooks"

if [[ ! -d "$hook_dir" ]]; then
  echo "install-hooks: $hook_dir does not exist. Are you inside a git checkout?" >&2
  exit 1
fi

cat > "$hook_dir/pre-commit" <<'HOOK'
#!/usr/bin/env bash
# Auto-installed by dev/scripts/install-hooks.sh — do not edit by hand.
# Edit dev/scripts/install-hooks.sh and re-run it instead.
set -euo pipefail

if [[ "${SKIP_PRECOMMIT:-0}" == "1" ]]; then
  echo "pre-commit: SKIP_PRECOMMIT=1 set, skipping make check-static" >&2
  exit 0
fi

# Doc-only skip per AGENTS.md: when nothing in the staged diff is
# .dart / .rs / pubspec.yaml / Cargo.toml, the analyzers have nothing
# to chew on. Saves time on every docs / hook / ARB / CI-config commit.
staged=$(git diff --cached --name-only --diff-filter=ACMRT)
if [[ -z "$staged" ]]; then
  echo "pre-commit: no staged files, skipping make check-static" >&2
  exit 0
fi
if ! printf '%s\n' "$staged" | grep -qE '\.(dart|rs)$|(^|/)pubspec\.yaml$|(^|/)Cargo\.toml$'; then
  echo "pre-commit: doc-only staged diff, skipping make check-static (per AGENTS.md)" >&2
  exit 0
fi

# Static slice of CI's gate: format-check + lint + workflow lint +
# release hardening + unused-deps, for both Dart and Rust. The test
# suite is not run locally — CI runs it on every PR to main/dev.
exec make check-static
HOOK
chmod +x "$hook_dir/pre-commit"

cat > "$hook_dir/pre-push" <<'HOOK'
#!/usr/bin/env bash
# Auto-installed by dev/scripts/install-hooks.sh — do not edit by hand.
# Edit dev/scripts/install-hooks.sh and re-run it instead.
#
# Local backstop before sharing: runs `make check-static` (format +
# lint + workflow/hardening lint + unused-deps), then formats Dart
# files and regenerates l10n if needed. Catches a format / lint
# slip from an amend or a SKIP_PRECOMMIT commit before it burns a CI
# round. The full test suite is NOT run here — it is slow and redundant
# with CI, which runs it on every PR to main/dev (the real gate before a
# release-bearing merge). Unconditional: check-static is seconds and its
# workflow / release-hardening slices cover non-.dart/.rs pushes too.
#
#   SKIP_PREPUSH=1   bypass for an emergency push
set -euo pipefail

if [[ "${SKIP_PREPUSH:-0}" == "1" ]]; then
  echo "pre-push: SKIP_PREPUSH=1 set, skipping all checks" >&2
  exit 0
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# ── make check-static (format-check + lint + workflow + release + unused-deps) ─
echo "pre-push: running make check-static..."
output=$(make check-static 2>&1)
status=$?
echo "$output" | tail -20
if [ $status -ne 0 ]; then
  echo "pre-push: make check-static failed." >&2
  exit 1
fi

# ── dart format ─
dart_files=$(git diff --cached --name-only --diff-filter=ACMR HEAD~1..HEAD -- '*.dart' 2>/dev/null || git ls-tree -r --name-only HEAD -- '*.dart')
if [ -n "$dart_files" ]; then
  echo "pre-push: dart format..."
  dart format . >/dev/null 2>&1 || { echo "pre-push: dart format failed." >&2; exit 1; }
fi

# ── flutter gen-l10n (only if .arb files changed) ─
arb_files=$(git diff --cached --name-only --diff-filter=ACMR HEAD~1..HEAD -- '*.arb' 2>/dev/null || git ls-tree -r --name-only HEAD -- '*.arb')
if [ -n "$arb_files" ]; then
  echo "pre-push: flutter gen-l10n..."
  (cd "$repo_root" && flutter gen-l10n >/dev/null 2>&1) || { echo "pre-push: flutter gen-l10n failed." >&2; exit 1; }
fi

echo "pre-push: all checks passed."
HOOK
chmod +x "$hook_dir/pre-push"

cat > "$hook_dir/post-commit" <<'HOOK'
#!/usr/bin/env bash
# Auto-installed by dev/scripts/install-hooks.sh — do not edit by hand.
# Edit dev/scripts/install-hooks.sh and re-run it instead.
#
# Bound the Rust build cache. cargo never garbage-collects target/:
# each distinct build adds artifacts and nothing removes them, so the
# directory grows without bound — flutter_rust_bridge codegen and
# cargo-mutants both spawn many distinct builds. When rust/target
# crosses a size threshold we run `make rust-sweep`, which drops the
# OLDEST artifacts until the directory is back under the cap. The hot
# cache (the latest couple of builds) survives, so this never forces a
# cold rebuild the way a full `cargo clean` would — one build alone is
# ~16G, so a full wipe on every commit meant compiling from scratch.
#
# Runs in the background after the commit: zero commit latency, and a
# post-commit hook can never fail the commit (git ignores its exit
# code). Output is appended to .git/target-gc.log.
#
# Tunables:
#   CARGO_TARGET_MAX_GB   cap in GiB, room for ~2 builds (default 35)
#   SKIP_TARGET_GC=1      skip the check for this commit
set -uo pipefail

[[ "${SKIP_TARGET_GC:-0}" == "1" ]] && exit 0

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
target_dir="$repo_root/rust/target"
[[ -d "$target_dir" ]] || exit 0

max_gb="${CARGO_TARGET_MAX_GB:-35}"
log="$repo_root/.git/target-gc.log"

(
  used_kb=$(du -sk "$target_dir" 2>/dev/null | cut -f1)
  [[ -n "${used_kb:-}" ]] || exit 0
  (( used_kb > max_gb * 1024 * 1024 )) || exit 0
  stamp="$(date '+%Y-%m-%d %H:%M:%S')"
  used_gb=$(( used_kb / 1024 / 1024 ))
  if ! command -v cargo-sweep >/dev/null 2>&1; then
    # No full-clean fallback on purpose: a cold rebuild is worse than
    # letting target/ stay large. Install cargo-sweep via make hooks'
    # sibling `make setup-rust-tools`.
    printf '%s  rust/target is %dG (> %dG) but cargo-sweep is missing — skipping (run: make setup-rust-tools)\n' \
      "$stamp" "$used_gb" "$max_gb"
    exit 0
  fi
  printf '%s  rust/target is %dG (> %dG) — make rust-sweep (trim oldest to %dG)\n' \
    "$stamp" "$used_gb" "$max_gb" "$max_gb"
  CARGO_TARGET_MAX_GB="$max_gb" make -C "$repo_root" rust-sweep 2>&1 || true
) >>"$log" 2>&1 &

exit 0
HOOK
chmod +x "$hook_dir/post-commit"

# commit-msg chains the conventional-commit format check (all commits)
# and the agent plan-ID gate (agent commits only). Symlinked so edits
# to the tracked scripts take effect immediately. The plan-ID gate
# still self-gates on plan-item IDs.
ln -sf "../../dev/scripts/commit-msg-gate.sh" "$hook_dir/commit-msg"
chmod +x "$repo_root/dev/scripts/commit-msg-gate.sh" \
         "$repo_root/dev/scripts/conventional-commit-check.sh" \
         "$repo_root/dev/scripts/agent-plan-id-gate.sh"

echo "install-hooks: wrote $hook_dir/{pre-commit,pre-push,post-commit}"
echo "install-hooks: linked $hook_dir/commit-msg -> dev/scripts/commit-msg-gate.sh"
echo "install-hooks: pre-commit runs \`make check-static\` (skipped for doc-only staged diffs); pre-push runs \`make check-static\` + dart format + flutter gen-l10n (tests run in CI on PRs, not locally)."
echo "install-hooks: commit-msg checks conventional-commit format (all commits) + plan-ID gate (agent commits only)."
echo "install-hooks: post-commit runs \`make rust-sweep\` in the background when rust/target exceeds CARGO_TARGET_MAX_GB (default 35), trimming the oldest artifacts only; log at .git/target-gc.log."
echo "install-hooks: bypass flags — SKIP_PRECOMMIT=1, SKIP_PREPUSH=1, SKIP_TARGET_GC=1."
