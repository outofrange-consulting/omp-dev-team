---
name: design-it-twice
description: Generate multiple radically different interface designs for a module, then compare and synthesize. Based on Ousterhout's "Design It Twice". Use when exploring interface options, designing an API, comparing module shapes, or when the user says "design it twice", "what are my options", or "show me alternatives".
model: claude-opus-4.8
metadata:
  tier: deep
---

# design-it-twice — explore divergent interface shapes

Your first design idea is rarely your best. Generate multiple radically different interface designs for a module, then compare them so the user can make an informed choice. Based on "Design It Twice" from John Ousterhout's *A Philosophy of Software Design*.

This is about **interface shape**, not implementation. Don't write code — design the contract.

## When to use

- Designing a new module, service, or API boundary.
- Refactoring an existing interface that feels wrong.
- Any time there's a non-obvious choice about how to expose functionality.
- When a new module boundary is identified during planning.

## Process

### 1. Gather requirements

Before designing, understand the constraints:

- What problem does this module solve?
- Who are the callers? (other modules, external users, tests)
- What are the key operations?
- What should be hidden inside vs exposed?
- Any hard constraints? (performance, compatibility, existing patterns)

Explore the codebase for existing patterns and conventions. Ask the user only for what you can't determine from the code.

### 2. Generate designs (sequential hand-off)

Produce 3+ **radically different** approaches — not variations on a theme. Delegate each via `/agent <name>` (one agent at a time — sequential hand-off, aggregate the results). Assign each a different design constraint:

| Design | Constraint | Optimizes for |
|--------|-----------|---------------|
| 1 | "Minimize the interface — aim for 1-3 methods max" | Simplicity, deep module |
| 2 | "Maximize flexibility — support many use cases and extension" | Generality, future-proofing |
| 3 | "Optimize for the most common caller — make the default case trivial" | Ergonomics, productivity |
| 4 | (optional) "Design around ports & adapters for cross-boundary deps" | Testability, isolation |

Each produces:

1. **Interface signature** — types, methods, parameters
2. **Usage example** — how a real caller would use it
3. **What it hides** — complexity kept internal
4. **Trade-offs** — what you gain and what you give up

### 3. Present designs

Show each design sequentially so the user can absorb one before the next. Use prose, not comparison tables, for the designs themselves — prose conveys trade-offs better.

### 4. Compare

After presenting all designs, compare on:

- **Interface simplicity** — fewer methods and simpler params = easier to use correctly
- **Depth** — small interface hiding significant complexity (good) vs large interface with thin implementation (bad)
- **Ease of correct use** vs **ease of misuse**
- **Implementation efficiency** — does the shape allow efficient internals?
- **Testability** — can callers test against this interface without mocking internals?

Give your own recommendation — which design is strongest and why. If elements from different designs combine well, propose a hybrid. Be opinionated.

### 5. Synthesize

Ask the user:

- "Which design best fits your primary use case?"
- "Any elements from other designs worth incorporating?"

The final design often combines insights from multiple options.

## Anti-patterns

- Don't let the designs converge — enforce radical difference via constraints.
- Don't skip the comparison step — the value is in the contrast.
- Don't implement — this is purely about interface shape.
- Don't evaluate based on implementation effort — that's a separate concern.
