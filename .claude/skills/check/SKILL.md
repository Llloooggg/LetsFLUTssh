---
name: check
description: Run analyzer + tests sequentially via make check. Full pre-commit validation.
---

Run full pre-commit validation (analyzer first, then tests):

```!
make check 2>&1
```

Report results concisely:
- If both pass: "Check: analyzer clean, all tests passed"
- If analyzer fails: show issues, skip test report
- If tests fail: show failing tests
Do NOT attempt to fix anything unless the user explicitly asks.
