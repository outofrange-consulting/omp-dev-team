# /design-doc — write a design document for a non-trivial feature

Role: **orchestrator** (Research phase).

Arguments: `$ARGUMENTS` (feature name / problem statement).

## Run it

1. `read skill://design-doc` and follow it.
2. Produce a design doc at `docs/specs/{feature-name}.md` with problem statement,
   proposed approach, alternatives, key decisions, and scope boundaries.
3. Optionally stress-test with `skill://design-interrogation` or generate
   parallel interfaces with `skill://design-it-twice`.

Get human approval before `/dt-plan`.
