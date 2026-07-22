#!/usr/bin/env bash
# Post-commit hook: cap rust/target size via cargo-sweep
#
# Runs in background after commit. Never fails the commit.

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
    printf '%s  rust/target is %dG (> %dG) but cargo-sweep missing — skipping (run: make setup-rust-tools)\n' \
      "$stamp" "$used_gb" "$max_gb"
    exit 0
  fi
  printf '%s  rust/target is %dG (> %dG) — make rust-sweep (trim oldest to %dG)\n' \
    "$stamp" "$used_gb" "$max_gb" "$max_gb"
  CARGO_TARGET_MAX_GB="$max_gb" make -C "$repo_root" rust-sweep 2>&1 || true
) >>"$log" 2>&1 &

exit 0
