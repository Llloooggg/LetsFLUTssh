#!/usr/bin/env bash
# Agent-only plan-ID gate. Installed as the `commit-msg` hook by
# `scripts/install-hooks.sh`.
#
# Fires only when the commit message carries a
# `Co-Authored-By: Claude` trailer — the maintainer's own commits
# skip the check entirely.
#
# Project rule: docs/AGENT_RULES.md § Plan-Item IDs Stay Internal.
# No agent-internal IDs (`B-XXX-N`, `PAT-X`, `A20`/`A21`/`A22`,
# `Phase X`, `Task N.M`) in commits, code, or any tracked
# artefact. Stable `§N.M` doc anchors to ARCHITECTURE.md remain
# legitimate.
#
# No bypass flag by design — the gate exists because the agent
# shipped the same violation twice in one session. A bypass
# would re-open the failure mode. The maintainer can drop the
# `Co-Authored-By: Claude` trailer to ship a non-agent commit.
set -euo pipefail

msg_file="$1"

if ! grep -qiE '^Co-Authored-By:.*Claude' "$msg_file"; then
    exit 0
fi

# Path-level allowlist — these files describe the rule itself
# (literal examples of the banned shapes).
allowlist_re='^(docs/AGENT_RULES\.md|CLAUDE\.md|\.claude/plans/|assets/fonts/LICENSES/|scripts/agent-plan-id-gate\.sh)'

# Plan-id shapes per docs/AGENT_RULES.md § Plan-Item IDs Stay
# Internal. mawk does not support `\b` / `\<...\>` word
# boundaries reliably, so use explicit character-class boundaries
# where false positives are realistic (the bare A-numeric needs
# boundaries to avoid `A11Y` / `A22Z` hits; the dashed shapes
# are distinctive enough on their own).
plan_id_re='B-[A-Z][A-Z0-9]*-[0-9]+|PAT-[A-Z][^A-Za-z0-9]|P[0-3]-[0-9]+|audits?[[:space:]'"'"'][a-z[:space:]]*[A-Z][0-9]|(^|[^A-Za-z0-9])A(11|12|20|21|22)([^A-Za-z0-9]|$)|Phase [A-Z]?[0-9]|Task [0-9]+\.[0-9]+'

# Walk the staged diff. Track the most recent `+++ b/<file>`
# header so matches on `^+` content lines attribute to the right
# file; allowlist hits flip a `skip` flag for the rest of the
# hunk.
violations="$(
    git diff --cached -U0 --diff-filter=AM | \
    awk -v re="$plan_id_re" -v allow="$allowlist_re" '
        /^\+\+\+ b\// {
            file = $0
            sub(/^\+\+\+ b\//, "", file)
            if (file ~ allow) skip = 1; else skip = 0
            next
        }
        /^\+\+\+ \/dev\/null/ { skip = 1; next }
        /^\+/ && !skip {
            line = $0
            sub(/^\+/, "", line)
            if (line ~ re) {
                print file ":" line
            }
        }
    '
)"

if [ -n "$violations" ]; then
    cat >&2 <<'HEADER'

❌ Agent plan-ID gate: staged diff contains plan-item IDs.

HEADER
    echo "$violations" | head -20 >&2
    cat >&2 <<'TRAILER'

Rule: docs/AGENT_RULES.md § Plan-Item IDs Stay Internal —
no agent-internal IDs (B-XXX-N, PAT-X, A20/A21/A22, Phase X,
Task N.M) in commits, code, or any tracked artefact. Stable
§N.M doc anchors to ARCHITECTURE.md are fine.

Edit the staged content to drop the IDs (rephrase as
load-bearing prose), `git add` the fixes, retry the commit.
TRAILER
    exit 1
fi

exit 0
