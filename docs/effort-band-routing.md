# Effort-band model routing (phase-aware bump-from-floor)

Apply the upstream "effort-band" routing idea (v7.0) to our port **without
breaking** the tier model or `copilot-preset`: the model is derived from the
**task size and the pipeline phase**, floored by the agent's declared tier.

## The insight

Our three tiers (`small`/`balanced`/`deep`) already *are* three effort bands. The
improvement over one-model-per-agent: **derive the band from objective signals**
(the `task-size-classifier`, recorded by `/scope`) — and spend the effort where
it pays. The effort belongs in **spec/plan**: a complex task needs deep reasoning
to design and decompose; once the plan is solid, **implementation is routine**.
So the size raises the band **only while planning**, and the build runs at the
floor.

## How it works

`model-routing.json` gains an `effortBand`:

```
ladder:     [small, balanced, deep]
sizeBand:   { trivial: small, standard: balanced, complex: deep }
bumpStages: [needs-plan]          # the planning phase: /scope -> /specs -> /plan
```

Resolution (pure `effectiveBand(floor, size, stage)` in `lib/shared.ts`):

```
effective = (stage in bumpStages) ? max_on_ladder(floor, sizeBand[size]) : floor
```

- **Planning** (`stage = needs-plan`): the size bumps the band — a `complex` plan
  runs the architect + the five plan-review critics at `deep`.
- **Build/review** (`stage = plan-approved`): **no bump** — implementers and
  reviewers run at their **floor**. Don't spend `deep` on mechanical
  implementation once the plan is solid.
- **Never below the floor** — high-stakes agents (deep floor: security/domain/
  arch-review, architect, security-engineer, codebase-recon) always hold at deep.
- **No signal / trivial / unscoped → the floor** (backward-compatible with
  today's static tiers).

The `model-routing` extension reads the floor (`agentModel`) + size + stage
(plan-gate state), **logs** every dispatch to `.omp/state/model-routing.log`, and:

- default **`advisory`** — warns when the dispatched tier ≠ the band tier;
- `DEV_TEAM_EFFORT_ROUTING=enforce` — blocks and names the model to use;
- `=off` — disables the band (floor tier only).

`copilot-preset` is untouched — the band picks a *tier*; `modelRoles` (or the
Copilot remap) resolves the concrete model.

## Decisions

- **Effort into spec/plan, not the build.** A complex task bumps the *planning*
  agents to deep; the build/review runs at the floor. This matches "put the
  package on the plan — if the plan is solid, implementation is trivial," and it
  avoids the failure mode of routing every lexical reviewer (naming, complexity,
  a11y) on opus just because the task is complex.
- **Bump-from-floor, never below the agent's tier.** The tier is a quality floor;
  the size can only raise it, and only while planning. Keeps the north star
  (quality first) without over-spending.
- **Default advisory, not enforce.** The orchestrator applies the rule; the
  extension audits and warns. `enforce` is opt-in so a not-yet-updated caller
  isn't bricked; `off` is the escape hatch.

## Optional: trivial downshift (off by default)

For teams that want to squeeze the fast path further, set
`effortBand.trivialDownshift: true`. On a **trivial**-staged task (`downshiftStages`,
default `["trivial"]`) each agent routes **one band below its floor** — except a
floor in `protectDownshift` (default `["deep"]`, the safety agents), which holds.
This is the **only** case an agent is routed below its declared tier; left off,
the never-below-floor guarantee stands. The bump-on-planning behavior is
unchanged.

## Pre-existing routing debt cleaned up

- The orchestrator's **Resolution Procedure** described a Claude-Code hook
  (`agent-model-resolve.sh`, `.claude/model-overrides.json`, `updatedInput`,
  `deny`, a non-existent `docs/model-routing.md` + ADR 0004) the OMP extension
  never implemented. Rewritten to reality + the new behavior.
- 4 skills + the agent-registry referenced the same stale
  `hooks/agent-model-resolve.sh` — repointed to the `model-routing` extension.

Now removed: the legacy `/model-routing-check` skill + command described a
`.claude/` resolver (`model-resolve.sh --dump-map`, `.claude/model-overrides.json`,
`.claude/metrics/model-routing.log`, an endpoint probe, a non-existent
`docs/model-routing.md`) that the OMP plugin never implemented — its exec block
targeted only absent files. Deleted; the `model-routing` extension's `/routing`
command is the single accurate diagnostic (tier map + effective band per floor for
the current stage and task size), and all references now point to it.

## Verified
`ci-validate-json` 23/23 · extensions compile · unit suite green (incl. 11
phase-aware `effectiveBand` cases) · no `agent-model-resolve.sh` references remain.
