---
name: analyze
description: Run Dart analyzer via make analyze. Use when user wants to check code for lint/analysis issues before commit.
---

Run the Dart analyzer:

```!
make analyze 2>&1
```

Report the results concisely:
- If clean (0 issues): say "Analyzer: clean" and nothing else
- If issues found: list each issue with file:line and the message. Group by file. Do NOT attempt to fix anything unless the user explicitly asks
