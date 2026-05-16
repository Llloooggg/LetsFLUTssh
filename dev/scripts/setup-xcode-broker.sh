#!/usr/bin/env bash
# Ensure SecurityKeyBroker.swift is wired into the Xcode Runner targets
# for both macOS and iOS. Runs once per fork after `git clone`; idempotent.
#
# The system-FIDO2 broker path (lfs_os_security::fido2_broker::apple)
# depends on the two Swift glue files under macos/Runner/ and ios/Runner/
# being compiled by Xcode as part of the Runner target. Most recent Xcode
# versions (15+) auto-detect new Swift files under the Runner/ source
# root the first time the project opens; older versions need a manual
# drag-into-Compile-Sources. This script verifies the wire is in place
# and either succeeds silently or prints the exact Xcode UI steps.
#
# Exit codes:
#   0 — both targets reference SecurityKeyBroker.swift (or non-Apple host)
#   1 — at least one target missing; manual Xcode add required

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Non-Apple hosts have no Xcode; the broker entitlement / Swift glue is
# meaningless there. Linux / Windows devs should never run this.
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "setup-xcode-broker: not on macOS, nothing to do."
  exit 0
fi

missing=0

check_target() {
  local label="$1"
  local pbxproj="$2"
  local swift_file="$3"

  if [[ ! -f "$pbxproj" ]]; then
    echo "setup-xcode-broker: $label pbxproj not found at $pbxproj"
    missing=1
    return
  fi

  if grep -qF "SecurityKeyBroker.swift" "$pbxproj"; then
    echo "setup-xcode-broker: $label — SecurityKeyBroker.swift already wired."
    return
  fi

  echo
  echo "setup-xcode-broker: $label — SecurityKeyBroker.swift NOT in project.pbxproj."
  echo "  Add it via Xcode (one-time, post-clone):"
  echo "    1. open $(dirname "$pbxproj")/.."
  echo "    2. In the Project Navigator, right-click the 'Runner' folder → 'Add Files to \"Runner\"…'."
  echo "    3. Select $swift_file. Confirm 'Add to targets: Runner' is checked."
  echo "    4. Build once: Product → Build (⌘B)."
  missing=1
}

check_target "macOS" \
  "$REPO_ROOT/macos/Runner.xcodeproj/project.pbxproj" \
  "$REPO_ROOT/macos/Runner/SecurityKeyBroker.swift"

check_target "iOS" \
  "$REPO_ROOT/ios/Runner.xcodeproj/project.pbxproj" \
  "$REPO_ROOT/ios/Runner/SecurityKeyBroker.swift"

if (( missing )); then
  echo
  echo "setup-xcode-broker: one or both Xcode targets need the manual add above."
  echo "  Re-run \`dev/scripts/setup-xcode-broker.sh\` after the file is in place; it will pass silently."
  exit 1
fi

echo "setup-xcode-broker: both Runner targets compile SecurityKeyBroker.swift."
