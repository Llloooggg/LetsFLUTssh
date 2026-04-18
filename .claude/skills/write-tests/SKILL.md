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

**Follow AGENT_RULES.md "Testing Methodology"** — it covers the three hard-to-remember invariants:
- "Tests assert spec, not current output" — derive the oracle from intent, never from observing the code
- "When test and code disagree, surface it" — stop and report to user, don't silently patch either side
- "Uncovered lines are a marker, not a target" — articulate the contract a line encodes before writing an `expect` that reaches it

When in doubt re-read those sections in AGENT_RULES.md verbatim; they are not paraphrased here on purpose.

Skill-specific additions:
- **Find callers first** — before touching a test file, run `/find-impact <source_path>` to see what else the behavior surfaces in, so the new test covers the real contract, not just the single call site
- **One test file per source file** — add to existing test file, never create `_extra_test.dart`
- Test uncovered branches: if/else, switch cases, error handling, edge cases
- Use descriptive test names that encode the spec (e.g. `'should reject empty host with InvalidHostError'`, not `'test1'` or `'covers line 42'`)
- Follow existing test patterns in the file
- Mock external dependencies (SSH, file I/O, platform) — never make real connections; pure logic gets direct unit tests without mocks
- Group related tests in `group()` blocks matching the class/function being tested

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
