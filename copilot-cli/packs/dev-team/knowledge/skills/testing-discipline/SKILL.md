---
name: testing-discipline
description: Tests are required for behavior changes — write good tests and verify them, in whatever order fits. Use whenever writing or modifying implementation code, or when reviewing whether changes are adequately tested. NOT test-first — test-first ordering is not enforced (see the tests-required rule); the leverage is in the plan gate, not the test sequence.
role: worker
user-invocable: true
---

# Testing discipline (tests required, test-first optional)

## Overview

Every behavior change ships with tests. **The order doesn't matter** — write the
test before, after, or alongside the code, whichever fits. What matters is that
the unit is **not done** until its tests exist and pass. For AI agents,
RED→GREEN→REFACTOR *ordering* adds little over "tests required + a strong plan
gate"; the `plan-gate` extension carries the process leverage instead.

## Iron law

**No behavior change is "done" until its tests pass.** Verify by running them —
`/impl-verify` runs the stack's strict build + tests and returns a bounded
verdict. Paste that verdict as evidence (`source-of-truth` rung 3); never claim
"tests should pass" from memory.

## Constraints

- Don't move to the next unit until the current unit's tests pass.
- **Don't edit a failing test to make it pass — fix the code.** Editing an
  existing `.feature` spec is blocked by `spec-guard`; change a wrong spec
  deliberately via `/specs`.
- **Don't delete, skip, or weaken tests to go green** (`no-disable-analyzers`).
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
- [ ] `/impl-verify` reports the strict build + tests green; verdict pasted
- [ ] No gate was silenced to get there (`no-disable-analyzers`)

## Integration with the pipeline

- **Plan (`/plan`)**: each step names the tests it will add — test strategy is
  part of the plan, authored before the build is unlocked (`/plan-approve`).
- **Build (`/build`)**: implement and test in any order; gate each unit on
  `/impl-verify`.
- **Acceptance tests**: Gherkin `.feature` scenarios define the outer loop;
  unit/integration tests cover the inside.

## Output

The `/impl-verify` PASS verdict (strict build + tests green) plus the tests
added, as the evidence a unit is done.
