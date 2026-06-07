# /triage — investigate a bug and write a triage record

Role: **worker**.

Arguments: `$ARGUMENTS` (bug description / issue reference).

## Run it

1. `read skill://triage` and follow it (uses `skill://systematic-debugging`).
2. Write a triage record to `.triage/<slug>.md` with root-cause analysis and a
   TDD fix plan. Do not fix yet unless asked — triage produces the plan.
