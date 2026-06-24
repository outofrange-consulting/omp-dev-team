# Effort-band model routing (bump-from-floor)

Apply the upstream "effort-band" routing idea (v7.0) to our port **without
breaking** the tier model or `copilot-preset`: the model is derived from the
**task size**, floored by the agent's declared tier.

## The insight

Our three tiers (`small`/`balanced`/`deep`) already *are* three effort bands. The
improvement over one-model-per-agent is to **derive the band from objective
signals** — and we have them: the `task-size-classifier`
(`trivial`/`standard`/`complex`), recorded by `/scope`. The agent's declared tier
becomes a **floor**; the size picks a target band; the effective band is the
higher of the two.

## How it works

`model-routing.json` gains an `effortBand`:

```
ladder:   [small, balanced, deep]
sizeBand: { trivial: small, standard: balanced, complex: deep }
```

Resolution (pure `effectiveBand(floor, size)` in `lib/shared.ts`):

```
effective = max_on_ladder(floor, sizeBand[size])
```

- An agent is **never routed below its floor** — high-stakes agents (deep floor:
  security/domain/arch-review, architect, security-engineer, codebase-recon)
  always hold at deep.
- **No size signal → the floor** (fully backward-compatible with today's static
  tiers).
- A cheap agent (small floor) rides the size: `small` on trivial, `balanced` on
  standard, `deep` on complex — so token spend tracks the work, and small tasks
  keep cheap agents cheap.

The `model-routing` extension reads the floor (`agentModel`) + size (plan-gate
state), **logs** every dispatch to `.omp/state/model-routing.log`, and:

- default **`advisory`** — warns when the dispatched tier ≠ the band tier;
- `DEV_TEAM_EFFORT_ROUTING=enforce` — blocks and names the model to use;
- `=off` — disables the band (floor tier only).

`copilot-preset` is untouched — the band picks a *tier*; `modelRoles` (or the
Copilot remap) resolves the concrete model.

## Decisions

- **Bump-from-floor, never below the agent's tier.** The agent tier is a quality
  floor; the size can only raise it. This keeps the north star (quality first):
  the band never under-powers a high-stakes agent, while still riding spend down
  for cheap agents on small tasks and up for everyone on complex work.
- **Default advisory, not enforce.** The orchestrator applies the rule; the
  extension audits and warns. `enforce` is opt-in so a not-yet-updated caller
  isn't bricked; `off` is the escape hatch.

## What this PR also cleans up (pre-existing routing debt)

- The orchestrator's **Resolution Procedure** described a Claude-Code hook
  (`agent-model-resolve.sh`, `.claude/model-overrides.json`, `updatedInput`,
  `deny`, a non-existent `docs/model-routing.md` + ADR 0004) the OMP extension
  never implemented. Rewritten to reality (native tier resolution + the
  effort-band logger) + the new behavior.
- 4 skills + the agent-registry referenced the same stale
  `hooks/agent-model-resolve.sh` — repointed to the `model-routing` extension.

Left as-is (separate, larger debt): the `/model-routing-check` skill's exec block
still targets the old `.claude/` resolver; `/routing` is the accurate effort-band
diagnostic and the skill now points to it.

## Verified
`ci-validate-json` 23/23 · extensions compile · unit suite green (incl. 13
`effectiveBand` cases) · no `agent-model-resolve.sh` references remain.
