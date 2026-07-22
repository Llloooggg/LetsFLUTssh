#!/usr/bin/env bash
# commit-msg hook: symlink to dev/scripts/commit-msg-gate.sh
#
# This file is a symlink target. The actual hook is commit-msg-gate.sh.

exec bash "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/dev/scripts/commit-msg-gate.sh" "$@"
