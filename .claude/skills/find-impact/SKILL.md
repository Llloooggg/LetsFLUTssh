---
name: find-impact
description: Map the blast radius of changing a Dart file — find importers (call sites) and the paired test file. Use when user says "what uses X", "who imports X", "impact of X", "find callers of X", or invokes /find-impact with a path.
---

## find-impact — impact analysis for a Dart source file

Given a path like `lib/core/ssh/known_hosts.dart`, report:

1. **Paired test file** — mirror path under `test/`. In this repo the rule is one test per source file (see CLAUDE.md).
2. **Direct importers** — files that `import` the target. Uses both package-relative and relative-path forms.
3. **Symbol references** — top-level class/function names defined in the target, grepped across `lib/` and `test/`.

### Arguments

- `$1` — absolute or repo-relative path to the Dart source file under `lib/`.

### Steps

1. **Normalize path.** Accept `lib/core/ssh/known_hosts.dart` or `/home/.../lib/core/ssh/known_hosts.dart`. Strip the repo prefix; work with the `lib/...` form.

2. **Find paired test.**
   - Mirror path: `lib/X/Y/foo.dart` → `test/X/Y/foo_test.dart`.
   - Run a `Glob` with pattern `test/**/foo_test.dart` as a fallback in case the test lives under a slightly different path.
   - Report whether the test exists; if not, flag it — per CLAUDE.md "all code must have tests".

3. **Find direct importers.**
   - Two import forms are used in this repo:
     - `package:lets_flut_ssh/...` (rare, only top-level entry points)
     - relative paths like `'../../core/ssh/known_hosts.dart'`
   - Grep for both:
     - `import '.*${basename}';` — matches any relative import of the file.
     - `import 'package:.*${path_under_lib}';` — matches package-form imports.
   - Restrict to `*.dart` only. List matching files (path + line of the `import` statement).

4. **Find top-level symbol references.**
   - Read the target file, extract top-level declarations: lines starting with `class `, `mixin `, `extension `, `enum `, `typedef `, or `[A-Z]\w+\s*\(` for top-level functions.
   - For each exported symbol (non-underscore-prefixed), grep across `lib/` and `test/` for bare identifier usage (excluding the target file itself).
   - Group results by file; cap at first 5 call sites per file with `head_limit`.

5. **Report format.** Emit a single compact report:

   ```
   Target: lib/core/ssh/known_hosts.dart
   Paired test: test/core/ssh/known_hosts_test.dart (exists | MISSING)

   Direct importers (N):
     - lib/core/connection/connection.dart:3
     - lib/features/known_hosts/known_hosts_controller.dart:5
     ...

   Symbols referenced externally:
     KnownHostsManager (12 sites)
       - lib/core/connection/connection.dart:24, 53, 57
       - lib/features/known_hosts/known_hosts_controller.dart:18
       ...
   ```

### Constraints

- **Do NOT run tests.** This skill is read-only discovery — it never invokes `flutter test`, `dart test`, or `make test`.
- **Do NOT edit any file.** Reporting only.
- Prefer `Grep` + `Glob` over `Bash` for speed and permission ergonomics.
- Cap total output to roughly one screen — if importers exceed 40, show the first 40 and the total count.
- Generated files (`*.g.dart`, `*.freezed.dart`) are excluded from analysis — skip them when listing results.
