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
