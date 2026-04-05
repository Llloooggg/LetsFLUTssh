#!/bin/bash
# PostToolUse hook: auto-format .dart files after Edit/Write
# Reads tool JSON from stdin, extracts file path, runs dart format if .dart

read -r input
file=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
f = d.get('tool_input', {}).get('file_path', '') or d.get('tool_response', {}).get('filePath', '')
print(f)
" "$input" 2>/dev/null)

if [[ "$file" == *.dart && -f "$file" ]]; then
    dart format "$file" 2>/dev/null
fi
exit 0
