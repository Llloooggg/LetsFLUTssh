#!/usr/bin/env bash
# Mutation testing wrapper for the Rust workspace via cargo-mutants.
#
# Why a wrapper:
#  - cargo-mutants creates per-job scratch copies of `target/` (one
#    Rust workspace clone per concurrent worker, ~3-4 GiB each).
#    Default `$TMPDIR` is /tmp, which on WSL2 is tmpfs (RAM, ~16 GiB)
#    and runs out fast at 4 jobs. We pin scratch + output to a
#    disk-backed dir under .cache/cargo-mutants/.
#  - cargo-mutants takes file globs without a slash to match basename;
#    each scope below maps to a curated list of files in lfs_core.
#  - Outcomes summary (caught/missed/unviable/timeout) is printed
#    from outcomes.json so callers don't have to parse logs.
#
# Usage:
#   scripts/run-mutants.sh <scope>
#
# Scopes:
#   archive   — lfs_core::archive::*
#   security  — lfs_core::security::*
#   ssh       — lfs_core::ssh::*
#   crypto    — lfs_core::crypto::*
#   db        — lfs_core::db::*
#   <path>    — anything else: pass a relative path under
#               rust/crates/lfs_core/src/ (e.g. `connection`)
#
# Knobs (env):
#   MUTANTS_JOBS        parallel workers (default 2; raise carefully)
#   MUTANTS_TIMEOUT_MUL test-phase timeout multiplier (default 5.0)
#   MUTANTS_OUTPUT      output dir (default .cache/cargo-mutants/<scope>)
#   MUTANTS_TMPDIR      scratch dir for per-worker target/ copies
#                       (default .cache/cargo-mutants/scratch)

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <scope>" >&2
  echo "  scopes: archive | security | ssh | crypto | db | <path under lfs_core/src/>" >&2
  exit 64
fi

SCOPE="$1"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$REPO/.cache/cargo-mutants"
RESULTS="${MUTANTS_OUTPUT:-$CACHE/$SCOPE}"
TMP="${MUTANTS_TMPDIR:-$CACHE/scratch}"
JOBS="${MUTANTS_JOBS:-2}"
TIMEOUT_MUL="${MUTANTS_TIMEOUT_MUL:-5.0}"

mkdir -p "$RESULTS" "$TMP"

# Map scope to a list of .rs basenames under lfs_core/src/<scope>/.
# cargo-mutants -f <basename> matches the file regardless of path,
# which is what we want here (the lfs_core crate has only one file
# per name across these dirs).
LFS_CORE_SRC="$REPO/rust/crates/lfs_core/src"
SCOPE_DIR="$LFS_CORE_SRC/$SCOPE"
if [[ ! -d "$SCOPE_DIR" ]]; then
  echo "scope '$SCOPE' is not a directory under lfs_core/src/ — pass a real path" >&2
  exit 64
fi

mapfile -t FILES < <(find "$SCOPE_DIR" -maxdepth 2 -name '*.rs' -printf '%f\n' | sort)
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "scope '$SCOPE' has no .rs files" >&2
  exit 64
fi

FILE_FLAGS=()
for f in "${FILES[@]}"; do
  FILE_FLAGS+=( --file "$f" )
done

echo "scope:       $SCOPE  (${#FILES[@]} files)"
echo "jobs:        $JOBS"
echo "timeout x:   $TIMEOUT_MUL"
echo "results:     $RESULTS"
echo "scratch:     $TMP"
echo

cd "$REPO/rust/crates/lfs_core"
TMPDIR="$TMP" cargo mutants \
  "${FILE_FLAGS[@]}" \
  --jobs "$JOBS" \
  --timeout-multiplier "$TIMEOUT_MUL" \
  --output "$RESULTS"

# Summary from outcomes.json. cargo-mutants writes one record per
# mutation with .summary in {caught, missed, unviable, timeout,
# success, failure}. Anything other than `missed` and `success`
# counts as caught.
SUMMARY="$RESULTS/outcomes.json"
if [[ -f "$SUMMARY" ]] && command -v python3 >/dev/null 2>&1; then
  echo
  echo "── Mutation summary (lfs_core::$SCOPE) ──"
  python3 - "$SUMMARY" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
outcomes = data.get('outcomes', [])
buckets = {}
for o in outcomes:
    s = o.get('summary', '?')
    buckets[s] = buckets.get(s, 0) + 1
total = sum(buckets.values())
caught = total - buckets.get('Missed', 0) - buckets.get('Unviable', 0)
testable = total - buckets.get('Unviable', 0)
score = (100.0 * caught / testable) if testable else 0.0
for k in sorted(buckets):
    print(f'  {k:14} {buckets[k]:>5}')
print(f'  {"TOTAL":14} {total:>5}')
print(f'  caught/testable: {caught}/{testable} → mutation score {score:.1f}%')
PY
fi
