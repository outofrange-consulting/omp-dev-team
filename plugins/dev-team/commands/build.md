# /build — execute an approved plan with TDD

Role: **orchestrator**. Phase 3. Implements an approved plan; does not create
plans or specs.

Arguments: `$ARGUMENTS` (optional `--plan <path>`; else newest approved plan in `plans/`).

## Run it

1. `read skill://build` and follow it exactly.
2. **Every step is TDD** (RED → GREEN → REFACTOR). No implementation without a
   failing test first. Paste fresh failing → passing output as evidence. At GREEN
   and before claiming a unit done, run **`/impl-verify`** (deterministic gate:
   strict stack build — e.g. `dotnet build -warnaserror` — + tests, bounded fix
   counter). Act on its verdict: PASS → proceed; FAIL → fix the cause and re-run
   (never silence the gate — `no-disable-analyzers`); HALT → escalate to the
   human. Configure stacks/budget in `.omp/dev-team.json` (`implVerify`).
3. Execute the plan **wave by wave** (from its `## Parallelization` section):
   independent slices in a wave build concurrently via the `task` tool with
   `isolation: "worktree"` (effective concurrency `min(wave width,
   DEV_TEAM_MAX_PARALLEL_BUILDS)`, default max 2), barrier-reconciled green
   before the next wave. Plans with no `Depends-on` (all wave 1) or
   `DEV_TEAM_MAX_PARALLEL_BUILDS=1` fall back to in-order sequential execution.
4. After each unit, run the **three-stage inline review**: spec-compliance →
   quality agents → browser (UI only). Auto-fix actionable issues and re-review
   up to 5 iterations; escalate the rest.
5. Before committing, run `/code-review`, then `/review-approve` to clear the
   review gate.

Each step must leave the codebase working and committable.
