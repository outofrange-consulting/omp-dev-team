# /code-review — full review suite with auto-fix loop

Role: **orchestrator**.

Arguments: `$ARGUMENTS` (optional: paths/globs; `--force` to review docs-only
changesets; default scope is uncommitted changes).

## Run it

1. `read skill://code-review` and follow it exactly.
2. Select review agents by what changed (see the Inline Review Checkpoint table
   in the orchestrator agent), and dispatch them **in parallel** via `task`.
   Cheap-tier agents (`pi/smol` = nano lexical, `pi/task` = code) run on the
   cheapest capable model; balanced/deep agents run on Sonnet/Opus.
3. If `REVIEW-CONTEXT.md` exists in the project root, pass its contents to each
   agent as additional context.
4. Classify findings: **actionable** = error/warning severity with high/medium
   confidence → auto-fix file-by-file, run tests, re-review (up to 5 iterations).
   **Human-required** = confidence none → log and escalate.
5. On a clean pass, run `/review-approve` to clear the commit gate.

Output: a structured review report written to file, and a pass/warn/fail verdict.
