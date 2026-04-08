---
name: fix-sonar
description: Fetch SonarCloud issues and fix them. Use when user wants to fix code smells, bugs, or vulnerabilities reported by SonarCloud.
---

## Fix SonarCloud issues

### Step 1: Fetch issues from SonarCloud API

Get open issues sorted by severity:
```bash
curl -s "https://sonarcloud.io/api/issues/search?componentKeys=Llloooggg_LetsFLUTssh&statuses=OPEN,CONFIRMED,REOPENED&ps=100&s=SEVERITY&asc=false" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for i in d.get('issues', []):
    comp = i.get('component','').replace('Llloooggg_LetsFLUTssh:','')
    print(f\"{i['severity']:12} {i['type']:15} {comp}:{i.get('line','')} — {i['message']}\")
print(f\"\\nTotal: {d.get('total',0)} issues\")
"
```

If `$ARGUMENTS` contains a severity (BLOCKER, CRITICAL, MAJOR, MINOR, INFO), filter by it:
```bash
curl -s "https://sonarcloud.io/api/issues/search?componentKeys=Llloooggg_LetsFLUTssh&statuses=OPEN,CONFIRMED,REOPENED&severities=$ARGUMENTS&ps=100"
```

If `$ARGUMENTS` contains a file path, filter by component:
```bash
curl -s "https://sonarcloud.io/api/issues/search?componentKeys=Llloooggg_LetsFLUTssh&statuses=OPEN,CONFIRMED,REOPENED&components=Llloooggg_LetsFLUTssh:$ARGUMENTS&ps=100"
```

### Step 2: Analyze and group issues

Group by file. For each file, read the relevant code sections to understand context.

### Step 3: Fix issues

For each issue:
1. Read the file and understand the problem
2. Fix the root cause — NEVER use `// ignore:`, `// NOSONAR`, or any suppression
3. Ensure the fix follows project conventions (CLAUDE.md)
4. If a fix changes public API or data flow, update docs (ARCHITECTURE.md)

### Step 4: Verify

Run `make analyze` to confirm no new issues were introduced.

### Rules
- Fix issues from highest severity to lowest: BLOCKER > CRITICAL > MAJOR > MINOR > INFO
- One logical fix per commit — don't bundle unrelated fixes
- Follow the HARD STOP rule: implement fix → tests → docs → `make analyze` → commit. Do NOT start the next fix until the current one is committed. Version bumps are automated by CI on merge to `main`
- Cognitive complexity (S3776) fixes: extract helper methods, don't just inline
- Nested ternary (S3358) fixes: extract to local variables or if/else
- Never suppress — always fix the root cause
