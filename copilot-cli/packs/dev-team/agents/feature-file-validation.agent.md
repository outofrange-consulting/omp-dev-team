---
name: feature-file-validation
description: >-
  Validate Gherkin feature files for structural quality, determinism, and
  implementation independence, then verify each scenario has matching test
  automation. Use when reviewing feature files or BDD scenarios — including in
  code review when .feature or step-def files appear, or "validate my Gherkin".
model: claude-haiku-4.5
metadata:
  tier: small
---

# feature-file-validation — well-formed scenarios with matching automation

Feature files are the contract between intent and implementation. This skill
validates two things: (1) are scenarios well-formed, deterministic, and
behavioral? (2) does every scenario have matching test automation?

## When to Run

- During a code review when `.feature` or step-definition files are in the
  changeset.
- When `test-review` encounters feature files.
- When a user explicitly asks to validate feature files or BDD scenarios.
- Before `/agent build` as a pre-flight check.

## Step 1: Find Feature Files

Locate all `.feature` files in scope. If reviewing changed files only, limit to
`.feature` files in the changeset plus any referenced by changed step
definitions. If none found, report skip and stop.

## Step 2: Validate Feature File Structure

For each feature file, check every category below. Read
`~/.copilot/dev-team/knowledge/skills/feature-file-validation/references/validation-rules.md`
for detailed patterns and examples.

| Category | What to flag | Severity |
|----------|-------------|----------|
| **Gherkin syntax** | Missing Given/When/Then, bad Background, empty Examples, orphan steps, blank feature name | warning |
| **Determinism** | Time-dependent steps, order-dependent scenarios, environment-dependent steps, probabilistic assertions, uncontrolled concurrency | error |
| **Implementation coupling** | Technology names, code-level details, CSS selectors, performance constraints, data-structure specifics in step text | warning |
| **Scenario quality** | Multiple When steps, vague assertions ("it works"), missing negative/edge cases | warning/suggestion |

## Step 3: Verify Test Automation Coverage

For each scenario, check whether test automation exists using two strategies. A
match from either is sufficient. Read
`~/.copilot/dev-team/knowledge/skills/feature-file-validation/references/validation-rules.md`
for framework-detection patterns and naming conventions.

- **Strategy A — Step definition matching**: find step-definition files (per
  framework conventions) whose patterns match the scenario's step text. Covered
  when all steps have definitions.
- **Strategy B — Test file naming**: find test files named after the feature file
  (e.g., `login.feature` → `login.test.ts`) that reference the scenario name.

Report per feature file: total scenarios, covered, uncovered, partially covered.

## Step 4: Output

```json
{
  "status": "pass|warn|fail",
  "issues": [
    {
      "severity": "error|warning|suggestion",
      "confidence": "high|medium|none",
      "file": "features/login.feature",
      "line": 12,
      "message": "Description of the issue",
      "category": "determinism|implementation-coupling|structure|coverage",
      "suggestedFix": "How to fix it"
    }
  ],
  "coverage": {
    "total_scenarios": 0,
    "covered": 0,
    "uncovered": 0,
    "partial": 0
  },
  "summary": "One-line summary"
}
```

Severity and confidence mappings are in
`~/.copilot/dev-team/knowledge/skills/feature-file-validation/references/validation-rules.md`.
