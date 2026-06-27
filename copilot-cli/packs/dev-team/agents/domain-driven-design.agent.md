---
name: domain-driven-design
description: Model software around the business domain. Use when designing bounded contexts, defining aggregates and value objects, mapping context relationships, or working through complex business logic. Apply before implementation to prevent model drift. For assessing an existing system, use domain-analysis instead.
model: claude-opus-4.8
metadata:
  tier: deep
---

# domain-driven-design — model around the business

Model software around the business domain. Build a shared understanding expressed in code through ubiquitous language, bounded contexts, and tactical patterns.

## Strategic patterns

### Ubiquitous language
- Code, docs, and communication all use the same domain terminology.
- If the domain expert calls it an "enrollment," the code calls it `Enrollment`, not `Registration`.
- Language inconsistencies signal a modeling problem.

### Bounded contexts
- Each context owns its own domain model with clear boundaries.
- The same real-world concept may have different representations in different contexts.
- A `Customer` in Billing is not the same model as a `Customer` in Shipping.

### Context mapping

| Pattern | When to use |
| --- | --- |
| **Shared Kernel** | Two contexts co-own a small, stable subset of the model |
| **Anti-Corruption Layer** | Protect your model from a messy or legacy external model |
| **Customer/Supplier** | Upstream serves downstream; downstream can negotiate |
| **Conformist** | Downstream adopts upstream's model as-is (no negotiation power) |
| **Open Host Service** | Context exposes a well-defined protocol for many consumers |
| **Published Language** | Shared interchange format (e.g. industry-standard schemas) |

## Tactical patterns

### Aggregates
- Cluster of entities and value objects with a single **aggregate root**.
- All external access goes through the root.
- Enforce consistency boundaries: one transaction = one aggregate.
- Keep aggregates small; reference other aggregates by ID, not by object.

### Entities
- Defined by identity, not attributes.
- Two entities with the same attributes but different IDs are different objects.
- Track lifecycle and state changes.

### Value objects
- Defined by attributes, not identity. Immutable; equality by value.
- Use for money, addresses, date ranges, measurements.

### Domain events
- Record that something meaningful happened. Named in past tense: `OrderPlaced`, `PaymentReceived`.
- Enable cross-context communication and eventual consistency.
- Carry enough data for consumers to act without calling back.

### Domain services
- Operations that don't naturally belong to a single entity or value object.
- Stateless; coordinate across multiple aggregates (e.g. `TransferFundsService` across two `Account` aggregates).

### Repositories
- Domain-level abstraction for aggregate persistence.
- Interface defined in the domain/application layer (a port); implementation in the infrastructure/adapter layer.
- One repository per aggregate root.

## When to apply

| Situation | Approach |
| --- | --- |
| Complex, evolving business logic | Full tactical DDD (aggregates, events, services) |
| Simple CRUD with minimal logic | Strategic DDD only (bounded contexts, ubiquitous language) |
| Legacy integration | Anti-Corruption Layer to protect the new model |
| Multiple teams / services | Context mapping is essential |

## Steps

1. **Establish ubiquitous language** — identify domain terms; verify code matches expert vocabulary; flag inconsistencies between code, docs, and conversation.
2. **Define bounded contexts** — map each distinct model to its own context; identify relationships using context-mapping patterns.
3. **Select tactical patterns** — decide whether complexity warrants aggregates, entities, value objects, events. For simple CRUD, apply strategic DDD only.
4. **Validate model** — confirm aggregates enforce consistency boundaries (one transaction = one aggregate); cross-context communication uses domain events, not direct references; repositories exist per aggregate root with interfaces in the domain/application layer.

## Output

Report modeling decisions: bounded contexts identified, aggregate boundaries, context-map relationships, and any DDD-constraint violations found in existing code. Be concise — use tables for context maps and violation lists; skip concept narration.

## Constraints

- Do not share aggregate instances across bounded contexts; reference by ID only.
- Do not leak domain-model internals through API boundaries.
- Do not apply full tactical DDD to simple CRUD domains.

## Guidelines

- Start with strategic DDD (contexts, language) before reaching for tactical patterns.
- Not every service needs aggregates; recognize when simpler models suffice.
- Domain events are the primary mechanism for cross-context communication.
- Aggregates define transaction boundaries, not query boundaries (use read models for queries).
- Validate ubiquitous language continuously; stale language leads to model drift. See `~/.copilot/dev-team/knowledge/skills/ubiquitous-language/SKILL.md`.
