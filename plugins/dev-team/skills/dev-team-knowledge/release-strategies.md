# Release Strategies

**Deploy ≠ release.** Deployment puts code on servers; release exposes behavior
to users. Keeping them separate is what makes continuous delivery safe. Adapted
from *Continuous Delivery* (Humble & Farley, ch. 10 & 14). Used by the
platform-engineer and in planning to keep trunk shippable.

## Decouple deployment from release

- **Feature toggle / flag** — ship code dark; turn behavior on at runtime; keep a
  kill-switch. Toggles are **inventory** — remove each one once the decision is
  permanent, or they rot into config complexity.
- **Branch by abstraction** — introduce an abstraction over the thing you're
  replacing, migrate callers on mainline, then delete the old path. Big changes
  without a long-lived branch.
- **Dark launching** — run new code paths against real production traffic with
  the result hidden from users, to derisk performance/correctness.
- **Keep mainline releasable** — every commit is shippable; hide incomplete work
  behind toggles/abstractions, **not** branches. Trunk-based development, commit
  at least daily.

## Deployment patterns

| Pattern | How | Rollback | Trade-off |
|---|---|---|---|
| **Blue-green** | Two identical envs; switch traffic to the new one | Switch back | Doubles infra during transition |
| **Canary** | Route a small % to the new version; watch metrics; ramp | Stop ramp, drain | Needs good metrics + routing |
| **Rolling** | Replace instances in batches | Roll backward | Mixed versions live at once |
| **Recreate** | Stop old, start new | Redeploy old | Downtime |

Keep as few production versions live as possible (ideally two during a
transition). Mixed versions imply the schema/API must satisfy **both**.

## Rollback is a practiced capability, not a hope

- Maintain the ability to roll back; back up prod state; **rehearse** it.
- Simplest reliable rollback = redeploy the last known-good artifact through the
  same pipeline.
- Pair with **expand/contract** schema migrations so data stays compatible both
  ways. Prefer rollback over ad-hoc hot-fixes.

## Planning hook

Prefer feature slices that keep trunk releasable at every step — a slice that
can only ship "all at once" is a planning smell (raise it in `/plan`).

## Connections

- Schema compatibility for rollback → `database-change-management.md`.
- The pipeline that promotes/rolls back → `deployment-pipeline.md`.
- Where this sits on the curve → `cd-maturity-model.md`.
