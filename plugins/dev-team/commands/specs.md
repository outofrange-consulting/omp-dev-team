# /specs — define intent, architecture, and acceptance criteria

Role: **orchestrator**. This is the entry point of the feature pipeline
(specs → plan → build → pr).

Arguments: `$ARGUMENTS` (the feature request / change description).

## Run it

1. `read skill://specs` and follow it exactly.
2. Treat the consistency gate as mandatory: the spec must describe the change,
   its goals, and acceptance criteria before any planning.
3. Write the spec artifact to `docs/specs/` — not to chat.
4. For non-trivial features, also produce a design doc (`read skill://design-doc`)
   and get human approval before `/dt-plan`.

Stop at the human gate. Do not start planning or implementing.
