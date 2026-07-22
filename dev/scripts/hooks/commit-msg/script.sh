#!/usr/bin/env bash
# commit-msg hook: symlink to commit-msg-gate.sh in same dir
# $0 is the symlink path (.git/hooks/commit-msg)
# dirname gives .git/hooks/
# We need to go up to find the script dir

# Resolve the symlink to get the real path
real_path="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
real_dir="$(dirname "$real_path")"

exec bash "$real_dir/commit-msg-gate.sh" "$@"
