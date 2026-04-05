#!/bin/bash
# PostToolUse hook: auto-run flutter gen-l10n after editing .arb files
# Reads tool JSON from stdin, extracts file path, runs gen-l10n if .arb

read -r input
file=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
f = d.get('tool_input', {}).get('file_path', '') or d.get('tool_response', {}).get('filePath', '')
print(f)
" "$input" 2>/dev/null)

if [[ "$file" == *.arb && -f "$file" ]]; then
    flutter gen-l10n 2>/dev/null
fi
exit 0
