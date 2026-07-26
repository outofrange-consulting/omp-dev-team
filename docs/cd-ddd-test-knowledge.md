# CD / DDD / Test knowledge extraction (from upstream v7.5–7.6)

Deeper dig into the upstream `agentic-dev-team` DDD/CD/test knowledge to find
genuine gaps in our port. We were already rich on **DDD** (domain-modeling,
object-calisthenics, design-smells, ubiquitous-language, hexagonal) and on
**test** mechanics (test-pyramid, test-doubles, testing-quadrants, test-smells,
testability-patterns, fixture-construction, …). The real gap was **continuous
delivery** — we had CD *test* architecture but not CD *delivery* knowledge — plus
two specific deepenings.

## Added (on-demand knowledge, zero always-loaded cost)

| File | Source | Why it was a gap |
|---|---|---|
| `deployment-pipeline.md` | Humble & Farley | We had `cd-test-architecture` (test shape) but no pipeline stages/gates, build-once, env-parity, cycle-time reference |
| `cd-maturity-model.md` | Humble & Farley | No way to score delivery health (6 areas × 5 levels) or plan improvement |
| `release-strategies.md` | Humble & Farley | `platform-engineer` named blue-green/canary/flags but nothing backed deploy≠release, branch-by-abstraction, rollback-as-practice |
| `database-change-management.md` | expand/contract | No reference for versioned migrations, reversible-without-data-loss, decoupling DB from app change |
| `dependency-breaking-techniques.md` | Feathers | `legacy-code` listed only 8 of the catalog; this adds the full blocker→technique table |
| `value-patterns.md` | xUnit Test Patterns | No reference for test-value sourcing (literal/derived/generated/dummy) — a real test-data-smell gap |

## Wired into

- `platform-engineer` agent → a CD knowledge block (the 4 delivery docs).
- `cd-test-architecture` skill → cross-refs the delivery side.
- `legacy-code` skill → points to the full dependency-breaking catalog.
- `test-design` skill (`test-smell-review`) → points to value sourcing.
- All 6 added to `dev-team-knowledge/index.json` for anchor resolution.

## Verified
`ci-validate-json` 23/23 · every `skill://` ref in the new files resolves ·
extensions compile · unit suite green.

## Noted for the model-resolution follow-up
The `test-design` skill still references a stale `hooks/agent-model-resolve.sh`
(model resolution is OMP-native now: `modelRoles` + `@role` aliases; the plugin-side resolver was retired — see `docs/upstream-v8-v10.md`) — to be cleaned up in the
routing work.
