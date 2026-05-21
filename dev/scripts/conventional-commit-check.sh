#!/usr/bin/env bash
# Conventional-commit subject validator — the single source of the
# commit-message format rule, shared by the local commit-msg hook
# (--file) and CI's commit-lint job (--range) so the two can never
# drift. Format reference: docs/CONTRIBUTING.md → Commit messages.
#
# Usage:
#   conventional-commit-check.sh --file <commit-msg-file>
#   conventional-commit-check.sh --range <git-range>
#
# Exit 0 when every checked subject conforms; exit 1 (listing the
# offending subjects) otherwise; exit 2 on usage error.
set -euo pipefail

# Types accepted in commit subjects. First group is canonical
# conventional-commits; the second is project-specific extensions kept
# after historical use (hardening = defence-in-depth raise distinct
# from a bug fix; diag = incident/boot instrumentation; format = pure
# formatting passes; recorder/sftp/ratelimit/rust = area shorthands).
TYPES='feat|fix|refactor|perf|build|test|docs|chore|ci|i18n|l10n|style|revert|security|hardening|diag|format|recorder|sftp|ratelimit|rust'
# Scope chars accepted inside (...). Comma + space accept historical
# multi-area scopes such as `refactor(rust,db)` / `refactor(a + b)`.
SCOPE='[a-z0-9_+/, -]+'
PATTERN="^(${TYPES})(\\(${SCOPE}\\))?!?: \\S.+"

# Exact-match subjects grandfathered from before the convention: the
# feat/rust-core long-running branch already merged them, so `make pr`
# must keep accepting them. Pinned exact-match, not a looser regex.
GRANDFATHERED=(
  "docs(rules) + chore: strengthen Comments rule, scrub retrospective comments"
)

# A subject that needs no validation: merges, dependabot bumps,
# git-default reverts, and the grandfathered exact subjects.
skip_subject() {
  local msg="$1" g
  [[ "$msg" == Merge\ * ]] && return 0
  [[ "$msg" == Bump\ * ]] && return 0
  [[ "$msg" == Revert\ \"* ]] && return 0
  for g in "${GRANDFATHERED[@]}"; do
    [[ "$msg" == "$g" ]] && return 0
  done
  return 1
}

validate_subject() {
  local msg="$1"
  skip_subject "$msg" && return 0
  printf '%s' "$msg" | grep -qE "$PATTERN"
}

print_help() {
  cat >&2 <<'TRAILER'

Expected: type(scope)?: short description
Canonical types: feat, fix, refactor, perf, build, test, docs, chore,
                 ci, i18n, l10n, style, revert, security
Extension types: hardening, diag, format, recorder, sftp, ratelimit, rust
See docs/CONTRIBUTING.md → Commit messages.
TRAILER
}

mode="${1:-}"
arg="${2:-}"

case "$mode" in
  --file)
    [[ -n "$arg" ]] || { echo "usage: $0 --file <commit-msg-file>" >&2; exit 2; }
    subject="$(sed -n '1p' "$arg")"
    if ! validate_subject "$subject"; then
      echo "❌ commit-msg: subject does not follow the convention:" >&2
      echo "  ✗ $subject" >&2
      print_help
      exit 1
    fi
    ;;
  --range)
    [[ -n "$arg" ]] || { echo "usage: $0 --range <git-range>" >&2; exit 2; }
    commits="$(git log --format='%s' "$arg")"
    # A mistaken commit reverted within the same range should not block:
    # accepts git-default `Revert "…"` and conventional `revert: "…"`.
    reverted="$(printf '%s\n' "$commits" | sed -nE 's/^(Revert |revert: )"([^"]+)".*/\2/p')"
    errors=""
    while IFS= read -r msg; do
      [[ -z "$msg" ]] && continue
      if [[ -n "$reverted" ]] && printf '%s\n' "$reverted" | grep -qxF "$msg"; then
        continue
      fi
      validate_subject "$msg" || errors+="  ✗ ${msg}"$'\n'
    done <<< "$commits"
    if [[ -n "$errors" ]]; then
      echo "❌ commit-lint: some commit subjects don't follow the convention:" >&2
      printf '%b' "$errors" >&2
      print_help
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 --file <commit-msg-file> | --range <git-range>" >&2
    exit 2
    ;;
esac

echo "commit subjects conform to the convention ✓"
