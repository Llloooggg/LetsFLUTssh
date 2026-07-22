#!/usr/bin/env bash
# Agent-only plan-ID gate. Installed as the `commit-msg` hook by
# `dev/scripts/install-hooks.sh`.
#
# Fires only when the commit message carries a
# Fires on every commit — scans for plan-item IDs in commit messages and diffs.
# skip the check entirely.
#
# Project rule: docs/AGENT_RULES.md § Plan-Item IDs Stay Internal.
# No agent-internal IDs in commits, code, or any tracked artefact.
# Stable `§N.M` doc anchors to ARCHITECTURE.md remain legitimate.
#
# What gets scanned:
#   1. The commit message itself (subject + body).
#   2. The staged diff (added lines only).
# Earlier shape scanned only the diff, so plan-IDs landed in commit
# subjects/bodies even though file content was clean.
#
# Patterns blocked:
#   Old shortcodes:    B-XXX-N, PAT-X, A20/A21/A22, Phase X, Task N.M
#   Audit-sweep forms: `audit P[0-9]+`, `audit P[N] items`, `P[N] sweep`,
#                      `Closes audit`, `(axis NN)`, `Audit Axis N High`,
#                      `chore(p[N]-sweep)`, plan filenames
#                      (`audit-consolidated-findings-YYYY-MM-DD.md`,
#                      `audit-fix-plan-YYYY-MM-DD.md`).
#
# Allowlist (path level) for the diff scan:
#   docs/AGENT_RULES.md, AGENTS.md, .opencode/plans/, fonts/LICENSES/,
#   this script. They describe the rule by literal example.
# The commit-message scan has no path context — it allows the
# directory mention `.opencode/plans/` (AGENTS.md references it as a
# canonical location) but blocks specific plan filenames.
#
# No bypass flag by design. The maintainer can drop the
# No bypass flag by design.
set -euo pipefail

msg_file="$1"


# Path-level allowlist for the staged-diff scan.
allowlist_re='^(docs/AGENT_RULES\.md|AGENTS\.md|\.opencode/plans/|assets/fonts/LICENSES/|dev/scripts/agent-plan-id-gate\.sh)'

# Plan-id shapes per docs/AGENT_RULES.md § Plan-Item IDs Stay
# Internal. mawk does not support `\b` reliably; explicit
# character-class boundaries on the bare A-numeric ladder so
# A11Y / A22Z don't false-positive.
plan_id_re='B-[A-Z][A-Z0-9]*-[0-9]+|PAT-[A-Z][^A-Za-z0-9]|P[0-3]-[0-9]+|(^|[^A-Za-z0-9])A(11|12|20|21|22)([^A-Za-z0-9]|$)|Phase [A-Z]?[0-9]|Task [0-9]+\.[0-9]+|[Aa]udit P[0-9]+|Audit Axis [0-9]+|Closes audit|\(axis [0-9]+\)|audit-consolidated-findings-[0-9]{4}-[0-9]{2}-[0-9]{2}|audit-fix-plan-[0-9]{4}-[0-9]{2}-[0-9]{2}|p[0-9]+-sweep|P[0-9]+ items?|P[0-9]+ sweep|P[0-9]+ list'

# ----- 1. commit-message scan -----
# The message file has no path context; the rule applies verbatim.
# A commit that has to discuss the rule (the hook itself, AGENT_RULES
# updates) is rare enough that we don't allowlist by subject — the
# maintainer can edit for those edits,
# matching the path-allowlist's posture.
msg_violations="$(grep -nE "$plan_id_re" "$msg_file" || true)"

# ----- 2. staged-diff scan -----
diff_violations="$(
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

if [ -n "$msg_violations" ] || [ -n "$diff_violations" ]; then
    cat >&2 <<'HEADER'

❌ Agent plan-ID gate: plan-item IDs in commit content.

HEADER
    if [ -n "$msg_violations" ]; then
        echo "Commit message:" >&2
        echo "$msg_violations" | head -20 | sed 's/^/  /' >&2
    fi
    if [ -n "$diff_violations" ]; then
        echo "Staged diff:" >&2
        echo "$diff_violations" | head -20 | sed 's/^/  /' >&2
    fi
    cat >&2 <<'TRAILER'

Rule: docs/AGENT_RULES.md § Plan-Item IDs Stay Internal —
no agent-internal IDs (B-XXX-N, PAT-X, A20/A21/A22, Phase X,
Task N.M, "audit P2 items", "Audit Axis N High #M", "Closes
audit P2 (axis NN)", "p2-sweep", "audit-consolidated-findings-*.md")
in commits, code, or any tracked artefact. Stable §N.M doc
anchors to ARCHITECTURE.md are fine. The directory mention
`.opencode/plans/` is fine; specific plan filenames are not.

Edit the staged content + commit message to drop the IDs
(rephrase as load-bearing prose), `git add` the fixes, retry
the commit.
TRAILER
    exit 1
fi

exit 0
