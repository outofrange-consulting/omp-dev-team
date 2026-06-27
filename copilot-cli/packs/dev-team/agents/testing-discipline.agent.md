---
name: testing-discipline
description: >-
  Tests are required for every behavior change — write good tests and verify
  them pass before a unit is "done". Use whenever writing or modifying
  implementation code, or when judging whether changes are adequately tested.
  Order is not enforced (not test-first); the leverage is the plan gate.
model: claude-sonnet-4.6
metadata:
  tier: balanced
---

# testing-discipline — tests required, test-first optional

Every behavior change ships with tests. **The order doesn't matter** — write the
test before, after, or alongside the code. What matters is that the unit is
**not done** until its tests exist and pass. RED→GREEN→REFACTOR *ordering* adds
little for an agent; the leverage lives in a strong plan gate, not the sequence.

## Iron law

**No behavior change is "done" until its tests pass.** Verify by running them —
run the stack's strict build + tests and paste the verdict as evidence; never
claim "tests should pass" from memory.

## Constraints

- Don't move to the next unit until the current unit's tests pass.
- **Don't edit a failing test to make it pass — fix the code.** Change a wrong
  spec deliberately, not to go green.
- **Don't delete, skip, or weaken tests to go green**, and don't silence any
  analyzer/gate.
- Prefer real code over mocks — mocks test your assumptions, not your code.

## What to test (and how well)

- Every new function/method that carries behavior; edge cases and error paths,
  not just the happy path.
- Test **user-facing behavior**, not the shape of data structures or signatures.
- **Vertical slices over horizontal.** Don't write all tests then all code in
  bulk — bulk tests describe *imagined* behavior and go insensitive to real
  changes. Prefer one test ↔ one behavior, building up incrementally. A first
  end-to-end "tracer bullet" slice proves the path before you invest in breadth.

## Verification checklist

Before completing a unit of work:

- [ ] Each behavior change has a test covering it (incl. edge/error cases)
- [ ] Tests use real code where feasible (mocks only when unavoidable)
- [ ] Strict build + tests reported green; verdict pasted
- [ ] No gate was silenced to get there

## Integration with the pipeline

- **Plan**: each step names the tests it will add — test strategy is part of the
  plan, authored before the build is unlocked.
- **Build**: implement and test in any order; gate each unit on the strict build
  + tests passing.
- **Acceptance tests**: Gherkin `.feature` scenarios define the outer loop;
  unit/integration tests cover the inside.

## Output

The PASS verdict (strict build + tests green) plus the tests added, as the
evidence a unit is done.
