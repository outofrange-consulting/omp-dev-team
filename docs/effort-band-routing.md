# Effort-band model routing

Apply the upstream "effort-band" routing idea (v7.0) to our port **without
breaking** the tier model or `copilot-preset`: the model is derived from the
**task size**, not only from a static per-agent tier.

## The insight

Our three tiers (`small`/`balanced`/`deep`) already *are* three effort bands. The
upstream improvement over one-model-per-agent is to **derive the band from
objective signals** and let it shift an agent's base — more deterministic, and it
ties spend to the work. We now have those signals: the `task-size-classifier`
(`trivial`/`standard`/`complex`), recorded by `/scope` in plan-gate state.

## How it works

`model-routing.json` gains an `effortBand`:

```
ladder: [small, balanced, deep]
effort: { trivial: -1, standard: 0, complex: +1 }
protectDownshift: [deep]      # safety agents never downshift
```

Resolution (pure `effectiveBand(base, size)` in `lib/shared.ts`):
`idx = clamp(ladder.indexOf(base) + effort[size], 0, 2)`, with a `deep` base
never shifting down. The orchestrator passes the **effort-band tier** when it
spawns each agent. The `model-routing` extension:

- **logs** every dispatch (`base`, `size`, `effective`, `dispatched`) to
  `.omp/state/model-routing.log`;
- by default (**`advisory`**) **warns** when the dispatched tier ≠ the band tier;
- with `DEV_TEAM_EFFORT_ROUTING=enforce` **blocks** and names the model to use;
- with `=off` disables the band (pure static tiers).

`copilot-preset` is untouched — the band picks a *tier*; `modelRoles` (or the
Copilot remap) resolves the concrete model.

## Decisions taken

- **Aggressive downshift on trivial**: every base downshifts on a trivial task
  **except** a `deep` base (security/domain/arch reviewers, architect, recon stay
  deep). Max token saving on small work; safety preserved.
- **Default advisory, not enforce**: the orchestrator applies the rule; the
  extension audits and warns. `enforce` is opt-in so a not-yet-updated caller
  isn't bricked (every mismatched dispatch would otherwise block). `off` is the
  escape hatch.

## What this PR also cleans up (pre-existing routing debt)

- The orchestrator's **Resolution Procedure** described a Claude-Code hook
  (`agent-model-resolve.sh`, `.claude/model-overrides.json`, `updatedInput`,
  `deny`, `docs/model-routing.md`, ADR 0004) that the OMP extension never
  implemented. Rewritten to describe reality (native base resolution + the
  effort-band logger) + the new behavior.
- 4 skills + the agent-registry referenced the same stale
  `hooks/agent-model-resolve.sh` — repointed to the `model-routing` extension.

Left as-is (separate, larger debt): the `/model-routing-check` skill's exec
block still targets the old `.claude/` resolver; `/routing` is the accurate
effort-band diagnostic and the skill now points to it.

## Verified
`ci-validate-json` 23/23 · extensions compile · unit suite green (incl. 11
`effectiveBand` cases) · no `agent-model-resolve.sh` references remain.
