---
name: build
description: >-
  Implement an approved plan: write code, write tests, run them, refactor, and
  inline-review each unit. Use after `dt plan-approve` (or `dt scope --trivial`).
model: claude-sonnet-4.6
metadata:
  tier: balanced
---

# build — execute the plan, test-after-with-refactoring

Implement the plan one unit at a time. Source edits are unlocked only because the
task was scoped trivial or the plan was approved — honor that plan; if reality
diverges from it, stop and go back to `/agent plan` rather than improvising scope.

## Loop, per unit

1. **Implement** the smallest shippable slice from the plan.
2. **Test** it — every behavior change ships with tests. Order is up to you
   (test-first is not enforced); the bar is that the unit's build + tests are
   green. Run the project's real commands; don't claim green without running them.
3. **Refactor after green** — take a deliberate pass over structure, naming,
   duplication, and "use the platform" while keeping tests green. Make changes
   only when there's a real opportunity.
4. **Inline review** — for a standard/complex unit, self-review for spec
   compliance first, then quality. Pull in a critic when warranted
   (`/agent security-review` for auth/crypto/input, `/agent test-review` for the
   tests). Fix actionable findings and re-run tests.

## Discipline

- Keep functions small and cohesive; prefer clear names over comments.
- Don't disable analyzers/linters to pass; fix the cause.
- Don't write secrets to `.env`/`*.pem`/`*.key` — `path-guard` blocks it.
- Don't touch frozen paths (`dt status` lists them) without `dt unfreeze`.

## Done

A unit is done when its build + tests are green and the inline review is clean.
When all units are done, stage the changes and hand off to `/agent review`. Report
the exact verification commands you ran and their results — faithfully, including
anything still failing or skipped.
