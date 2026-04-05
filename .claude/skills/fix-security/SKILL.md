---
name: fix-security
description: Fetch GitHub security alerts (Dependabot, code scanning, secret scanning) and fix them. Use when user wants to resolve security issues.
---

## Fix GitHub security issues

### Step 1: Fetch all security alerts

Run these in parallel to get the full picture:

**Dependabot alerts:**
```bash
gh api repos/Llloooggg/LetsFLUTssh/dependabot/alerts --jq '.[] | select(.state=="open") | "\(.severity) \(.dependency.package.name) \(.dependency.package.ecosystem) — \(.security_advisory.summary)"'
```

**Code scanning alerts (CodeQL + Semgrep):**
```bash
gh api repos/Llloooggg/LetsFLUTssh/code-scanning/alerts --jq '.[] | select(.state=="open") | "\(.rule.severity) \(.tool.name) \(.most_recent_instance.location.path):\(.most_recent_instance.location.start_line) — \(.rule.description)"'
```

**Secret scanning alerts:**
```bash
gh api repos/Llloooggg/LetsFLUTssh/secret-scanning/alerts --jq '.[] | select(.state=="open") | "\(.secret_type) — \(.secret_type_display_name)"' 2>/dev/null || echo "No secret scanning alerts or insufficient permissions"
```

If `$ARGUMENTS` contains "dependabot", "codescan", or "secrets" — fetch only that category.

### Step 2: Triage and prioritize

Present a summary table:
| Source | Severity | Issue | Location |
|--------|----------|-------|----------|

Prioritize: critical/high first, then medium, then low.

### Step 3: Fix issues

**Dependabot (dependency vulnerabilities):**
1. Check what version fixes the vulnerability
2. Update the dependency in `pubspec.yaml` to the fixed version
3. Run `flutter pub get` to update `pubspec.lock`
4. Run `make check` to verify nothing breaks
5. Bump version (patch)

**Code scanning (CodeQL/Semgrep):**
1. Read the flagged code
2. Fix the vulnerability — NEVER suppress with `// ignore:` or inline comments
3. If it's a pattern used elsewhere, fix all instances
4. Update SECURITY.md if the security model changed

**Secret scanning:**
1. Immediately warn the user — leaked secrets need rotation, not just removal
2. Help remove the secret from code and add to `.gitignore` if it's a file
3. Suggest rotating the compromised credential

### Step 4: Verify

- `make check` must pass
- Re-fetch the specific alert to confirm the fix addresses it

### Rules
- One fix per commit, HARD STOP between fixes
- Dependabot fixes: always verify the new version is stable (no beta/pre-release)
- Never downgrade a dependency to fix a vulnerability — upgrade or find alternative
- If a vulnerability has no fix available, document it and tell the user
