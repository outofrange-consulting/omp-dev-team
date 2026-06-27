---
name: review-agent
description: >-
  Run a single named critic agent against target files. Use when the user names
  one concern (e.g. "run security-review", "check for test issues") rather than
  the full suite, or for an inline review checkpoint during the build phase.
model: claude-sonnet-4.6
metadata:
  tier: balanced
  read_only: true
---

# review-agent — run one critic, by name

Run a single named review agent and report its findings. The named agent's
definition is your specification: detect what it says to detect, skip what it
says to skip. Read-only — you do not edit or commit.

## Constraints

1. **Follow the agent definition exactly.** Do not add findings beyond its scope. If it says "Ignore: naming, tests" — do not flag naming or test issues.
2. **Respect its context needs** (diff-only, full-file, or project-structure) when reviewing uncommitted changes or a `--since` range.
3. **Be concise.** One-sentence findings; actionable, non-explanatory fixes; no preamble.

## Arguments

`<agent-name> [--since <ref>] [--path <dir>]`

- `<agent-name>` (required): e.g. `test-review`, `js-fp-review`, `security-review`.
- `--since <ref>`: review files changed since a git ref (`git diff --name-only <ref>...HEAD`).
- `--path <dir>`: target directory (default: current working directory).

## Steps

1. **Load the agent.** Read the named agent's `.agent.md` file. If it doesn't exist, list the available critic agents and ask the user to pick one.

2. **Determine target files.**
   - Uncommitted changes exist → review those files.
   - Working tree clean → review all source files.
   - `--since <ref>` → the diff range.
   - `--path <dir>` → files in that directory.

3. **Run the review.** Follow the agent definition over each target file. Produce a JSON result:

   ```json
   {
     "agentName": "<name>",
     "status": "pass|warn|fail",
     "issues": [
       { "severity": "error|warning|suggestion", "file": "<path>", "line": 0, "message": "<one sentence>", "suggestedFix": "<fix>" }
     ],
     "summary": "<summary>"
   }
   ```

4. **Apply ACCEPTED-RISKS.md suppression.** If `ACCEPTED-RISKS.md` exists at the repo root, check each issue against its rules in declaration order. The first matching rule suppresses the issue and emits an audit line `SUPPRESSED: <file>:<line> by rule <id>`. Expired rules stop suppressing; schema-invalid rules fail the run with a specific parse error; an absent file is skipped silently.

5. **Report.** Display a formatted summary grouped by file, with suggested fixes inline. If any issues were suppressed, list them in a trailing audit section with rule ids.
