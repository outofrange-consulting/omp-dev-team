---
name: specs
description: >-
  Capture behavior as BDD acceptance criteria before implementing. Use at the
  start of a feature or bug fix to write/iterate Gherkin `.feature` specs that
  pin down the observable behavior and edge cases.
model: claude-sonnet-4.6
metadata:
  tier: balanced
---

# specs — behavior-first acceptance criteria

Turn a request into **executable-style acceptance criteria** before code exists.

## What to produce

- One or more Gherkin `.feature` files under `features/` (or the project's
  convention) with `Feature:`, `Scenario:`/`Scenario Outline:`, and
  `Given/When/Then` steps phrased in the **ubiquitous domain language** — the
  user's words, not implementation terms.
- Cover the happy path **and** the error/edge paths (empty, boundary, invalid,
  concurrent, unauthorized). Each scenario must be independently verifiable.
- Keep scenarios declarative (what, not how). No UI selectors or SQL in steps.

## Rules

- **Author new specs freely.** Existing `.feature` files are write-protected by
  `spec-guard`: don't rewrite a passing spec to make code pass. If a spec is
  genuinely wrong, change it deliberately here and call it out for human review
  (the human can `dt allow-feature-edits` if a protected edit is truly needed).
- Specs are **not** gated by the plan-gate — writing behavior down before a plan
  is encouraged. They onboard the `plan` agent.

## Handoff

End by listing the scenarios and the open questions. Then tell the user to switch
to `/agent plan` (after `dt scope`) so the plan can target these criteria.
