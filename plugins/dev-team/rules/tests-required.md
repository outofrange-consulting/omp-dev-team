---
description: Tests are required for behavior changes — but test-first is not; a unit isn't done until its tests pass
globs:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.py"
  - "**/*.go"
  - "**/*.rs"
  - "**/*.java"
  - "**/*.kt"
  - "**/*.cs"
---

# Tests required (test-first optional)

**Every behavior change ships with tests.** But **test-first ordering is not
required** — write the code and its tests in whichever order fits the work. A
unit is simply **not done** until its tests exist and pass.

- **Verify by running them.** `/impl-verify` runs the stack's strict build +
  tests and returns a bounded verdict; paste it as your evidence
  (`source-of-truth` rung 3). No "tests should pass" from memory.
- **Never edit a failing test to make it pass — fix the code.** Editing an
  existing `.feature` BDD spec is blocked by `spec-guard` (authoring a new spec
  is fine); change a wrong spec deliberately via `/specs`.
- **Never delete, skip, or weaken tests to go green** — see `no-disable-analyzers`.
- Match the existing test framework and style.

**Why not test-first.** For AI agents, RED → GREEN → REFACTOR *ordering* adds
little over "tests required + a strong plan gate." The leverage lives in the
plan, not the test sequence: the `plan-gate` extension enforces
**pre-analysis → (trivial | plan) → build → review** before any source edit.
