---
description: TDD — write a failing test before changing source (RED → GREEN → REFACTOR)
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

**Follow RED → GREEN → REFACTOR for every unit of behavior.**

1. **RED** — write the smallest failing test that expresses the next behavior.
   Run it; paste the failing output.
2. **GREEN** — write the minimum code to make it pass. Run it; paste passing
   output.
3. **REFACTOR** — clean up with tests green.

No implementation without a failing test first. No scenario without a
corresponding test. Each step must leave the codebase in a working, committable
state. See `skill://test-driven-development`.

**Never edit a failing test/spec to make it pass — fix the code.** Editing
existing `.feature` BDD specs is **blocked** by `tdd-guard` (authoring a new spec
is fine). If a spec is genuinely wrong, change it deliberately via `/specs`, or
temporarily lift the block with `/allow-feature-edits` (re-protect with
`/protect-features`).
