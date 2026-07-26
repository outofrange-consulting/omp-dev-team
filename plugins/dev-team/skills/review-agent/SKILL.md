---
name: review-agent
description: >-
  Run a single named review agent against target files. Use this when the
  user names a specific agent (e.g. "run security-review", "check for test
  issues", "run js-fp-review on this file") rather than wanting the full
  suite. Prefer this over /code-review when only one concern is relevant or
  speed matters. Also used by the orchestrator for inline review checkpoints
  during Phase 3 implementation.
argument-hint: "<agent-name> [--since <ref>] [--path <dir>]"
user-invocable: true
allowed-tools: read, search, find, bash(git diff *)
---

# Review Agent

Role: worker. This skill performs the actual review using the agent
definition as its specification.

You have been invoked with the `/review-agent` skill. Run a single named review agent.

This command is executed under orchestrator direction. Dispatch the named agent
through the `task` tool as `agent: "<name>"` and pass **no model**: `task` has no
`model` parameter, and OMP resolves the agent's own `model:` frontmatter against
`modelRoles` (see the Resolution Procedure in `agents/orchestrator.md`). A single
targeted review is a review-leg call, so pass no `effort` either — it runs at the
agent's declared floor.

## Worker constraints

1. **Follow the agent definition exactly.** The agent file is your
   specification — detect what it says to detect, skip what it says
   to skip.
2. **Respect context needs.** When reviewing uncommitted changes or `--since`,
   honor the agent's `Context needs` field (diff-only, full-file, or
   project-structure).
3. **Do not add findings beyond the agent's scope.** If the agent
   says "Ignore: naming, tests" — do not flag naming or test issues.
4. **Return structured JSON only.** Output the standard result
   format. Do not add prose commentary.
5. **Be concise.** Issue messages should be one sentence. Suggested
   fixes should be actionable, not explanatory. No preambles or
   filler.

## Parse Arguments

Arguments: $ARGUMENTS

Required: agent name (`$0`, e.g., `test-review`, `js-fp-review`, `security-review`)

Optional:

- `--since <ref>`: Review files changed since a git ref
- `--path <dir>`: Target directory (default: current working directory)

## Steps

### 1. Load the agent definition

Preferred path: dispatch the agent by name through the `task` tool
(`agent: "<name>"`). OMP discovers agents itself and loads the definition as that
subagent's system prompt — you never have to locate the file, and its instruction
text stays out of your own context.

Only when you are running the review inline (no subagent) do you need the file
itself. Agents live in the dev-team plugin's `agents/` directory as
`<name>.md`; the authoritative roster — name, role, model floor, scope — is
`skill://dev-team-knowledge/agent-registry.md`.

If the name doesn't resolve, do **not** guess a near-miss. List the review agents
from the registry (or from `/agents`, which shows every agent OMP actually
discovered) and ask the user to pick one.

### 2. Determine target files

Same auto-scope logic as `/code-review`:

- If uncommitted changes exist: review those files
- If working tree is clean: review all source files
- `--since <ref>`: `git diff --name-only <ref>...HEAD`
- `--path <dir>`: review files in that directory

### 3. Run review

Follow the agent definition to review each target file. Produce a JSON result:

```json
{
  "agentName": "<name>",
  "status": "pass|warn|fail",
  "issues": [
    {
      "severity": "error|warning|suggestion",
      "file": "<path>",
      "line": 0,
      "message": "<description>",
      "suggestedFix": "<fix>"
    }
  ],
  "summary": "<summary>"
}
```

### 3b. Apply ACCEPTED-RISKS.md suppression

Before reporting, consult `ACCEPTED-RISKS.md` at the repo root if present. For each issue, check rules in declaration order per `skill://dev-team-knowledge/accepted-risks-schema.md`. The first matching rule suppresses the issue from the displayed result and emits an audit entry of the form `SUPPRESSED: <file>:<line> [<rule_id>] by ACCEPTED-RISKS rule <rule.id>`. Expired rules become inert (stop suppressing). Schema-invalid rules fail the run with a specific parse error. Absent file: skip silently.

### 4. Report

Display the result as a formatted summary with issues grouped by file. Include suggested fixes inline. If any issues were suppressed by ACCEPTED-RISKS, list them in a dedicated trailing section with rule ids for audit.
