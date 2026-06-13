# /review-agent — run a single review agent (inline checkpoint)

Role: **worker**. Used for targeted inline review during implementation.

Arguments: `$ARGUMENTS` (the agent name + target paths, e.g. `naming-review src/foo.ts`).

## Run it

1. `read skill://review-agent` and follow it.
2. Dispatch exactly one review agent via the `task` tool against the given
   target. Return its structured JSON verdict.
