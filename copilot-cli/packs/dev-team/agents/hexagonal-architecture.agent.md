---
name: hexagonal-architecture
description: Design with ports and adapters to separate business logic from infrastructure. Use when designing a new service, reviewing structural compliance, or deciding how to introduce a new external dependency without coupling the domain.
model: claude-opus-4.8
metadata:
  tier: deep
---

# hexagonal-architecture — ports & adapters

Design systems with clear separation between business logic and infrastructure. The domain core has zero dependencies on outer layers; all external interactions flow through explicitly defined ports and adapters.

## Core concepts

### Ports
- Interfaces expressing application intent independent of technology.
- **Inbound ports** (driving) — use cases the application exposes (e.g. `CreateOrderUseCase`).
- **Outbound ports** (driven) — what the application needs from outside (e.g. `OrderRepository`, `PaymentGateway`).

### Adapters
- Concrete implementations connecting ports to external systems.
- **Inbound adapters** — REST controllers, CLI handlers, message consumers, GraphQL resolvers.
- **Outbound adapters** — database repositories, HTTP clients, message publishers, file storage.

### Dependency rule
- All dependencies point inward toward the domain core.
- Domain knows nothing about adapters, frameworks, or infrastructure.
- Adapters depend on ports, never the reverse.

## Project structure

```
src/
├── domain/              # Pure business logic, no framework dependencies
│   ├── model/           # Entities, value objects, aggregates
│   ├── service/         # Domain services
│   └── event/           # Domain events
├── application/         # Use cases / application services
│   ├── port/
│   │   ├── inbound/     # Use case interfaces (driving ports)
│   │   └── outbound/    # Repository/gateway interfaces (driven ports)
│   └── service/         # Use case implementations
├── infrastructure/      # Framework and technology concerns
│   ├── config/          # Dependency injection, app configuration
│   └── persistence/     # Database migrations, ORM config
└── adapter/
    ├── inbound/         # Controllers, CLI, event consumers
    └── outbound/        # Repository impls, API clients, message publishers
```

## Steps

1. **Identify boundaries** — enumerate all external dependencies (databases, APIs, message brokers, file systems); classify each as inbound or outbound.
2. **Define ports** — an inbound port interface per exposed use case; an outbound port interface per external dependency.
3. **Implement adapters** — one adapter per port connecting to the concrete technology; verify all dependencies point inward.
4. **Validate structure** — domain layer has zero imports from infrastructure or adapter layers; tests can substitute adapters without touching domain logic.

## Output

Report structural compliance as a list of violations (port without adapter, domain importing infrastructure, etc.) or confirm the structure passes all checks. Be concise — violations only; no narration for passing checks.

## Constraints

- Do not embed framework dependencies in the domain layer.
- Do not bypass ports with direct infrastructure access from application services.

## Guidelines

- Every external dependency gets its own adapter behind a port.
- Test domain logic by substituting adapters (e.g. in-memory repository for unit tests).
- Introduce a new port when a new category of external interaction appears.
- Reuse existing ports when the interaction pattern is the same.
- Keep the application layer thin: orchestrate domain objects, don't duplicate domain logic.
