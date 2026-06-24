# Test Value Patterns

How to source scalar values for fixtures and doubles so every value **reveals its
intent**. Adapted from *xUnit Test Patterns* (Meszaros). Guards against the
Obscure Test, Fragile Test, and Erratic Test smells. Used by test-design and
test reviewers.

## The four value sources

| Source | What | Use when | Risk |
|---|---|---|---|
| **Literal Value** | A constant written directly in the test | The exact value is significant — a boundary, pathological case, or spec example | Hard-coded-values smell; fragile coupling if reused across tests |
| **Derived Value** | Computed in-test from another value via a **visible** expression | A value relates to another by a documented rule | The same math error can hide in both test and SUT — cross-check by hand |
| **Generated Value** | Produced at runtime (sequence, UUID, faker) | The value must be **unique**, or it doesn't affect the outcome | Non-determinism / Erratic Test if the value actually matters |
| **Dummy Object** | A do-nothing placeholder satisfying a signature | An argument is required but **unused** on the path under test | If the SUT touches it, you need a Stub/Fake instead |

## Choosing a source

1. Does the behavior **depend** on the exact value? → **Literal** (and make it
   prominent / named).
2. Is it **derived** from another value by a rule? → **Derived** (show the
   expression; cross-check against a hand-computed literal).
3. Must it be **unique** or is it irrelevant? → **Generated** — but **prefer a
   distinct incrementing sequence over randomness** (reproducible).
4. Is the parameter **required but unused**? → **Dummy**.

## Notes that matter

- **Distinct over Random.** Uniqueness rarely needs randomness; a sequence is
  unique *and* deterministic.
- **Generate only for uniqueness**, never to "save typing" on a significant
  value — that hides intent.
- **Anonymous vs significant.** Make significant values loud (named constant);
  make irrelevant values quiet (a helper like `anonymousString()`), so the
  reader sees what matters.
- **Dummy ≠ Stub.** A Dummy is never used; the moment the SUT reads it, upgrade
  to a Stub/Fake.

## Connections

- The smells this prevents → `test-smells.md`.
- Building the surrounding fixture → `fixture-construction.md`.
- Doubles for collaborators → `test-doubles.md`.
- Asserting outcomes → `result-verification.md`.
