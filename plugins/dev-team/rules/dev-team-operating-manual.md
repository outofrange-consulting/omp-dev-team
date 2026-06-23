---
description: Dev-team operating manual — orchestration pipeline, model tiers, guardrails (always loaded)
alwaysApply: true
---

# Dev-Team — Orchestration Pipeline (Oh-My-Pi port)

This plugin runs a persona-driven AI development team on Oh-My-Pi (OMP),
ported from `bdfinst/agentic-dev-team`. The **orchestrator** agent is the
central dispatcher; it routes work to specialized agents via the `task` tool
based on task type, complexity, and required expertise.

## North Star

Every change must reduce friction for someone getting work done: **fewer
missteps, less rework, lower token cost.** Measure friction, don't assume it —
the `telemetry` extension and `/cost-report` exist to close the loop. A change
that cannot name the friction it removes does not ship.

## Output guardrails

1. **Write to files, not chat.** Plans, designs, ADRs, reports, and code go to
   files. Chat is for decisions, status, and questions.
2. **Plan-only means plan-only.** When asked for a plan, produce only the plan.
   The plan is a gate, not a warm-up.
3. **No preamble / "I will…" narration.** State results directly. End a turn
   with one sentence: what changed and what's next.
4. **Verification evidence required.** Paste fresh test output before claiming a
   step is done.

## How this maps to OMP

- **Agents** live in `.omp/agents/*.md` and are spawned with the `task` tool
  (the orchestrator declares `spawns`). Persona agents give behavioral
  guardrails; the real win of subagents is **context isolation** — a subagent
  reads 20 files and returns 10 lines.
- **Skills** live in `.omp/skills/*/SKILL.md`. Read one with `read skill://<name>`
  or invoke as `/skill:<name>`. Load on demand, not all at once.
- **Knowledge** (registries, rubrics, detection patterns) lives in
  `skill://dev-team-knowledge/`. Resolve a section anchor via `skill://dev-team-knowledge/index.json`,
  then `read` just that section with offset/limit.
- **Workflow commands** live in `.omp/commands/*.md`: `/specs`, `/plan`,
  `/build`, `/pr`, `/code-review`, `/review-agent`, `/continue`, `/triage`, …
- **Guardrails** are OMP **extensions** in `.omp/extensions/`. They split into
  two honestly-different classes — don't conflate them:
  - **Enforcement** (`PreToolUse` that returns `block: true` — the agent cannot
    proceed): `path-guard` (denies writing secrets/credentials via edit **and**
    shell — `>`, `tee`, `sed -i`, `cp/mv`), `review-gate` (blocks `git commit`
    until `/code-review` + `/review-approve`; explicit `--no-verify` is the
    documented human override), `freeze-guard` (`/freeze` `/unfreeze` — blocks
    edits/shell-writes to frozen globs), and `tdd-guard`'s `.feature` block (you
    fix code, not the spec; `/allow-feature-edits` to override).
  - **Advisory** (warns, does not block): `destructive-guard` (caution on
    hard-to-reverse shell commands; *blocks* only under `/careful on`),
    `tdd-guard`'s RED→GREEN nudge, and `model-routing` (dispatch tier log +
    `/routing` diagnostic).
  - **State trust.** Toggle state (`freeze`, `careful`, `review-gate`) lives
    **outside the working tree** (`~/.omp/state/dev-team/<repo>/`, override
    `OMP_DEVTEAM_STATE_DIR`) so the agent can't flip a guard off with an in-repo
    write. This is advisory-grade enforcement against a cooperative agent and
    accidental footguns — **not a security sandbox**: an agent running arbitrary
    shell could still reach the out-of-tree path. Treat secrets/destruction as
    defense-in-depth, not a hard boundary.
- **Verification** of a quality gate is by the toolchain, not by vibes: a step
  is "done" only with fresh build/test output (see the `no-disable-analyzers`
  and `source-of-truth` rules; `/impl-verify` runs the stack's real build+test).

## Model routing (tiers → models)

Each agent declares a tier in its `model:` frontmatter. The mapping is native
(`.omp/config.yml` `modelRoles` + the agent frontmatter); the source of truth is
`skill://dev-team-knowledge/model-routing.json`.

| Tier | Frontmatter | Resolves to | Used for |
|---|---|---|---|
| small | `pi/smol` | cheap cloud model (via `modelRoles.smol`, default Haiku) | lexical/structural pattern matching, checklist review (naming, complexity, a11y, svelte, js-fp, token-efficiency) |
| balanced | `claude-sonnet-4-6` | Sonnet (cloud) | semantic analysis, most team & review agents, orchestrator |
| deep | `claude-opus-4-8` | Opus (cloud) | cross-file reasoning, design synthesis, threat modeling, recon |

**The small tier is a cheap-cloud, high-volume tier** — it replaces expensive
Sonnet/Opus calls for lexical/structural checks, not the other way round. Keep it
on the cheapest capable model (default `claude-haiku-4-5`; cheaper via the
copilot-preset plugin). The `model-routing` extension logs each dispatch's tier;
run `/skill:model-routing-check` or the `/routing` command for the effective map.

## Request processing flow

Trivial task (typo, simple query) → route directly to one agent. Non-trivial →
**Research → Plan → Implement**, with a human gate between phases and a fresh
context per phase (write a progress file to `memory/` to onboard the next phase).

1. **Research** — find relevant files, trace data flows, scope the problem.
   Subagents explore and return concise findings. For non-trivial features write
   a design doc to `docs/specs/`. (`/specs`, Design Doc, Domain Analysis skills.)
2. **Human gate.**
3. **Plan** — decompose into vertical slices, author each slice's Gherkin
   scenarios, specify files/snippets/TDD steps/verification. Each slice declares
   `Depends-on` so independent slices group into build waves. Before the human
   gate, run the **five plan-review personas** in parallel (acceptance, design,
   UX, strategic, parallelization). (`/plan`.) The plan is the primary review
   artifact.
4. **Human gate.**
5. **Implement** — execute the plan with **RED-GREEN-REFACTOR**. Parallel
   independent units use `isolation: "worktree"` on `task`. After each unit run
   the **three-stage inline review** (spec-compliance → quality agents → browser
   for UI). Auto-fix actionable issues (error/warning, high/medium confidence)
   and re-review up to 5 iterations; escalate the rest. Run `/code-review` then
   `/review-approve` before committing. (`/build`.)
6. **Human gate.**
7. **PR / branch workflow** (`/pr`, Branch Workflow skill).
8. **Learning loop** — log metrics, refine routing, record decisions to
   `memory/decisions.md`.

## ATDD

All development is Acceptance-Test-Driven. The spec describes the change and its
goals; `/plan` decomposes it into vertical slices and authors the Gherkin
scenarios before implementation. No implementation without a corresponding
scenario; no scenario without a corresponding test.

## Decision log

Log non-obvious routing and architectural decisions to `memory/decisions.md` so
they persist across resets and onboard later phases. Don't log routine choices.
