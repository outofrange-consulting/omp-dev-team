# /build — execute an approved plan with TDD

Role: **orchestrator**. Phase 3. Implements an approved plan; does not create
plans or specs.

Arguments: `$ARGUMENTS` (optional `--plan <path>`; else newest approved plan in `plans/`).

## Run it

1. `read skill://build` and follow it exactly.
2. **Every step is TDD** (RED → GREEN → REFACTOR). No implementation without a
   failing test first. Paste fresh failing → passing output as evidence.
3. For parallel independent units, dispatch implementers with
   `isolation: "worktree"` on the `task` tool.
4. After each unit, run the **three-stage inline review**: spec-compliance →
   quality agents → browser (UI only). Auto-fix actionable issues and re-review
   up to 5 iterations; escalate the rest.
5. Before committing, run `/code-review`, then `/review-approve` to clear the
   review gate.

Each step must leave the codebase working and committable.
