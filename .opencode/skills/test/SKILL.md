---
name: test
description: Run all tests with coverage via make test. Use when user wants to run the test suite.
---

Run the test suite:

```!
make test 2>&1
```

Report the results concisely:
- If all tests pass: say "Tests: all passed (N tests)" and nothing else
- If failures: list each failing test with file and test name. Show the failure reason. Do NOT attempt to fix anything unless the user explicitly asks

If the user passed arguments like a specific test file, run that instead:
`flutter test $ARGUMENTS`
