---
name: design-doc
description: Produce a written design document in docs/specs/ and get human approval before planning begins. Use during research when a feature request, architectural change, or non-trivial task enters the pipeline, or when the user says "brainstorm", "design", "spec", or "let's think through this".
model: claude-sonnet-4.6
metadata:
  tier: balanced
---

# design-doc — capture intent before planning

Research explores what exists; this adds a structured output: a design document capturing the proposed approach and getting human approval before planning. Misunderstandings caught at design time cost minutes; caught at implementation time they cost hours.

## Constraints

- Do not start planning without an approved design doc for non-trivial features.
- The design doc captures intent and approach, not file-level changes — it is not a plan.
- Do not skip alternatives analysis — a design doc with one option is a plan, not a design doc.
- The human must explicitly approve the design doc before proceeding.
- **Do not write code, scaffold a project, or take any implementation action** until the design doc is approved. It is a gate, not a suggestion — run `dt plan-approve` only after approval.

## Rationalization prevention

| Excuse | Reality |
|--------|---------|
| "Too simple to need a design doc" | Simple projects harbor unexamined assumptions. The doc will be short — just write it. |
| "I already know the approach" | Then it takes 5 minutes to write down. And the human might disagree. |
| "Writing a spec slows us down" | Misunderstandings at design time cost minutes; at implementation time, hours. |
| "The requirements are clear enough" | Clear to you. The human may interpret them differently. Write it down and verify. |

## When to produce a design doc

| Task type | Required? |
|-----------|-----------|
| New feature | Yes |
| Architectural change | Yes |
| Cross-cutting refactor | Yes |
| API design or redesign | Yes |
| Bug fix | No (unless the fix requires design decisions) |
| Typo/config/doc fix | No |
| Single-file change | No (unless it changes behavior significantly) |

## Document structure

Save to `docs/specs/{feature-name}.md`:

```markdown
# {Feature Name} — Design Document

## Problem Statement
What problem are we solving? Who experiences it? What happens if we don't solve it?

## Proposed Approach
High-level description of the solution. How does it work? Key components?

## Alternatives Considered
| Approach | Pros | Cons | Why rejected |
|----------|------|------|-------------|

At least two alternatives. "Do nothing" counts as one.

## Key Decisions
Decisions that constrain planning. For each: what was decided, why, what trade-off was accepted.

## Open Questions
Things needing answers before or during planning. Tag each with who should answer (human, architect, domain expert).

## Scope Boundaries
What's explicitly in and out of scope. Prevents scope creep during planning and implementation.

## Visual Artifacts (optional)
Diagrams, mockups, data-flow sketches. Use Mermaid for diagrams when possible.
```

## Process

1. **Research** — explore the codebase, understand the problem space.
2. **Draft** — write the design doc from research findings.
3. **Present** — show it to the human at the research gate.
4. **Approve/revise** — human approves, requests changes, or redirects.
5. **Proceed** — the approved doc feeds the plan as input. Hand off via `/agent plan`.

## Integration

- The approved design doc captures the "why" and "how"; acceptance scenarios capture the "what".
- Pair with `design-interrogation` to stress-test implicit decisions before approval.

## Output

A design document at `docs/specs/{feature-name}.md`, reviewed and approved by the human before planning begins.
