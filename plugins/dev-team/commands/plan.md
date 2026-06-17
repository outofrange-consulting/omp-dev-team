# /plan — decompose into vertical slices with Gherkin scenarios

Role: **orchestrator**. Phase 2 of the pipeline.

Arguments: `$ARGUMENTS` (optional: path to the spec/design doc).

## Run it

1. `read skill://plan` and follow it exactly.
2. Decompose the feature into **vertical slices**; author each slice's **Gherkin
   scenarios** (the behavioral contract) and TDD steps before implementation.
   Each slice declares `Depends-on` + `Files`; derive the `## Parallelization`
   waves so independent slices can build concurrently.
3. Before the human gate, dispatch the **five plan-review personas in parallel**
   via the `task` tool (acceptance, design, UX, strategic, parallelization). If
   any returns `needs-revision`, address blockers first. Aggregate all findings.
4. Write the plan to `plans/` with `**Status**: draft`. The plan is the primary
   review artifact.

Stop at the human gate. Mark `**Status**: approved` only after human approval.
