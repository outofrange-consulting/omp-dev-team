---
name: build
description: >-
  Execute an approved implementation plan in the Code-First Small Batches
  cadence — one behavior at a time, IMPLEMENT then TEST then REFACTOR, with a
  refactor on every green. Gates each step on /impl-verify, runs inline review
  checkpoints, and produces verification evidence. Use when the user says
  "build this", "implement the plan", "start building", or after /plan has been
  approved.
argument-hint: "[--plan <path>]"
user-invocable: true
allowed-tools: read, write, edit, find, search, bash, task, ask
---

# Build

Role: orchestrator. This command implements an approved plan — it does not create plans or specs.

You have been invoked with the `/build` command.

## Orchestrator constraints

1. **Follow the plan exactly.** If the plan is wrong, stop and ask the user — do not deviate silently.
2. **One cadence: Code-First Small Batches.** Each behavior follows **IMPLEMENT → TEST → REFACTOR**, one small batch at a time, one agent doing all three. There is nothing to resolve and no per-plan opt-in — this is the only cycle a step follows (upstream ADR-0017; see `docs/plan-gate-over-tdd.md` for the measured cost result behind it). The **refactor runs on every green** — never deferred to an end-of-build pass, never skipped, never made conditional on task size. **Tests are frozen during REFACTOR** (behaviour-preserving means the tests do not move). Big-batch shapes are prohibited: never all the code then all the tests, never all the tests then all the code. A step is done only when `/impl-verify` reports its strict build + tests green (`tests-required` rule).
3. **Incremental.** Each step must leave the codebase in a working, committable state.
4. **Verification evidence required.** Paste the fresh `/impl-verify` verdict before claiming a step is done.
5. **Review checkpoints.** After each unit of work, run inline review (spec-compliance first, then quality agents). Max 2 correction iterations before escalating.
6. **Be concise.** Report step status and verification evidence, no narration.

## Parse Arguments

Arguments: $ARGUMENTS

- `--plan <path>`: Path to the plan file. If omitted, search `plans/` for the most recently modified plan with status `approved`.

## Steps

### 1. Find the plan

If `--plan` was provided, read that file. Otherwise, search `plans/` for `.md` files and find the most recently modified one with `**Status**: approved`. If no approved plan is found, tell the user: "No approved plan found. Run `/plan` first, then approve it."

### 2. Verify plan status

Read the plan file. If the status is not `approved`, ask the user: "This plan has status '<status>'. Approve it before building, or continue anyway?"

### 3. Verify acceptance criteria (gate)

Before implementation begins, dispatch a spec-compliance-review subagent in **criteria verification mode** (see the `prompts/spec-reviewer.md` template, § Pre-build criteria verification mode — a plugin-relative path, the same form the orchestrator uses, because OMP substitutes the plugin-root variable only in discovery configs, never inside a skill body). Pass the plan's acceptance criteria and per-step test expectations.

The reviewer evaluates each criterion for:

- **Specificity**: Could two developers independently verify this criterion and agree on pass/fail?
- **Testability**: Can this criterion be validated with a test or observable output?
- **Completeness**: Are edge cases and error conditions addressed?

If any criteria are flagged:

1. Present the findings to the user with the reviewer's suggested improvements
2. Ask: "Revise these criteria before building, or proceed anyway?"
3. If the user overrides, log the override in the build output and continue
4. If the user revises, update the plan file and re-verify

### 4. Implement each step

Work the plan **wave by wave** using the `## Parallelization` section (the waves derived from each slice's `Depends-on`). Within a wave, independent slices may build concurrently; a barrier holds the next wave until the current one is reconciled green.

**Resolve effective concurrency first.** The effective number of slices to build at once is `min(slices in the wave, DEV_TEAM_MAX_PARALLEL_BUILDS)` — default max **2**; a non-positive or non-integer value clamps to **1**.

- **Sequential fallback (effective concurrency = 1):** a fully-dependent plan (every wave has one slice), `DEV_TEAM_MAX_PARALLEL_BUILDS=1`, or a harness without parallel `task` fan-out → build slices one at a time in dependency order in a single worktree. No worktree fan-out, no reconcile step.
- **Concurrent dispatch (effective concurrency > 1):**
  1. Dispatch each independent slice in the wave to its **own** git worktree via the `task` tool (`isolation: "worktree"`), up to the effective concurrency. Each slice's changes stay isolated until reconcile, and each slice still runs its tests via `/impl-verify` and inline review gates.
  2. **Report the concrete level and cost**, e.g. *"building wave 2 — 2 slices concurrently; faster wall-clock but burns token budget faster."*
  3. **Barrier + reconcile** once the wave's slices finish: merge the slice worktrees into the integration branch order-independently and run the full test suite before any next-wave slice starts.
  4. **Loud halt, never silent:**
     - A **failing slice** → stop the wave, name the failing slice, list which same-wave slices succeeded and where their (preserved) worktrees are, and start no next-wave slice. Resume rebuilds only the incomplete slice.
     - A **reconcile conflict** (two same-wave diffs touch one file — the Parallelization Critic should have caught this at plan time) → stop, name the file, pick no side, and start no next-wave slice.

For each step within a slice, dispatch the **`software-engineer`** agent directly via the `task` tool — one call per step. There is no implementer prompt template: it was retired per upstream ADR-0029 because it restated what the agent already knows and was a second place the cadence had to be kept in sync. The per-step contract below *is* the template; pass the step **and the slice's Gherkin scenario(s)** — the scenarios are the behavioral contract the step's test must satisfy. Pass no `effort:`: build is post-plan, so it runs at the agent's declared floor (`agents/orchestrator.md` § Resolution Procedure).

1. **IMPLEMENT** — Write the step's code for **one behavior**. Don't add behavior beyond what the step requires, and don't do surrounding cleanup yet. Prefer real code over mocks.
2. **TEST** — Write that behavior's test, covering the slice scenario the step traces to, then run **`/impl-verify`** (strict stack build + tests, bounded fix counter). **PASS** → proceed. **FAIL** → fix the *cause* and re-run; never silence the gate (`no-disable-analyzers`). **HALT** (fix budget spent) → escalate to the human. Paste the verdict as evidence.
3. **REFACTOR (on every green)** — Take a deliberate refactor pass **every** time the batch goes green: scan for structure, naming, duplication, and reinvented built-ins (the `refactor-opportunity-review` lens), apply behavior-preserving cleanups, then re-run `/impl-verify` and keep it green. **Tests are frozen during REFACTOR** — if a cleanup needs a test to change, it is not behaviour-preserving; split it into its own batch. The pass is always taken; making changes is conditional on finding a real opportunity. Never defer it to an end-of-build sweep. Refactors beyond the step's scope are logged as follow-ups, not done inline.

4. **Inline review checkpoint** — Route review depth based on the step's **Complexity** classification:
   - **trivial**: Skip inline review. The final `/code-review` (step 6) covers all modified files.
   - **standard**: Run `/review-agent spec-compliance-review` against changed files. If it passes, run quality review agents relevant to what changed. If review finds actionable issues (error/warning with high/medium confidence), auto-fix and re-run failed agents (up to 5 iterations per the review-fix loop in `agents/orchestrator.md`). Escalate to user if the loop doesn't converge.
   - **complex**: Run `/review-agent spec-compliance-review`, then the full quality agent suite including the `@slow`-role agents (security-review, domain-review, arch-review). Same review-fix loop applies.
   - If no complexity is specified, default to **standard**.
   - **UI changes (any complexity)**: After quality review passes, run browser verification via `/skill:browse` in automated smoke test mode. Skip with warning if the dev server is not running. See `agents/orchestrator.md` Stage 3.
5. **Mark step done** — Use the Edit tool to update the plan file's `## Build Progress` section on disk:
   - Change `- [ ] Step N.M: <title>` to `- [x] Step N.M: <title>` for the completed step.
   - When every step under a slice is `[x]`, check off the parent `- [ ] Slice N: <title>`.
   - For each acceptance criterion verified by this step, change `- [ ]` to `- [x]` in the Build Progress `### Acceptance Criteria` subsection.
   - After all slices are `[x]`, change `**Status**: approved` to `**Status**: in-progress`.
   - This disk write is the durable commit. If a `/clear` occurs, `/continue` reads `## Build Progress` to determine the resume point without needing conversation history.

#### Per-step contract for the implementation subagent

This is what the `software-engineer` call carries. **The design is settled — do not design.** The subagent is executing one step of an approved plan, not re-opening it.

**What it receives**

- The plan step it is executing (description, complexity, target files, target behavior, draft commit message)
- The Gherkin scenario(s) for the slice the step belongs to — the behavioral contract its tests must satisfy
- A reference to the full plan (the plan file under `plans/`, or the plan progress file) — read it for context, but do not work outside the assigned step
- Existing source files relevant to the step, and any prior step output this step depends on
- A worktree path when running in parallel with other slices (`isolation: "worktree"`)

**Constraints**

- **Honor the gate.** No completion without a green `/impl-verify` verdict pasted as evidence.
- **Do not work outside the assigned step.** A bug or improvement found in adjacent code is flagged to the orchestrator as a follow-up, not fixed inline.
- **Do not silently revert unrelated changes** on a worktree merge conflict. Stop and escalate.
- **Do not claim completion without verification evidence.** No "tests passed" from memory.
- **No preamble, no narration.** Output only the structured result below.

**Escalate to the orchestrator when**

- The plan step contradicts the slice's scenarios or acceptance criteria.
- The required behavior cannot be tested in isolation (an architectural gap in the plan).
- A dependency it needs was not produced by a prior step that should have produced it.
- After 2 fix attempts `/impl-verify` still reports FAIL/HALT for a reason it cannot resolve.

**Output format**

```json
{
  "step": "<step number and title from the plan>",
  "status": "complete | blocked | escalated",
  "filesChanged": ["<path>", "..."],
  "evidence": {
    "implVerify": "<the /impl-verify verdict line (PASS, or the resolved FAIL/HALT history)>",
    "testsAdded": ["<test name or path>", "..."]
  },
  "followUps": [
    { "type": "refactor | bug | adjacent-improvement", "description": "<short note>", "file": "<path>" }
  ],
  "escalation": {
    "reason": "<why escalating, if status=escalated|blocked>",
    "context": "<what the orchestrator needs to resolve it>"
  },
  "summary": "<2-3 sentences: what was implemented and what the /impl-verify verdict demonstrates>"
}
```

### 5. Run full test suite

After all steps are complete, run the full test suite. Paste the output as final verification evidence.

### 6. Run code review

Run `/code-review` against all files modified during the build.

### 7. Update plan status

Use the Edit tool to change `**Status**: in-progress` to `**Status**: implemented` in the plan file. Briefly confirm completion and direct the user to `/pr`.

## Escalation

Stop and ask the user when:

- A test fails for an unexpected reason after 3 attempts
- The plan requires architectural decisions not covered by the plan
- A review checkpoint fails after 2 correction iterations
- You discover the plan is incomplete or contradictory

## Integration

- `/specs` produces the intent, architecture, and acceptance-criteria artifacts that inform the plan
- `/plan` decomposes the feature into slices, authors each slice's Gherkin, and produces the plan this command executes
- `/code-review` runs the full review suite after implementation
- `/pr` creates the pull request after a successful build
- `/continue` can resume a partially completed build across sessions
- The progress-guardian agent tracks step completion against the plan
