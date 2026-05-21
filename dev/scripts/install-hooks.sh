#!/usr/bin/env bash
# Install the project's git hooks into .git/hooks. Idempotent.
#
# Hooks are intentionally not tracked, so each clone runs this once
# (CLAUDE.md / docs/CONTRIBUTING.md point contributors here). Layout —
# cheap checks fire early for fast feedback, the heavy test suite waits
# until push, and CI re-runs everything as the real enforcement gate:
#   pre-commit   make check-static (format + lint + workflow/hardening
#                lint + unused-deps; no tests) — skipped for doc-only diffs
#   pre-push     make test (full Dart + Rust suite) — skipped when the
#                pushed commits touch no .dart/.rs/pubspec/Cargo.toml
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

# Doc-only skip per CLAUDE.md: when nothing in the staged diff is
# .dart / .rs / pubspec.yaml / Cargo.toml, the analyzers have nothing
# to chew on. Saves time on every docs / hook / ARB / CI-config commit.
staged=$(git diff --cached --name-only --diff-filter=ACMRT)
if [[ -z "$staged" ]]; then
  echo "pre-commit: no staged files, skipping make check-static" >&2
  exit 0
fi
if ! printf '%s\n' "$staged" | grep -qE '\.(dart|rs)$|(^|/)pubspec\.yaml$|(^|/)Cargo\.toml$'; then
  echo "pre-commit: doc-only staged diff, skipping make check-static (per CLAUDE.md)" >&2
  exit 0
fi

# Static slice of CI's gate: format-check + lint + workflow lint +
# release hardening + unused-deps, for both Dart and Rust. The full
# test suite runs in the pre-push hook, not on every commit.
exec make check-static
HOOK
chmod +x "$hook_dir/pre-commit"

cat > "$hook_dir/pre-push" <<'HOOK'
#!/usr/bin/env bash
# Auto-installed by dev/scripts/install-hooks.sh — do not edit by hand.
# Edit dev/scripts/install-hooks.sh and re-run it instead.
#
# Heavy gate before sharing: runs the full `make test` suite so a
# broken push never reaches CI. Kept out of pre-commit so day-to-day
# commits stay fast — static checks fire on commit, tests fire here.
#
#   SKIP_PREPUSH=1   bypass for an emergency push
set -euo pipefail

if [[ "${SKIP_PREPUSH:-0}" == "1" ]]; then
  echo "pre-push: SKIP_PREPUSH=1 set, skipping make test" >&2
  exit 0
fi

zero='0000000000000000000000000000000000000000'
run=0          # 1 => force the suite (range we cannot cheaply diff)
code_touched=0 # 1 => a pushed range touched testable code
saw_range=0

# git feeds "<local_ref> <local_sha> <remote_ref> <remote_sha>" per ref.
while read -r _local_ref local_sha _remote_ref remote_sha; do
  [[ "$local_sha" == "$zero" ]] && continue   # branch deletion: nothing to test
  saw_range=1
  if [[ "$remote_sha" == "$zero" ]]; then
    run=1; break                              # new branch: no base to diff, test it
  fi
  files=$(git diff --name-only "$remote_sha" "$local_sha" 2>/dev/null) || { run=1; break; }
  if printf '%s\n' "$files" | grep -qE '\.(dart|rs)$|(^|/)pubspec\.yaml$|(^|/)Cargo\.toml$'; then
    code_touched=1
  fi
done

[[ "$saw_range" == 1 ]] || exit 0             # nothing to push
if [[ "$run" != 1 && "$code_touched" != 1 ]]; then
  echo "pre-push: pushed commits touch no .dart/.rs/pubspec/Cargo.toml, skipping make test" >&2
  exit 0
fi

exec make test
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
# crosses a size threshold we reset it via `make rust-clean`.
#
# Runs in the background after the commit: zero commit latency, and a
# post-commit hook can never fail the commit (git ignores its exit
# code). Output is appended to .git/target-gc.log.
#
# Tunables:
#   CARGO_TARGET_MAX_GB   threshold in GiB (default 10)
#   SKIP_TARGET_GC=1      skip the check for this commit
set -uo pipefail

[[ "${SKIP_TARGET_GC:-0}" == "1" ]] && exit 0

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
target_dir="$repo_root/rust/target"
[[ -d "$target_dir" ]] || exit 0

max_gb="${CARGO_TARGET_MAX_GB:-10}"
log="$repo_root/.git/target-gc.log"

(
  used_kb=$(du -sk "$target_dir" 2>/dev/null | cut -f1)
  [[ -n "${used_kb:-}" ]] || exit 0
  if (( used_kb > max_gb * 1024 * 1024 )); then
    printf '%s  rust/target is %dG (> %dG) — make rust-clean\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$(( used_kb / 1024 / 1024 ))" "$max_gb"
    make -C "$repo_root" rust-clean 2>&1 || true
  fi
) >>"$log" 2>&1 &

exit 0
HOOK
chmod +x "$hook_dir/post-commit"

# commit-msg chains the conventional-commit format check (all commits)
# and the agent plan-ID gate (agent commits only). Symlinked so edits
# to the tracked scripts take effect immediately. The plan-ID gate
# still self-gates on the Co-Authored-By: Claude trailer.
ln -sf "../../dev/scripts/commit-msg-gate.sh" "$hook_dir/commit-msg"
chmod +x "$repo_root/dev/scripts/commit-msg-gate.sh" \
         "$repo_root/dev/scripts/conventional-commit-check.sh" \
         "$repo_root/dev/scripts/agent-plan-id-gate.sh"

echo "install-hooks: wrote $hook_dir/{pre-commit,pre-push,post-commit}"
echo "install-hooks: linked $hook_dir/commit-msg -> dev/scripts/commit-msg-gate.sh"
echo "install-hooks: pre-commit runs \`make check-static\` (skipped for doc-only staged diffs); pre-push runs \`make test\`."
echo "install-hooks: commit-msg checks conventional-commit format (all commits) + plan-ID gate (agent commits only)."
echo "install-hooks: post-commit runs \`make rust-clean\` in the background when rust/target exceeds CARGO_TARGET_MAX_GB (default 10); log at .git/target-gc.log."
echo "install-hooks: bypass flags — SKIP_PRECOMMIT=1, SKIP_PREPUSH=1, SKIP_TARGET_GC=1."
