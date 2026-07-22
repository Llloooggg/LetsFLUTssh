#!/usr/bin/env bash
# Install pre-push hook
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../../.." && pwd)"
hook_dir="$repo_root/.git/hooks"
cp "$script_dir/script.sh" "$hook_dir/pre-push"
chmod +x "$hook_dir/pre-push"
echo "pre-push: installed"
