---
name: dev-team-knowledge
description: Reference corpus for the dev-team agents and skills — registries, review rubrics/templates, OWASP detection map, design/test taxonomies, ADR criteria, and the model-routing config. Read individual files with skill://dev-team-knowledge/<file>; this is consulted by team/review agents, not invoked directly.
---

# Dev-Team Knowledge Corpus

Reference material the persona/review agents and workflow skills cite. Every
file is reachable from any working directory as `dev-team-knowledge/<file>`,
so it works whether this is the active workspace or installed as a plugin.

## How to use

Resolve a section anchor through the index, then read just that file:

1. `use the /dev-team-knowledge skill/index.json` — section summaries keyed by document; find the right anchor.
2. `use the /dev-team-knowledge skill/<file>.md` — load the document (use `:offset-limit` selectors for a single section of a large file).

## Map

- **Registries / process**: `agent-registry.md`, `review-rubric.md`, `review-template.md`, `adr-decision-criteria.md`, `adversarial-review-protocol.md`, `accepted-risks-schema.md`.
- **Architecture / design**: `architecture-assessment.md`, `domain-modeling.md`, `design-smells.md`, `object-calisthenics.md`.
- **Security**: `owasp-detection.md`, `security-review-rule-map.yaml`, `security-primitives-contract.md`, `rule-fixtures/`.
- **Testing**: `test-strategy.md`, `test-pyramid.md`, `test-doubles.md`, `test-smells.md`, `testability-patterns.md`, `test-layer-gates.md`, `test-organization.md`, `result-verification.md`, `fixture-construction.md`, `test-refactoring.md`, `cd-test-architecture.md`, `component-test-patterns.md`, `microservice-testing.md`, `testing-quadrants.md`, `test-automation-maturity.md`, `exploratory-testing-field-guide.md`, `testing-techniques/`, `test-stack-profiles/`, `test-matrix-examples/`.
- **Routing / cost**: `model-routing.json` (tier→backend source of truth; also read by the `model-routing` extension), `model-pricing.json`.
- **Schemas**: `schemas/` (recon envelope, unified finding, disposition register).

Bare `dev-team-knowledge/X.md` references in agent prompts are valid only when followed by a one-sentence "Whole-file load:" rationale; otherwise resolve the anchor via `index.json` first and read with `:offset-limit`.
