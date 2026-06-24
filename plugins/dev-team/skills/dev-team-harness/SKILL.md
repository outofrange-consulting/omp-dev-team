---
name: dev-team-harness
description: >-
  How the dev-team plugin maps onto Oh-My-Pi — agents, skills, knowledge,
  commands, the influence-vs-enforcement guard taxonomy, out-of-tree guard
  state, and the verification stance. Read when you need to understand the
  harness itself (which guard blocks what, where state lives, how to load
  knowledge), not for routine task work.
---

# Dev-Team harness — how it maps to Oh-My-Pi

Reference for the plugin's moving parts. The always-loaded operating manual
points here so it can stay small; load this only when you actually need it.

## Components

- **Agents** live in `.omp/agents/*.md` and are spawned with the `task` tool
  (the orchestrator declares `spawns`). Persona agents give behavioral
  guardrails; the real win of subagents is **context isolation** — a subagent
  reads 20 files and returns 10 lines.
- **Skills** live in `.omp/skills/*/SKILL.md`. Read one with `read skill://<name>`
  or invoke as `/skill:<name>`. Load on demand, not all at once.
- **Knowledge** (registries, rubrics, detection patterns) lives in
  `skill://dev-team-knowledge/`. Resolve a section anchor via
  `skill://dev-team-knowledge/index.json`, then `read` just that section with
  offset/limit.
- **Workflow commands** live in `.omp/commands/*.md`: `/specs`, `/plan`,
  `/build`, `/pr`, `/code-review`, `/review-agent`, `/continue`, `/triage`, …

## Guardrails — influence vs enforcement (don't conflate them)

Guards are OMP **extensions** in `.omp/extensions/`, in two honestly-different
classes:

- **Enforcement** (`PreToolUse` that returns `block: true` — the agent cannot
  proceed): `plan-gate` (blocks edits to production source until the task is
  scoped and, if non-trivial, a plan is approved — enforces **pre-analysis →
  (trivial | plan) → build → review** for agent and human alike; commands
  `/scope`, `/trivial`, `/plan-approve`, `/plan-reset`), `path-guard` (denies
  writing secrets/credentials via edit **and** shell — `>`, `tee`, `sed -i`,
  `cp/mv`), `review-gate` (blocks `git commit` until `/code-review` +
  `/review-approve`; explicit `--no-verify` is the documented human override),
  `freeze-guard` (`/freeze` `/unfreeze` — blocks edits/shell-writes to frozen
  globs), and `spec-guard`'s `.feature` block (you fix code, not the spec;
  `/allow-feature-edits` to override).
- **Advisory** (warns, does not block): `destructive-guard` (caution on
  hard-to-reverse shell commands; *blocks* only under `/careful on`) and
  `model-routing` (dispatch tier log + `/routing` diagnostic).

**State trust.** Toggle state (`freeze`, `careful`, `review-gate`, `plan-gate`)
lives **outside the working tree** (`~/.omp/state/dev-team/<repo>/`, override
`OMP_DEVTEAM_STATE_DIR`) so the agent can't flip a guard off with an in-repo
write. This is advisory-grade enforcement against a cooperative agent and
accidental footguns — **not a security sandbox**: an agent running arbitrary
shell could still reach the out-of-tree path. Treat secrets/destruction as
defense-in-depth, not a hard boundary.

## Verification stance

A quality gate is verified by the **toolchain, not by vibes**: a step is "done"
only with fresh build/test output. See the `no-disable-analyzers` rule (never
silence a gate) and `source-of-truth` rule (cite code/data/telemetry, not
memory). `/impl-verify` runs the stack's real strict build + tests and returns a
bounded PASS/FAIL/HALT verdict.

## Plan-first, tests required (not test-first)

The process leverage is the **plan gate**, not test ordering. `/plan` decomposes
a spec into vertical slices and authors the Gherkin scenarios (the behavioral
contract) and each slice's test list before the build is unlocked
(`/plan-approve`). Tests are **required** for behavior changes but **test-first
is not** — write code and tests in any order; a unit is done only when
`/impl-verify` is green (`tests-required` rule). This replaces the former
test-first (TDD) enforcement.
