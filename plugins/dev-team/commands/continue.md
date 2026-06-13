# /continue — resume work from a prior session

Role: **orchestrator**.

Arguments: `$ARGUMENTS` (optional progress-file path).

## Run it

1. `read skill://continue` and follow it.
2. Load the latest phase progress file from `memory/` (and `memory/decisions.md`)
   and resume at the correct phase with only the agents/skills that phase needs.
