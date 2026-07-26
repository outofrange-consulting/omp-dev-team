---
name: testing-discipline
description: Tests are required for behavior changes, written in the Code-First Small Batches cadence — IMPLEMENT then TEST then REFACTOR, one behavior at a time, refactor on every green. Use whenever writing or modifying implementation code, or when reviewing whether changes are adequately tested. NOT test-first: RED-first is not enforced (see the tests-required rule); the leverage is in the plan gate, not the test sequence.
role: worker
user-invocable: true
---

# Testing discipline (Code-First Small Batches)

## Overview

Every behavior change ships with tests, written in **small per-behavior
batches**. The cadence is **Code-First Small Batches**:

```
IMPLEMENT one behavior -> TEST it -> REFACTOR on green
```

One agent does all three for a unit of work. There is no cadence to choose and
no per-plan opt-in — this is the only cycle a step follows.

- **Refactor on every green.** Never deferred to an end-of-build sweep, never
  skipped, never made conditional on task size or complexity. Dropping RED-first
  is not dropping REFACTOR.
- **Tests are frozen during REFACTOR.** Behaviour-preserving means the tests do
  not move. If a cleanup needs a test to change, it is not a refactor — split it
  into its own batch.
- **No big-batch shapes.** Never all the code then all the tests; never all the
  tests then all the code.

Why not enforce RED-first: it is a **cost** result, not a quality gap. Classic
TDD scored 0.966 quality at $1.59/cell against Code-First's 0.961 at $0.99 —
0.608 quality-per-dollar vs 0.968 (upstream ADR-0017; full citation in
`docs/plan-gate-over-tdd.md`). The `plan-gate` extension carries the process
leverage the ordering was standing in for.

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
- **Vertical slices over horizontal.** Bulk tests describe *imagined* behavior
  and go insensitive to real changes — this is the same prohibition as "no
  big-batch shapes" above, seen from the test side. One test ↔ one behavior,
  built up incrementally. A first end-to-end "tracer bullet" slice proves the
  path before you invest in breadth.

## Verification checklist

Before completing a unit of work:

- [ ] Each behavior change has a test covering it (incl. edge/error cases)
- [ ] Tests use real code where feasible (mocks only when unavoidable)
- [ ] `/impl-verify` reports the strict build + tests green; verdict pasted
- [ ] The refactor pass was taken on this green, with the tests unchanged
- [ ] No gate was silenced to get there (`no-disable-analyzers`)

## Integration with the pipeline

- **Plan (`/plan`)**: each step names the tests it will add — test strategy is
  part of the plan, authored before the build is unlocked (`/plan-approve`).
- **Build (`/build`)**: run the IMPLEMENT → TEST → REFACTOR batch per behavior
  and gate each unit on `/impl-verify`. The per-step contract lives in
  `skill://build`.
- **Acceptance tests**: Gherkin `.feature` scenarios define the outer loop;
  unit/integration tests cover the inside.

## Output

The `/impl-verify` PASS verdict (strict build + tests green) plus the tests
added, as the evidence a unit is done.
