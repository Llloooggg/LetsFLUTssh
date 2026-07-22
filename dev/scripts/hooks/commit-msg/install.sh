#!/usr/bin/env bash
# Install commit-msg hook (symlink to commit-msg-gate.sh)
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../../.." && pwd)"
hook_dir="$repo_root/.git/hooks"
ln -sf "$script_dir/script.sh" "$hook_dir/commit-msg"
chmod +x "$repo_root/dev/scripts/commit-msg-gate.sh"
echo "commit-msg: installed (symlink)"
