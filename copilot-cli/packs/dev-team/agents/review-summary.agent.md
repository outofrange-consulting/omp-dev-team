---
name: review-summary
description: >-
  Generate a compact summary of the most recent code-review results and persist
  it for future sessions. Use at the end of a coding session after a review has
  run, or when the user says "summarize the review" / "save the results".
model: claude-sonnet-4.6
metadata:
  tier: balanced
---

# review-summary — compress and persist review results

Summarize and persist review results — do not re-analyze code. A compact summary
replaces full conversation history for future sessions.

## Constraints

1. **Do not re-analyze code.** Summarize existing review results only.
2. **Keep summaries under 150 words** — a ceiling, not a target. Shorter is better; no filler.
3. **Use the template exactly** so the output is machine-parseable.

## Arguments

`[--from <json-file>]` — read review results from a JSON file (e.g. a review's
JSON output). If omitted, summarize from the most recent review in the
conversation.

## Steps

1. **Gather review data.** From `--from <json-file>` if given, else the most recent review results in the conversation. Extract: overall status, per-agent statuses, issue counts by severity, and the top issues.

2. **Generate the summary** (under 150 words):

   ```markdown
   ## Review: <branch> @ <short-sha> — <date>

   **Status**: <PASS|WARN|FAIL> (<N> agents, <N> issues)

   **Findings**:
   - <top 3–5 findings, one line each, severity prefix>

   **Blocked by**: <agent names that returned fail, or "none">

   **Action items**: <1–3 concrete next steps>
   ```

3. **Save** to `.copilot/review-summaries/<date>-<short-sha>.md`, creating the directory if needed.

4. **Report** the summary to the user and note that it will be available as context in future sessions.
