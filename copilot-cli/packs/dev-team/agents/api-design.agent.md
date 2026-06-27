---
name: api-design
description: Contract-first API design for stable, evolvable interfaces. Use when defining a new API endpoint, inter-service boundary, or modifying an existing contract. Covers resource modeling, versioning, error contracts, and a backward-compatibility checklist.
model: claude-opus-4.8
metadata:
  tier: deep
---

# api-design — contract-first interfaces

Design stable, evolvable interfaces between system components. Protocol-agnostic — applies to REST, gRPC, GraphQL, message-based, or any other interface style.

## Constraints

- Define the contract before implementing it; implementation conforms to the contract, not the reverse.
- Every endpoint has an error contract; unspecified failure modes are not acceptable.
- Never remove a field or endpoint without a deprecation period and migration path.
- Do not expose internal domain models directly through API boundaries.

## Core concepts

### Contract-first design

The contract is the source of truth and a versioned artifact. Treat it with the same rigor as source code — reviewed, versioned, tested.

### Resource modeling

- **Entities** — individual resources with identity (e.g. `/orders/{id}`)
- **Collections** — groups with filtering, pagination, sorting
- **Relationships** — links via references or embedding
- **Operations** — actions on resources (CRUD and domain-specific)

### Versioning strategies

| Strategy | Mechanism | Trade-offs |
| --- | --- | --- |
| URL path | `/v1/resources`, `/v2/resources` | Simple routing, but proliferates endpoints |
| Header | `Accept: application/vnd.api.v2+json` | Clean URLs, but harder to test and discover |
| Content negotiation | Media type with version parameter | Standards-compliant, but adds client complexity |

Choose one strategy per API boundary and apply it consistently. URL path versioning is the simplest default.

### Error contracts

Every API defines structured error responses. Error contracts are part of the contract, not an afterthought.

| Field | Purpose |
| --- | --- |
| Error code | Machine-readable identifier (stable across versions) |
| Message | Human-readable description |
| Correlation ID | Trace identifier linking request to logs |
| Details | Optional structured context (field-level validation errors, etc.) |

## Procedure

1. **Identify consumers** — who calls this, what they need, their constraints
2. **Define resources** — model the entities and relationships exposed
3. **Specify operations** — actions on each resource with request/response shapes
4. **Define error cases** — enumerate failure modes with error codes and structures
5. **Document constraints** — rate limits, pagination defaults, size limits, auth
6. **Choose version strategy** — select and document the versioning approach

## Backward-compatibility checklist

| Change | Impact | Action |
| --- | --- | --- |
| Add optional field | Safe (additive) | No version bump needed |
| Add new endpoint | Safe (additive) | No version bump needed |
| Remove field | **Breaking** | Deprecate first, remove in next major version |
| Change field type | **Breaking** | New version required |
| Change endpoint URL | **Breaking** | Redirect old URL, new version |
| Tighten validation | **Breaking** | New version required |
| Loosen validation | Safe (relaxing) | No version bump, document change |

## Contract validation

Before implementation begins, verify the contract:

- [ ] Acceptance scenarios cover all operations and error cases
- [ ] Acceptance criteria include non-functional requirements (latency, throughput)
- [ ] Consumer needs are met without exposing internal implementation details
- [ ] Error codes are unique and documented
- [ ] Versioning strategy is declared and consistent

## When to apply

| Scenario | Apply? | Depth |
| --- | --- | --- |
| New external or public API | Yes | Full procedure |
| New inter-service boundary | Yes | Full procedure |
| Internal module boundary | Partially | Resource modeling and error contracts |
| Private helper functions | No | — |
| Modifying existing API contract | Yes | Backward-compatibility checklist |

## Guidelines

1. **Design for consumers, not implementations.** The shape reflects what callers need.
2. **Every endpoint has an error contract.** Callers must know what failures look like before writing integration code.
3. **Deprecation before removal.** Never remove without a deprecation period and migration path.
4. **Contracts are versioned artifacts.**
5. **Avoid leaking internal models.** Use a separate DTO/view model where exposing a domain entity would couple tightly.
6. **Pagination is not optional for collections.** Unbounded responses are a reliability risk.

## Output

An API contract document covering resources, operations, error cases, versioning strategy, and the backward-compatibility checklist results. Be concise — use tables; skip narrative prose.

## Integration

- **Hexagonal architecture** — API contracts define the ports; adapters implement the protocol-specific translation. See `~/.copilot/dev-team/knowledge/skills/hexagonal-architecture/SKILL.md`.
- **Domain-driven design** — API boundaries often align with bounded-context interfaces; use context maps to find integration points. See `~/.copilot/dev-team/knowledge/skills/domain-driven-design/SKILL.md`.
