#!/usr/bin/env bash
set -euo pipefail

# Calculates the semver bump from conventional commits since the last tag,
# updates pubspec.yaml, and commits. Run on dev before creating a PR to main.
#
# Bump rules:
#   BREAKING CHANGE / feat!:                                              → major
#   feat:                                                                 → minor
#   fix: / refactor: / perf: / build: / security: / i18n: / l10n: /
#     Dependabot "Bump ..."                                               → patch
#   docs: / test: / ci: / chore: / style: / revert:                       → no bump
#
# Dependabot-specific overrides (parsed from the commit body trailer
# Dependabot stamps on every PR):
#   dependency-type: direct:development                                   → no bump
#   dependency-type: indirect                                             → no bump
#   dependency-name: <org>/<repo> (GitHub Actions ecosystem)              → no bump
# Dev-deps + transitive deps + CI tooling bumps don't reach the shipped
# binary, so they have no business stamping a release tag.
#
# Usage: dev/scripts/bump-version.sh [--dry-run]

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

# Pull latest tags from origin so LAST_TAG reflects what was actually
# released, not just what happens to be in the local store. Without this
# fetch, a local clone that doesn't track remote tags computes the commit
# range against a stale LAST_TAG, which replays the previous release's
# fix/refactor/feat commits into the next bump and publishes empty
# "Maintenance release." notes for patches whose real diff is test/doc
# only. Silent on offline / no remote.
git fetch --tags --quiet origin 2>/dev/null || true

# Find the latest version tag
LAST_TAG=$(git tag -l 'v*' --sort=-v:refname | head -1)
if [ -z "$LAST_TAG" ]; then
  RANGE="HEAD"
else
  RANGE="${LAST_TAG}..HEAD"
fi

echo "Last tag: ${LAST_TAG:-<none>}"
echo "Commit range: $RANGE"

BUMP="none"  # none | patch | minor | major

# Returns 0 (true) when `$1` names a package in any local manifest's
# dev / build-only section: `dev_dependencies:` in `pubspec.yaml`
# (Dart) or `[dev-dependencies]` / `[build-dependencies]` in any
# `Cargo.toml` under `rust/` (Cargo). Returns 1 otherwise. Used to
# override Dependabot's `dependency-type:` trailer, which marks every
# Dart-pub entry as `direct:production` regardless of which section
# the manifest lists it under.
is_dev_dep() {
  local name="$1"
  if [ -z "$name" ]; then
    return 1
  fi
  # Runtime presence wins. `tokio` (and friends) live in both
  # `[dependencies]` and `[dev-dependencies]` of the same crate;
  # a bump there is a runtime change and must drive a patch. Only
  # when every occurrence sits in a dev / build section do we
  # treat the bump as non-release-affecting.
  if awk -v name="$name" '
      /^dependencies:[[:space:]]*$/ { in_run=1; in_dev=0; next }
      /^dev_dependencies:[[:space:]]*$/ { in_run=0; in_dev=1; next }
      /^[a-z_]+:[[:space:]]*$/ { in_run=0; in_dev=0; next }
      in_run && $0 ~ "^[[:space:]]+" name "[[:space:]]*:" { has_run=1 }
      in_dev && $0 ~ "^[[:space:]]+" name "[[:space:]]*:" { has_dev=1 }
      END {
        if (has_run) { exit 2 }
        if (has_dev) { exit 0 }
        exit 1
      }
    ' pubspec.yaml 2>/dev/null; then
    return 0
  fi
  local pub_exit=$?
  if [ "$pub_exit" = "2" ]; then
    return 1
  fi
  local has_runtime=0
  local has_dev_only=0
  while IFS= read -r -d '' toml; do
    awk -v name="$name" '
        FNR == 1 { in_run=0; in_dev=0 }
        /^\[dependencies\]/ { in_run=1; in_dev=0; next }
        /^\[dev-dependencies\]/ || /^\[build-dependencies\]/ { in_run=0; in_dev=1; next }
        /^\[/ { in_run=0; in_dev=0; next }
        in_run && $0 ~ "^" name "[[:space:]]*=" { has_run=1 }
        in_dev && $0 ~ "^" name "[[:space:]]*=" { has_dev=1 }
        END {
          if (has_run) { exit 2 }
          if (has_dev) { exit 0 }
          exit 1
        }
      ' "$toml" 2>/dev/null
    local rc=$?
    if [ "$rc" = "2" ]; then
      has_runtime=1
    elif [ "$rc" = "0" ]; then
      has_dev_only=1
    fi
  done < <(find rust -name Cargo.toml -print0 2>/dev/null)
  if [ "$has_runtime" = "1" ]; then
    return 1
  fi
  if [ "$has_dev_only" = "1" ]; then
    return 0
  fi
  return 1
}

# Read SHA + subject pairs so we can fetch each commit's body
# separately. Dependabot stamps a YAML-ish trailer in the body
# describing the dependency type / name / version; we need it to
# tell a release-affecting bump (`direct:production` runtime dep)
# apart from a dev-dep / transitive / GitHub-Action bump that has
# no business stamping a tag.
while IFS=$'\t' read -r SHA MSG; do
  [ -z "$SHA" ] && continue

  # Skip merge commits
  echo "$MSG" | grep -qE '^Merge ' && continue

  # Skip version-bump commits
  echo "$MSG" | grep -qE '^chore: bump version ' && continue

  # Skip revert commits — both git's default `Revert "..."` form and
  # our conventional `revert: ...` form. A commit that cancels another
  # out should not drive the release forward on its own; if the reverted
  # commit itself was already released, the revert ships as part of the
  # next bumpable change (fix/feat/etc).
  echo "$MSG" | grep -qE '^Revert "' && continue
  echo "$MSG" | grep -qE '^revert(\([a-z0-9_-]+\))?: ' && continue

  # BREAKING CHANGE → major
  if echo "$MSG" | grep -qiE 'BREAKING CHANGE|^[a-z]+(\([a-z0-9_-]+\))?!:'; then
    BUMP="major"
    continue
  fi

  # Skip non-bumping types. `style` is pure formatting and `revert` is
  # handled above; both stay here in the regex so future readers see the
  # full set of no-bump prefixes in one place.
  echo "$MSG" | grep -qE '^(docs|test|ci|chore|style)(\([a-z0-9_-]+\))?: ' && continue

  # feat → minor
  if echo "$MSG" | grep -qE '^feat(\([a-z0-9_-]+\))?: '; then
    [ "$BUMP" != "major" ] && BUMP="minor"
    continue
  fi

  # Dependabot trailer probe — applies to both the conventional
  # `build(deps):` / `chore(deps):` shape and the raw `Bump X from
  # Y to Z` subject. The trailer lives in the commit body
  # (`updated-dependencies:` + `dependency-name:` + `dependency-type:`
  # + `update-type:`); we fetch it on demand only when the subject
  # looks bumpish, so the body read budget stays bounded to actual
  # dependency commits.
  #
  # Three signals reject the bump (CI / dev / transitive doesn't
  # reach the shipped binary, no business stamping a release):
  #   - `dependency-name: <org>/<repo>` — GitHub Actions
  #     ecosystem (slash in the name is the unique signal).
  #   - `dependency-type: indirect` — transitive dep already
  #     pinned by a direct one; no user-visible change.
  #   - `dependency-name` resolves to a `dev_dependencies:` entry
  #     in the CURRENT `pubspec.yaml` (Dart) or a `[dev-dependencies]`
  #     / `[build-dependencies]` entry in any `Cargo.toml` under
  #     `rust/` (Cargo). Dependabot for Dart stamps `direct:production`
  #     even when the entry sits in `dev_dependencies:` (the trailer
  #     is unreliable on its own), so the manifest is the source of
  #     truth for the dev / runtime split.
  DEPBOT_SKIP=false
  if echo "$MSG" | grep -qE '^(build|fix|refactor|perf|security)(\([a-z0-9_-]+\))?: bump |^Bump .+ from .+ to '; then
    BODY=$(git log -1 --format='%b' "$SHA" 2>/dev/null || true)
    DEP_NAME=$(echo "$BODY" | grep -oE '^[[:space:]]*-?[[:space:]]*dependency-name:[[:space:]]*[^[:space:]]+' | head -1 | sed 's/.*dependency-name:[[:space:]]*//')
    if [ -n "$DEP_NAME" ] && echo "$DEP_NAME" | grep -q '/'; then
      DEPBOT_SKIP=true
    elif echo "$BODY" | grep -qE '^[[:space:]]*dependency-type:[[:space:]]*indirect\b'; then
      DEPBOT_SKIP=true
    elif [ -n "$DEP_NAME" ] && is_dev_dep "$DEP_NAME"; then
      DEPBOT_SKIP=true
    fi
  fi
  if [ "$DEPBOT_SKIP" = true ]; then
    echo "  · skip non-runtime dep bump: $MSG"
    continue
  fi

  # fix / refactor / perf / build / security / i18n / l10n → patch.
  # `security` is treated like `fix` — a vulnerability / hardening
  # change is always at least a patch bump. `i18n` / `l10n` also
  # trigger a patch so a translation-only release cycle still ships:
  # without this, running the bump script on a window that contained
  # only `l10n:` commits would report "nothing to bump", no tag would
  # be cut, and updated strings would never reach users.
  if echo "$MSG" | grep -qE '^(fix|refactor|perf|build|security|i18n|l10n)(\([a-z0-9_-]+\))?: '; then
    [ "$BUMP" = "none" ] && BUMP="patch"
    continue
  fi

  # Dependabot raw format: "Bump X from Y to Z"
  if echo "$MSG" | grep -qE '^Bump .+ from .+ to '; then
    [ "$BUMP" = "none" ] && BUMP="patch"
    continue
  fi

done <<< "$(git log "$RANGE" --format='%H%x09%s' --no-merges)"

if [ "$BUMP" = "none" ]; then
  echo "No version-affecting commits since ${LAST_TAG:-start} — nothing to bump"
  exit 0
fi

# Read current version
FULL=$(grep '^version:' pubspec.yaml | sed 's/version: *//')
VER="${FULL%%+*}"
BUILD="${FULL##*+}"

MAJOR="${VER%%.*}"
REST="${VER#*.}"
MINOR="${REST%%.*}"
PATCH="${REST#*.}"

# Calculate new version
case "$BUMP" in
  major) NEW_MAJOR=$((MAJOR+1)); NEW_MINOR=0; NEW_PATCH=0 ;;
  minor) NEW_MAJOR=$MAJOR; NEW_MINOR=$((MINOR+1)); NEW_PATCH=0 ;;
  patch) NEW_MAJOR=$MAJOR; NEW_MINOR=$MINOR; NEW_PATCH=$((PATCH+1)) ;;
esac
NEW_BUILD=$((BUILD+1))
NEW_VER="${NEW_MAJOR}.${NEW_MINOR}.${NEW_PATCH}"

echo "Bump: $BUMP"
echo "Version: ${VER} → ${NEW_VER} (build ${BUILD} → ${NEW_BUILD})"

if [ "$DRY_RUN" = true ]; then
  echo "(dry run — no changes made)"
  exit 0
fi

# Update pubspec.yaml
sed -i "s/^version: .*/version: ${NEW_VER}+${NEW_BUILD}/" pubspec.yaml

# Commit
git add pubspec.yaml
git commit -m "chore: bump version ${VER} → ${NEW_VER}"

echo "Done. Version bumped to ${NEW_VER}+${NEW_BUILD}"
