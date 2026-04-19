---
name: doc
description: Look up a section of docs/ARCHITECTURE.md without reading the whole file. Given a task description OR a § identifier (numeric like "3.6", "§11" or header fragment like "Security", "Tags", "Transfer Queue"), returns the relevant ARCHITECTURE.md section(s) verbatim. Executes Grep + Read itself in a single invocation — does not ask the user to run anything. Trigger phrases: "/doc <anything>", "docs on X", "architecture of X", "find the ARCHITECTURE § about X". Use when you need to consult docs/ARCHITECTURE.md for a specific topic instead of reading the full 3000-line file.
---

## `/doc` — autonomous doc lookup

When invoked, **execute every step below yourself using `Grep` and `Read`**. Do **not** ask the user to run anything. Do **not** instruct the user to re-invoke this skill — if a second lookup is needed, chain it internally in the same turn.

### Input

A single string `$ARGS`. Two shapes are accepted:

- **Free-form task text** — "describe tags", "fix SFTP permission prompt", "why does transfer cancel on timeout", or the user's literal request after `/doc`.
- **§ identifier** — numeric (`3`, `3.6`, `3.6.1`, `§3.6`, `§11`) or a header fragment (`Security`, `Tags`, `Transfer Queue`, `SFTP`, `Session CRUD Flow`, `Persistence`).

### Execution — a single invocation, done autonomously

1. **Classify the input.** `$ARGS` is a § identifier when it matches `^§?\d+(\.\d+){0,2}$` or is a short phrase that already looks like an ARCHITECTURE.md heading. Everything else is a task description.

2. **If `$ARGS` is a task description** → do steps 3–6. **If `$ARGS` is a § identifier** → skip to step 5 with that identifier.

3. **Load the TOC.** `Read(file_path: "docs/ARCHITECTURE.md", offset: 3, limit: 50)` — this covers the `## Table of Contents` block. (If the TOC has moved, `Grep(pattern: "^## Table of Contents", path: "docs/ARCHITECTURE.md", output_mode: "content", -n: true)` to find it, then Read from that offset with limit 55.)

4. **Pick the §s that map to the task.** Reason about `$ARGS` against the TOC entries and pick **1–3** §s that are load-bearing for the task. Be generous — "add a DAO for pinned snippets" should pull `§10 Data Models`, `§11 Persistence`, and the `§3.x` §s for snippets and tags. Print a one-line summary: `Task: <$ARGS>. Matched §s: <list>.` Then, **in the same turn, without asking the user**, proceed to step 5 for each matched §.

5. **Locate the heading for each § identifier.** Use `Grep(path: "docs/ARCHITECTURE.md", output_mode: "content", -n: true)`:
   - Numeric `X` → pattern `^## ${X}\. `.
   - Numeric `X.Y` → pattern `^### ${X}\.${Y} `.
   - Numeric `X.Y.Z` → pattern `^#### ${X}\.${Y}\.${Z} `.
   - Text fragment → pattern `^##+ .*${text}` with `-i: true`.
   
   Record the matched line number and the heading depth (count of `#`).

6. **Find the end of the §.** Grep for the **next** heading of equal or shallower depth after the matched line:
   - Start depth `##` → next `^## ` after start.
   - Start depth `###` → next `^## ` or `^### ` after start.
   - Start depth `####` → next `^## `, `^### `, or `^#### ` after start.
   
   End line = `(next_heading_line - 1)`. If none found, end = end of file (use `Bash("wc -l docs/ARCHITECTURE.md")` if you need the exact count).

7. **Read the § body.** `Read(file_path: "docs/ARCHITECTURE.md", offset: <start>, limit: <end - start + 1>)`. Sub-§s come along because they live inside the parent range.

8. **Emit the result.** Concatenate, in this order, for each § fetched:
   - An anchor header: `### docs/ARCHITECTURE.md:<start>-<end> — <matched heading text>`.
   - The body **verbatim** (preserve code fences, mermaid blocks, tables, existing cross-links).

9. **Surface cross-links as hints.** Scan each emitted body for `[§X …](…)`, `[…](#…)`, `[ARCHITECTURE §X …](…)`. If any cross-linked § was **not** fetched in steps 5–8, list them as bullets at the end:
   > **Cross-link candidates:**
   > - `§13 Security Model` — referenced from the body above.
   > - `§9.1 SSH Connection Flow` — referenced from the body above.
   
   Then, if the current task plausibly depends on any of those, **fetch them too by looping back to step 5 with that § id — in the same invocation, without asking the user**. Stop when no new load-bearing cross-links appear.

10. **No match?** If step 5 finds no heading matching the identifier:
    - Run `Grep(pattern: "^##+ ", path: "docs/ARCHITECTURE.md", output_mode: "content", -n: true)` to list all headings.
    - Report `no match for "<arg>"`, followed by the nearest candidates (headings sharing a word with the query).
    - Do **not** fall back to reading the whole file. If the topic is genuinely missing from the docs, surface that fact — it is a gap that `docs/AGENT_RULES.md § Docs First` step 2 / step 7 is designed for (read code, then write the § in the same commit).

### Hard constraints

- **Never `Read` `docs/ARCHITECTURE.md` without `offset` + `limit`.** A full-file read means this skill failed; retry step 5.
- **Never emit "please run Grep / Read for me" instructions to the user.** The agent invoking this skill has `Grep` and `Read` in its tool set; use them.
- **Never summarise or paraphrase the § body.** Verbatim only. Summaries lose cross-links and drift.
- **Two-stage is internal, not user-facing.** If `$ARGS` is task text, pick §s yourself from the TOC and fetch in the same turn. Do not make the user type a second `/doc <§>`.

### Worked examples

- **User: "сделай мне описание к тегам"**
  → `$ARGS = "описание к тегам"`. Classify as task. Read TOC. Pick `§10 Data Models` (tag model lives there) and `§11 Persistence` (tags DAO). Grep + Read both §s. Emit both bodies verbatim with cross-link hints. One invocation.

- **User: "/doc 3.6"**
  → `$ARGS = "3.6"`. Classify as § identifier. Grep `^### 3.6 `. Find next `^### ` or `^## `. Read slice. Emit body + cross-links. One invocation.

- **User: "/doc Security"**
  → `$ARGS = "Security"`. Classify as § identifier (single word, looks like a header). Grep `^##+ .*Security` case-insensitive. Multiple matches possible (`### 3.6 Security & Encryption`, `## 13. Security Model`, `### 16.3 Security Decisions`) — emit all three bodies, labelled by anchor.

- **User: "why is transfer concurrency 2?"**
  → `$ARGS = "why is transfer concurrency 2?"`. Classify as task. Read TOC. Pick `§3.3 Transfer Queue`. Grep + Read. Emit. If §3.3 cross-links to §9.4, add it to cross-link candidates and fetch inline because the task explicitly asks about the *concurrency rationale*, which is likely in the flow description too.
