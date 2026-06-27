---
name: plan
description: >-
  Produce a concrete, reviewable implementation plan before any source is edited.
  Use after scoping a non-trivial task. Output is the primary review artifact:
  every file change, the test strategy, acceptance criteria, and risks.
model: claude-sonnet-4.6
metadata:
  tier: balanced
  escalate-when-complex: claude-opus-4.8
---

# plan — the implementation plan is the review artifact

A 200-line plan is far more reviewable than 2000 lines of code. Get the design
right here, on paper, where mistakes are cheap. **You cannot edit production
source yet** — the plan-gate stays closed until the human runs `dt plan-approve`.

## Produce a plan with

1. **Goal & scope** — what changes, and explicitly what does *not*.
2. **Approach** — the design, and at least one alternative considered with the
   reason it was rejected (design-it-twice). Name the affected module boundaries.
3. **File-by-file changes** — for each file: what changes and why, with the key
   functions/types. New files: their responsibility.
4. **Test strategy** — which behaviors get tests, at which level (unit /
   integration / e2e), and how each acceptance criterion from the specs is
   covered. Tests are required for behavior changes.
5. **Verification** — the exact commands that must pass (build, lint, test).
6. **Risks & rollout** — what could break, migration/ordering concerns, and how
   it's reversible.

## Self-review before the human gate

Challenge your own plan from these lenses and fold the findings in:
- **Acceptance**: is every criterion verifiable? Are error paths covered?
- **Design**: coupling, abstraction quality, structural risk, pattern fit.
- **Strategic**: problem-solution fit, scope creep, opportunity cost.
- **UX** (if user-facing): journey, error experience, accessibility.

For a **complex** task, reason at opus depth (or recommend the user `/model
claude-opus-4.8` for this step).

## Handoff

Present the plan and the self-review findings. Ask the human to sign off. Tell
them: on approval, run `dt plan-approve` (optionally `dt plan-approve docs/plan.md`),
then switch to `/agent build`. Do not approve on their behalf.
