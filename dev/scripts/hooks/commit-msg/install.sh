#!/usr/bin/env bash
# Install commit-msg hook (symlink to script.sh)
script_dir="$(cd "$(dirname "$0")" && pwd)"
hook_dir="$script_dir/../../../../.git/hooks"
ln -sf "$script_dir/script.sh" "$hook_dir/commit-msg"
chmod +x "$script_dir/commit-msg-gate.sh"
echo "commit-msg: installed (symlink)"
