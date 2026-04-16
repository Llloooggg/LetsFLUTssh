---
name: write-tests
description: Check SonarCloud coverage and write missing tests for uncovered lines. Use when user wants to improve test coverage.
---

## Write tests for uncovered code

### Step 1: Get current coverage from SonarCloud

**Per-file coverage (worst files first):**
```bash
curl -s "https://sonarcloud.io/api/measures/component_tree?component=Llloooggg_LetsFLUTssh&metricKeys=uncovered_lines,lines_to_cover,coverage&strategy=leaves&ps=50&s=metric&metricSort=uncovered_lines&asc=false" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(f\"{'File':<60} {'Coverage':>8} {'Uncovered':>9} {'Total':>5}\")
print('-' * 85)
for c in d.get('components', []):
    m = {x['metric']: x.get('value','?') for x in c.get('measures',[])}
    name = c['path']
    print(f\"{name:<60} {m.get('coverage','?'):>7}% {m.get('uncovered_lines','?'):>9} {m.get('lines_to_cover','?'):>5}\")
"
```

**New code coverage:**
```bash
curl -s "https://sonarcloud.io/api/measures/component?component=Llloooggg_LetsFLUTssh&metricKeys=new_coverage,new_uncovered_lines,new_lines_to_cover"
```

If `$ARGUMENTS` contains a file path, focus on that file only.

### Step 2: Get uncovered line ranges

For each target file, fetch exact uncovered lines:
```bash
curl -s "https://sonarcloud.io/api/sources/show?component=Llloooggg_LetsFLUTssh:FILEPATH&from=1&to=9999" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for line in d.get('sources', []):
    if line.get('lineHits', None) == 0:
        print(f\"  L{line['line']}: {line['code'][:100]}\")
"
```

### Step 3: Read source and existing tests

For each file to cover:
1. Read the source file to understand the code
2. Find existing test file: `test/` mirror of `lib/` path (e.g., `lib/core/ssh.dart` → `test/core/ssh_test.dart`)
3. Read the existing test file to understand what's already tested

### Step 4: Write tests

**Assert spec, not current output.** Before writing any `expect(...)`, state in one sentence what the function *should* do for the given input — derived from the feature's intent (commit history, naming, surrounding docstrings, user-facing strings), not from running the code and copying the result. **Never** run the function, observe the output, and paste it into `expect(...)` as the oracle: that's a pinning test, it cements bugs, and it's the reason "coverage went up, bugs are still a truckload". This applies doubly to parsers, formatters, `localizeError`, URL/URI handling, and anything that touches untrusted input. If the correct behavior is genuinely unclear, stop and ask the user rather than inventing an oracle.

**When test and code disagree, surface it — don't silently "fix" either side.** If your derived spec says X and the code returns Y, you have three possibilities: (1) real bug in code, (2) wrong spec on your side (you misread the intent), (3) genuinely ambiguous requirement. From inside the test file you cannot tell which. Stop writing the test. Report the disagreement to the user with:
- the exact input
- the expected value per your spec, **and** where you derived the spec from (commit message, docstring, user-visible string, linked issue)
- the current output the code actually produces

Let the user decide which side is wrong. Only after confirmation: fix the code **or** update the spec. A confident "I found a bug, patching it" on an edge case is exactly how correct behavior gets quietly regressed and tests start cementing a *new* wrong answer.

**Uncovered lines are a marker, not a target.** SonarCloud's "line 42 not covered" means "no test verifies the behavior this line implements" — it is NOT a target that says "write anything that reaches this line". A test whose only purpose is to execute the line (`function(args); expect(result, isNotNull);` / `expect(() => fn(), returnsNormally)` / `expect(result, isA<T>())` on any non-trivial function) raises coverage and catches nothing. Before writing it, answer: **what branch, decision, or contract does this line encode?** Then write a test that would fail if that contract broke. If you can't articulate the contract for a line, either the logic is too implicit to test (refactor first — extract a pure function) or you don't understand it yet (ask the user). A file at 100% coverage with smoke-style assertions is worse than 80% with meaningful ones: it gives false confidence *and* it will fight you when you try to change the code. Skip lines you can't spec, don't paper over them.

Rules:
- **One test file per source file** — add to existing test file, never create `_extra_test.dart`
- Test uncovered branches: if/else, switch cases, error handling, edge cases
- Use descriptive test names that encode the spec: `'should reject empty host with InvalidHostError'`, not `'test1'` or `'covers line 42'`
- Follow existing test patterns in the file
- Mock external dependencies (SSH, file I/O, platform) — never make real connections
- Pure logic should have direct unit tests without mocks
- Group related tests in `group()` blocks matching the class/function being tested
- If you can't state the expected behavior in one sentence without looking at the implementation, you don't have a spec yet — stop and derive one first

### Step 5: Verify coverage improved

Run tests and check coverage:
```bash
make test
```

Then compare with SonarCloud numbers. Note: local `lcov.info` may lag behind SonarCloud — for authoritative numbers, push and wait for CI, or use the API after CI completes.

### Prioritization
- If no arguments: start with files that have the most uncovered lines (biggest impact)
- If argument is "new": focus only on new code coverage (new_uncovered_lines)
- If argument is a file path: focus on that file only
- Skip untestable lines: real SSH connections, native file I/O, platform-specific code that requires a real device
- Target: 100% where possible, 80% is SonarCloud minimum but never the goal
