---
name: lint
description: Run static analysis (Dart analyzer + Rust clippy) via make lint. Use when user wants to check code for lint/analysis issues before commit.
---

Run static analysis on both languages:

```!
make lint 2>&1
```

Report the results concisely:
- If clean (0 issues): say "Lint: clean" and nothing else
- If issues found: list each issue with file:line and the message. Group by file. Do NOT attempt to fix anything unless the user explicitly asks
