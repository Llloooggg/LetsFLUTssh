#!/usr/bin/env bash
# Verify every non-English ARB file declares the same set of message keys
# as app_en.arb (the source-of-truth template). Missing keys mean a
# translator has nothing to localise, and any S.of(context).newKey call
# would crash at runtime in that locale.
#
# Requires `jq` on PATH. GitHub-hosted ubuntu-latest runners ship with
# jq pre-installed.
#
# Exit codes:
#   0 — every locale matches en
#   1 — at least one locale is missing keys (printed to stderr)
#   2 — invocation / IO problem

set -euo pipefail

ARB_DIR="${ARB_DIR:-lib/l10n}"
TEMPLATE="${ARB_DIR}/app_en.arb"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "check-arb-parity: template not found at $TEMPLATE" >&2
  exit 2
fi

if ! command -v jq >/dev/null; then
  echo "check-arb-parity: jq not found on PATH" >&2
  exit 2
fi

# All keys that don't start with @ (those are ICU metadata, not messages).
expected_keys=$(jq -r 'keys[] | select(startswith("@") | not)' "$TEMPLATE" | sort -u)

if [[ -z "$expected_keys" ]]; then
  echo "check-arb-parity: template $TEMPLATE has no message keys" >&2
  exit 2
fi

failed=0
checked=0
for arb in "$ARB_DIR"/app_*.arb; do
  [[ "$arb" == "$TEMPLATE" ]] && continue
  checked=$((checked + 1))
  locale_name=$(basename "$arb" .arb)
  actual_keys=$(jq -r 'keys[] | select(startswith("@") | not)' "$arb" | sort -u)
  missing=$(comm -23 <(echo "$expected_keys") <(echo "$actual_keys"))
  if [[ -n "$missing" ]]; then
    failed=1
    count=$(echo "$missing" | wc -l | tr -d ' ')
    echo "::error file=$arb::$locale_name is missing $count key(s) present in app_en.arb"
    echo "Missing keys in $locale_name:" >&2
    echo "$missing" | sed 's/^/  - /' >&2
  fi
done

if [[ "$failed" -ne 0 ]]; then
  echo "check-arb-parity: at least one locale is incomplete" >&2
  exit 1
fi

echo "check-arb-parity: all $checked locale ARB files match app_en.arb"
