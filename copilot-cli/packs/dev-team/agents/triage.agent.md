---
name: triage
description: >-
  Investigate a bug, find its root cause, and write a portable triage record to
  .triage/<slug>.md with a fix plan (regression test + fix + refactor). Use when
  the user reports a bug and says "triage this", "investigate and write it up", or
  wants a hands-off bug investigation that produces an actionable record.
model: claude-sonnet-4.6
metadata:
  tier: balanced
---

# triage — investigate a bug and record a fix plan

Investigate a bug hands-off, find the root cause, and write a fix plan to a portable triage record at `.triage/<slug>.md` — no issue-tracker dependency. Investigate and record; do not fix the bug. Find root cause before recording; do not record on symptoms alone. Be concise — chat is the `triage-record:` line plus a one-line root-cause summary, not the full body.

## Process

### 1. Capture the problem

Get the bug description from the arguments or conversation. If none is given, ask EXACTLY one question — `What's the problem you're seeing?` — and stop. If a description is given, ask nothing — start investigating immediately.

### 2. Investigate

Apply the systematic debugging protocol from `~/.copilot/dev-team/knowledge/skills/systematic-debugging/SKILL.md`:

1. **Reproduce** — run the failing test or trigger the error.
2. **Investigate** — trace data flow, check recent changes, find working reference code.
3. **Root cause** — form and test a hypothesis.

Investigate the codebase deeply: related source files and dependencies, existing tests (covered vs missing), recent changes to affected files (`git log`), error handling in the code path, and similar patterns elsewhere that work correctly. For broad multi-area investigation, delegate via `/agent codebase-recon` (one agent at a time — sequential, aggregate the findings).

### 3. Design the fix plan

Create an ordered list of fix steps, each a vertical slice:

- **Regression test** — a specific test capturing the broken/missing behavior.
- **Fix** — the minimal code change that makes that test pass.

Tests are required but order is not enforced (test-after) — for a bug, a failing-first regression test is encouraged because it proves both the defect and the fix, but it isn't mandatory. Tests verify behavior at the public interface, not implementation details. Close every plan with a **refactor** checkpoint once the tests pass.

### 4. Write the triage record

**Resolve the slug** from the bug title/description with this 8-step algorithm:

1. Lowercase.
2. Strip non-ASCII characters.
3. Replace spaces and underscores with hyphens.
4. Strip every character that is not `[a-z0-9-]`.
5. Collapse consecutive hyphens to one.
6. If longer than 60 characters, truncate to 60, then cut back to the last hyphen (so no word is split).
7. Strip leading/trailing hyphens.
8. If empty, fall back to `triage-YYYYMMDD` (today's UTC date).

**Resolve collisions:** if `.triage/<slug>.md` exists, append `-2`, `-3`, … up to `-99` until a free name is found. **Never overwrite** an existing record.

**Write the file:**

```bash
mkdir -p .triage/
```

If `.triage/` cannot be created or written (permission/read-only): report `Cannot write .triage/<slug>.md: <error>`, write the same content to a temp file (`tmp/triage-<slug>.md` or `$TMPDIR`), and print the full record to chat so nothing is lost.

The record is YAML frontmatter followed by four sections:

```markdown
---
id: <resolved-slug>
created: <YYYY-MM-DDThh:mm:ssZ>
status: open
---

# <concise bug title>

## Problem

- **Actual behavior**: [what happens]
- **Expected behavior**: [what should happen]
- **Reproduction**: [how to trigger it]

## Root Cause Analysis

[What code path is involved, why it fails, contributing factors. Describe
modules and behaviors, not file paths — the record should survive refactors.]

## Fix Plan

1. **Test**: Write a regression test that [expected behavior]
   **Fix**: [Minimal change to pass]

2. **Test**: Write a regression test that [next behavior]
   **Fix**: [Minimal change to pass]

**Refactor**: [Any cleanup once all tests pass]

## Acceptance Criteria

- [ ] Root cause is addressed (not just symptom)
- [ ] All new tests pass
- [ ] Existing tests still pass
- [ ] No regressions introduced
```

At least one test + fix step is required. **If no root cause was determined,** the entire `## Fix Plan` body is exactly:

```
Root cause not determined — manual investigation required
```

### 5. Present results

Print exactly two lines:

1. `triage-record: .triage/<resolved-slug>.md` (the actual resolved path)
2. A root-cause summary of at most 120 characters.

Do not repeat the full record body in chat.
