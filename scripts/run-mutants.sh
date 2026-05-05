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

# Map scope to a list of paths under lfs_core/src/<scope>/.
# cargo-mutants -f <glob> matches by basename when there is no
# slash in the glob and by full path when there is. Pass paths
# *with* slashes (`src/archive/apply.rs`) so generic basenames
# like `mod.rs` don't accidentally pull in every `mod.rs` across
# the crate (which would balloon a 465-mutant scope into a
# 900+-mutant unrelated run).
LFS_CORE_SRC="$REPO/rust/crates/lfs_core/src"
SCOPE_DIR="$LFS_CORE_SRC/$SCOPE"
if [[ ! -d "$SCOPE_DIR" ]]; then
  echo "scope '$SCOPE' is not a directory under lfs_core/src/ — pass a real path" >&2
  exit 64
fi

mapfile -t FILES < <(find "$SCOPE_DIR" -maxdepth 2 -name '*.rs' -printf '%P\n' | sort)
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "scope '$SCOPE' has no .rs files" >&2
  exit 64
fi

FILE_FLAGS=()
for f in "${FILES[@]}"; do
  # `**/<scope>/<file>` anchors the glob on the scope dir.
  # cargo-mutants matches on the full path, so this skips
  # same-name files in sibling modules — without it,
  # generic basenames (mod.rs) would pull in every `mod.rs`
  # across the crate (~900+ extra mutants).
  FILE_FLAGS+=( --file "**/$SCOPE/$f" )
done

echo "scope:       $SCOPE  (${#FILES[@]} files)"
echo "jobs:        $JOBS"
echo "timeout x:   $TIMEOUT_MUL"
echo "results:     $RESULTS"
echo "scratch:     $TMP"
echo

cd "$REPO/rust/crates/lfs_core"
# cargo-mutants exits 2 when at least one mutant survives — that's
# the normal "found dirty spots" outcome, not a wrapper failure.
# Capture the code, run the summary, then forward it.
set +e
TMPDIR="$TMP" cargo mutants \
  "${FILE_FLAGS[@]}" \
  --jobs "$JOBS" \
  --timeout-multiplier "$TIMEOUT_MUL" \
  --output "$RESULTS"
RC=$?
set -e

# cargo-mutants writes per-outcome lists under mutants.out/. Each
# *.txt file holds one mutant per line, prefixed with the source
# path — perfect for a wc + awk roll-up that needs no host deps
# beyond the POSIX shell tools we already rely on.
OUT_DIR="$RESULTS/mutants.out"
if [[ -d "$OUT_DIR" ]]; then
  caught=$(wc -l <"$OUT_DIR/caught.txt"   2>/dev/null || echo 0)
  missed=$(wc -l <"$OUT_DIR/missed.txt"   2>/dev/null || echo 0)
  unv=$(   wc -l <"$OUT_DIR/unviable.txt" 2>/dev/null || echo 0)
  to=$(    wc -l <"$OUT_DIR/timeout.txt"  2>/dev/null || echo 0)
  caught_total=$((caught + to))
  testable=$((caught_total + missed))
  echo
  echo "── Mutation summary (lfs_core::$SCOPE) ──"
  echo "  caught $caught_total  missed $missed  unviable $unv  (total $((testable + unv)))"
  if [[ $testable -gt 0 ]]; then
    # Bash has no float math; awk is the standard tool for the
    # mutation-score percentage.
    awk -v c="$caught_total" -v t="$testable" \
      'BEGIN { printf "  mutation score: %.1f%%  (%d/%d)\n", 100.0 * c / t, c, t }'
  fi
  echo
  printf '  %6s %6s %6s  file\n' caught missed score
  # Build per-file caught / missed counts with awk over both
  # outcome lists, then emit a sorted (worst first) table.
  awk -v out="$OUT_DIR" '
    function strip(s) {
      sub(/^crates\/lfs_core\/src\//, "", s)
      sub(/^crates\/lfs_frb\/src\/api\//, "frb::", s)
      return s
    }
    BEGIN {
      while ((getline line < (out "/caught.txt")) > 0) {
        split(line, a, ":"); caught[a[1]]++
      }
      while ((getline line < (out "/timeout.txt")) > 0) {
        split(line, a, ":"); caught[a[1]]++
      }
      while ((getline line < (out "/missed.txt")) > 0) {
        split(line, a, ":"); missed[a[1]]++
      }
      for (f in caught) files[f]
      for (f in missed) files[f]
      n = 0
      for (f in files) {
        order[++n] = f
      }
      # Sort descending by missed count.
      for (i = 1; i <= n; i++) {
        for (j = i + 1; j <= n; j++) {
          if (missed[order[j]] > missed[order[i]]) {
            t = order[i]; order[i] = order[j]; order[j] = t
          }
        }
      }
      for (i = 1; i <= n; i++) {
        f = order[i]; c = caught[f] + 0; m = missed[f] + 0
        total = c + m
        score = total ? (100.0 * c / total) : 0
        printf "  %6d %6d %5.1f%%  %s\n", c, m, score, strip(f)
      }
    }'
fi
# Forward cargo-mutants exit code so CI / make-target pipelines can
# decide whether to fail the build on surviving mutants.
exit "$RC"
