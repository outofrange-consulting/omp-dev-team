---
name: domain-analysis
description: Strategic DDD health assessment of an existing system. Use when asked to analyze an architecture, assess domain health, find coupling problems, map bounded contexts, trace event flows, or understand what is slowing delivery — "what's wrong with our architecture", "where is the coupling", "event storming", "friction report". For greenfield modeling use domain-driven-design instead.
model: claude-opus-4.8
metadata:
  tier: deep
---

# domain-analysis — strategic DDD health assessment

Assess the domain health of an existing multi-component system. Produce a structured report covering bounded-context boundaries, context-map relationships, domain-event flows, value-stream throughput, and a friction report identifying where the architecture inhibits continuous delivery.

This skill is analytical, not prescriptive — it describes what *is*, not what should be built. For greenfield design use `~/.copilot/dev-team/knowledge/skills/domain-driven-design/SKILL.md`. For code-level violations (anemic model, missing DTOs, wrong layer), use the `/agent arch-review` flow.

## Scope

Determine scope from the request first:

- **Single repo** — analyze folder structure, package boundaries, shared models.
- **Multi-repo / microservices** — analyze service boundaries, shared libraries, event contracts, API dependencies.

## Evidence requirement

Every finding must be grounded in something you actually read. When reporting a God Object, a missing ACL, a coupling trap, or a friction item, cite the specific `file:line` or `file` where the evidence was observed. Do not assert a pattern from naming conventions alone — open the file and confirm.

Classify each finding by confidence:

- **observed** — directly visible in a file you read (an import, a shared type, a method call)
- **inferred** — visible at folder/module level without reading implementation (directory name, package dependency)
- **suspected** — requires runtime knowledge or cannot be confirmed statically

## Analysis framework

### 1. Bounded-context identification

Structure reveals intent without reading implementation. Look at folder names, module names, and package boundaries first, then confirm with data schemas.

- Derive contexts from top-level folders, packages, or service names.
- Flag **God Objects** — types appearing in multiple components under diverging meanings (e.g. `User` in Auth, Orders, Billing with different fields). A God Object is only a problem if its semantics diverge; the same name with the same meaning is fine.
- Identify whether each context owns its model exclusively or borrows from neighbors.

### 2. Context mapping

Classify each inter-context relationship by integration pattern — the pattern determines who can change what without coordinating.

| Pattern | Signal in code |
| --- | --- |
| **Anti-Corruption Layer** | Translator/mapper class at the boundary; explicit model conversion |
| **Shared Kernel** | Shared library/package co-owned by two contexts |
| **Customer/Supplier** | Downstream negotiates with upstream via contracts or versioned APIs |
| **Conformist** | Downstream uses upstream's model with no translation |
| **Open Host Service** | Published protocol (REST, gRPC, event schema) consumed by many |

Flag missing ACLs — direct dependencies passing domain objects across boundaries without translation. Highest-risk coupling: a schema change in one context silently breaks another.

### 3. Behavioral event storm

Domain events are the seams that let contexts evolve independently. Missing events are missing seams.

- Identify domain events: past-tense names (`OrderPlaced`, `InventoryReserved`) crossing component boundaries.
- Trace each: which component emits it, which consume it, sync or async.
- Flag events that are missing (cross-boundary state changes with no event) or implicit (direct method calls that should be events).

### 4. Value-stream flow

Trace a single unit of value through the system. Begin from a specific entrypoint you can point to (a CLI command, HTTP handler, message consumer) — name it. Trace the actual flow, not a hypothetical one.

- Identify the happy path: ordered sequence of component handoffs from entrypoint to outcome.
- Flag synchronous handoffs where async would decouple (latency and availability risk).
- Flag high-coupling handoffs: caller must know too much about the downstream internals.
- Identify missing compensating actions for mid-stream failure (e.g. payment charged but order not created).

### 5. Coupling-trap detection

- **Circular dependencies** — A depends on B, B depends on A (directly or transitively).
- **Coupling traps** — a change to one model forces breaking changes in others; signals missing abstraction or misplaced boundary.
- **Shared mutable state** — two contexts writing the same tables/caches without clear ownership.

## Steps

1. Map bounded contexts from directory structure and naming.
2. Identify God Objects spanning contexts — open files to confirm semantic divergence.
3. Chart context relationships using the integration-pattern table.
4. Locate missing ACLs by reading import statements across boundaries.
5. Run the event storm: events, emitters, consumers.
6. Identify the value-stream entrypoint in code; trace the happy path step by step.
7. Identify coupling traps and circular dependencies.
8. Write the friction report.

## Output

### Bounded contexts
Table: context name, owning file/package, primary aggregate or concern, upstream/downstream relationships.

### God Objects
List each: type name, contexts it appears in, diverging semantics, evidence (`file:line`). Omit types with consistent meaning everywhere.

### Context map
Table of relationships and integration patterns. Flag missing ACLs with ⚠ and cite the import/call that crosses the boundary without translation.

### Domain event inventory
Table: event name, emitting context, consuming contexts, sync/async. If no domain events exist, say so explicitly.

### Value stream
State the entrypoint (file and function/command). List the ordered handoffs with coupling severity (low/medium/high) and confidence tier.

### Friction report
Each item: category tag, files/components involved, confidence tier, concrete fix direction. Format:

```
[category] file-a → file-b (confidence: observed)
Description of the coupling or gap.
Fix: <specific action, e.g. "introduce ACL", "extract context", "replace sync call with domain event">
```

Categories: `deployment-coupling` | `data-coupling` | `semantic-coupling` | `event-gap`

Example:

```
[semantic-coupling] output.ts → enricher.ts (confidence: observed, output.ts:3)
output.ts imports classifyDDD() from enricher.ts — business logic that runs at render time
belongs in the enrichment phase. This creates a reverse dependency: Output depends on
Enrichment internals.
Fix: run classifyDDD during enrichment and store results on contextMap.dddInsights;
output.ts reads the pre-computed field.
```

## Constraints

- Do not redesign. Describe what exists; note what is missing.
- Do not flag code-level violations — those belong to the architecture-review flow.
- Scope coupling-trap findings to cross-context boundaries; intra-context coupling is out of scope.
- **Do not reframe infrastructure as a domain.** CI/CD stages, Terraform modules, deploy scripts, and Makefiles are not bounded contexts or aggregates. If no application logic exists, the skip applies regardless of labels.

## Guidelines

- Start with folder/package structure before reading any code — structure reveals intended boundaries.
- Friction-report items must cite the specific file (and line if possible).
- If the system has no domain model (pure infrastructure, scripts, configs, build tools), return a brief two-to-three-sentence note explaining that and skip the full report. Do not invent an "operational domain" or "infrastructure domain" in its place.
