#!/usr/bin/env bash
# Verify every non-English ARB file declares the same set of message keys
# as app_en.arb (the source-of-truth template). Missing keys mean a
# translator has nothing to localise, and any S.of(context).newKey call
# would crash at runtime in that locale.
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

python3 - "$TEMPLATE" "$ARB_DIR" <<'PY'
import json, os, sys, glob

template_path, arb_dir = sys.argv[1], sys.argv[2]

def keys_of(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return {k for k in data.keys() if not k.startswith("@")}

expected = keys_of(template_path)
if not expected:
    print(f"check-arb-parity: template {template_path} has no message keys", file=sys.stderr)
    sys.exit(2)

failed = False
for arb in sorted(glob.glob(os.path.join(arb_dir, "app_*.arb"))):
    if os.path.abspath(arb) == os.path.abspath(template_path):
        continue
    locale = os.path.splitext(os.path.basename(arb))[0]
    actual = keys_of(arb)
    missing = sorted(expected - actual)
    if missing:
        failed = True
        print(f"::error file={arb}::{locale} is missing {len(missing)} key(s) present in app_en.arb")
        print(f"Missing keys in {locale}:", file=sys.stderr)
        for k in missing:
            print(f"  - {k}", file=sys.stderr)

if failed:
    print("check-arb-parity: at least one locale is incomplete", file=sys.stderr)
    sys.exit(1)
print(f"check-arb-parity: every locale in {arb_dir} matches en")
PY
