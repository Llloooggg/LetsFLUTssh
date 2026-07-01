#!/usr/bin/env bash
# Trim rust/target back under CARGO_TARGET_MAX_GB in escalating passes.
#
# cargo never garbage-collects target/; flutter_rust_bridge codegen and
# cargo-mutants each spawn many distinct builds whose artifacts pile up.
# The single worst offender is debug/incremental — rustc's incremental
# cache, which it rewrites on every build, so its files always look
# fresh. `cargo sweep --maxsize` picks a timestamp cutoff and removes
# everything older, so when the bulk of the directory is a freshly
# touched incremental cache it can reclaim almost nothing (observed:
# 2G freed out of a 108G target). The escalation below fixes that:
#
#   1. --time pass   drop artifacts untouched for CARGO_SWEEP_STALE_DAYS.
#   2. --maxsize     trim the rest oldest-first down to the cap.
#   3. incremental   if still over cap, delete every incremental/ dir.
#                    It is per-machine scratch, rebuilt on the next
#                    compile, and dropping it never recompiles the
#                    dependency graph (that lives in deps/), so this
#                    stays well short of a cold `cargo clean`.
#
# Tunables:
#   CARGO_TARGET_MAX_GB     cap in GiB (default 35)
#   CARGO_SWEEP_STALE_DAYS  age cutoff for the --time pass (default 7)
set -uo pipefail

max_gb="${CARGO_TARGET_MAX_GB:-35}"
stale_days="${CARGO_SWEEP_STALE_DAYS:-7}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rust_dir="$(cd "$script_dir/../.." && pwd)/rust"
target_dir="$rust_dir/target"

[[ -d "$target_dir" ]] || { echo "rust-sweep: $target_dir not found, nothing to do"; exit 0; }
cd "$rust_dir"

used_gb()  { echo $(( $(du -sk "$target_dir" 2>/dev/null | cut -f1) / 1024 / 1024 )); }
over_cap() { (( $(du -sk "$target_dir" 2>/dev/null | cut -f1) > max_gb * 1024 * 1024 )); }

echo "rust-sweep: target is $(used_gb)G, cap ${max_gb}G"

cargo sweep --time "$stale_days" || true
cargo sweep --maxsize "${max_gb}GB" || true

if over_cap; then
  echo "rust-sweep: still $(used_gb)G after cargo-sweep — pruning incremental/ caches"
  find "$target_dir" -type d -name incremental -prune -exec rm -rf {} +
fi

echo "rust-sweep: target is $(used_gb)G after sweep"
