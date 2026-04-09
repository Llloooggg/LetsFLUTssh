#!/usr/bin/env bash
set -euo pipefail

# Calculates the semver bump from conventional commits since the last tag,
# updates pubspec.yaml, and commits. Run on dev before creating a PR to main.
#
# Bump rules:
#   BREAKING CHANGE / feat!:  → major
#   feat:                     → minor
#   fix: / refactor: / perf: / build: / Dependabot "Bump ..." → patch
#   docs: / test: / ci: / chore: → no bump
#
# Usage: scripts/bump-version.sh [--dry-run]

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

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

while IFS= read -r MSG; do
  [ -z "$MSG" ] && continue

  # Skip merge commits
  echo "$MSG" | grep -qE '^Merge ' && continue

  # Skip version-bump commits
  echo "$MSG" | grep -qE '^chore: bump version ' && continue

  # Skip revert commits
  echo "$MSG" | grep -qE '^Revert "' && continue

  # BREAKING CHANGE → major
  if echo "$MSG" | grep -qiE 'BREAKING CHANGE|^[a-z]+(\([a-z0-9_-]+\))?!:'; then
    BUMP="major"
    continue
  fi

  # Skip non-bumping types
  echo "$MSG" | grep -qE '^(docs|test|ci|chore)(\([a-z0-9_-]+\))?: ' && continue

  # feat → minor
  if echo "$MSG" | grep -qE '^feat(\([a-z0-9_-]+\))?: '; then
    [ "$BUMP" != "major" ] && BUMP="minor"
    continue
  fi

  # fix / refactor / perf / build → patch
  if echo "$MSG" | grep -qE '^(fix|refactor|perf|build)(\([a-z0-9_-]+\))?: '; then
    [ "$BUMP" = "none" ] && BUMP="patch"
    continue
  fi

  # Dependabot raw format: "Bump X from Y to Z"
  if echo "$MSG" | grep -qE '^Bump .+ from .+ to '; then
    [ "$BUMP" = "none" ] && BUMP="patch"
    continue
  fi

done <<< "$(git log "$RANGE" --format='%s' --no-merges)"

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
