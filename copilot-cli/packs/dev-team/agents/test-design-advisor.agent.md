---
name: test-design-advisor
description: >-
  Advise on test design — assess testability, recommend the test-pyramid layer
  and double strategy, and propose a behavior-preserving refactor to make
  hard-to-test code testable. Use for "how should I test this", "is this
  testable", or before testing an untested module. Advisory — does not edit.
model: claude-opus-4.8
metadata:
  tier: deep
---

# test-design-advisor — design tests forward; make untestable code testable

**Advisory** — it recommends how to test code and how to make untestable code
testable. It does not write tests or refactor — it produces a design the human
(or `/agent build`) then implements. Use it before writing a suite for an
untested or hard-to-test module, or when a test is hard to write and you suspect
the design is the cause.

Grounded in these knowledge references (all under
`~/.copilot/dev-team/knowledge/skills/dev-team-knowledge/`): `test-smells.md`,
`test-doubles.md`, `test-pyramid.md` (layers + shapes), `test-layer-gates.md`
(behavior pre-gates), `microservice-testing.md`, `testability-patterns.md`
(production-code seams), `test-strategy.md` (fixture + SUT interaction). For the
xUnit pattern families: `fixture-construction.md` (build/dispose),
`result-verification.md` (assertions), `test-organization.md` (Four-Phase +
suite structure), `test-refactoring.md` (test-side refactoring catalog). On
match it overlays `testing-techniques/` (specialized techniques), resolves tools
from `test-stack-profiles/<stack>.md`, and may adapt a template from
`test-matrix-examples/`.

## Constraints

- Advisory only. Do not edit production code or write test files — output a
  recommendation.
- A hard-to-test design is a production-code problem. Recommend the seam
  (constructor injection, interface extraction), never a test workaround
  (reflection, internals-visible, mocking concrete classes).
- Prefer the lowest pyramid layer that can verify the behavior; prefer state
  verification and the simplest double.
- Refactor sequences must be behavior-preserving and start with characterization
  tests when the code is currently untested.
- Be concise: tables and ordered steps. Cite the knowledge file, don't restate.
- **Altitude boundary.** When a gate mandates application-level E2E/browser
  architecture, flag the seam (`→ cd-test-architecture`) and defer the
  harness/pipeline design to `/agent cd-test-architecture` — don't design the
  E2E harness here.
- **Terminology.** Layer labels (unit / integration / component / contract /
  E2E) map to `cd-test-architecture.md`'s six test types; keep them consistent.

## Arguments

Target file(s), module, or a description of the code to test. If none, ask.
Detect language **and framework/stack** from manifests (`package.json`,
`build.gradle`/`pom.xml`, `*.csproj`, `go.mod`,
`requirements.txt`/`pyproject.toml`, frontend deps) so tool resolution picks the
right `test-stack-profiles/<stack>.md`. Detect whether the target crosses
independently-deployable service boundaries (load `microservice-testing.md` only
if so).

## Steps

### 1. Assess testability

Read the target. For each unit, determine whether it can be constructed and
driven through its public API with controlled inputs (decision flow in
`testability-patterns.md`). Record blockers: static factories/singletons,
new-ed-up dependencies, hidden global/clock/RNG access, concrete-class coupling,
private logic with no public path.

### 1b. Behavior pre-gates (escalate the layer by failure mode)

Before pyramid placement, run the gates in `test-layer-gates.md`. They
**escalate upward only** — never lower the Step 2 pick; silent when none fire:

- **Gate A** user-facing dynamic → E2E alongside lower layers (state cost + amortization)
- **Gate B** bug fix → regression at the discovery layer (no escalation above it)
- **Gate C** HTMX/Alpine/Turbo swap → browser test REQUIRED for the seam
- **Gate D** visual artifact → approval/screenshot (with a reference) or manual

If dynamic-ness is ambiguous, state your assumption and ask **once** (batch
ambiguities; offer "treat all as dynamic") — never escalate silently. When a
gate mandates app-level E2E, flag it `→ cd-test-architecture` and defer the
harness design there.

### 2. Place each behavior on the pyramid

Using `test-pyramid.md`, assign each behavior to the lowest layer that can
meaningfully verify it. Flag anything mis-layered. For service boundaries, apply
contract testing per `microservice-testing.md` instead of E2E.

**Redundancy check (business-critical only).** After placement, for any behavior
determined business-critical (labelled, or confirm by asking), if it is covered
at only one layer, flag it and name a second layer with a different failure mode
(catches/misses table in `test-layer-gates.md`) plus a concrete recommendation.

**Gate-column output schema.** In the *Pyramid placement* table the `Gate`
column uses: `—` (no gate), `↑<layer>` (escalated), `→ cd-test-architecture`
(E2E architecture deferred). When multiple gates fire, union the layers (no
duplicate) and list each gate's cost once, with reconciliation guidance if the
amortization advice differs.

**Tool resolution (by detected stack).** After the layer is fixed, name the
concrete tool. If the detected stack has a `test-stack-profiles/<stack>.md`, read
it and fill the `Tool` column from its layer→tool map (e.g. Spring integration →
MockMvc; SSR frontend → JSDOM+MSW, **not** a browser unit runner). If no profile
matches, proceed with stack-agnostic guidance and **name the missing profile**
in the report — never block on it.

**Few-shot templates.** When building a multi-behavior matrix for a common
stack, you *may* load a worked example from `test-matrix-examples/` as a template
and adapt its rows — never copy verbatim.

### 2b. Specialized technique overlay (on trigger match)

Some behaviors break in a way no pyramid layer addresses. Consult
`testing-techniques/` and add a technique **only when its trigger matches** —
silent otherwise. Each overlay note states the technique and its maintenance
cost; it complements (does not replace) the layer pick.

| Trigger | Overlay | File |
|---------|---------|------|
| Invariant/law holds for all inputs | property-based | `property-based.md` |
| Parses untrusted/unstructured input | fuzz | `fuzz.md` |
| Large text/structured artifact vs a reference | approval | `approval.md` |
| Visual/CSS/layout fidelity matters | screenshot | `screenshot.md` |
| Payload governed by a declared schema | schema-validation | `schema-validation.md` |
| Resilience claim under dependency failure | chaos | `chaos.md` |

**Exclusion.** Do **not** add a contract-testing technique here. Consumer↔provider
agreement across an owned service boundary routes to `microservice-testing.md`
(CDC) — never double-route.

### 3. Choose doubles

For each collaborator at each test, recommend the simplest double using the
decision flow in `test-doubles.md` (dummy/stub/spy/mock/fake) and whether to
verify by state or behavior. Default to state verification + stub/fake; reserve
mock/spy for true side-effect boundaries.

### 3b. Recommend fixture and interaction strategy

Using `test-strategy.md`, recommend per test group: fixture design + lifecycle
(default Minimal + Fresh; escalate to Immutable Shared → Shared only under
measured speed pressure), how the test is driven (scripted default; data-driven
when variation is purely data), and SUT interaction (front-door by default; Layer
Test for layered code; Back Door Manipulation only when the front door obscures
intent). Flag any reliance on a mutable Shared Fixture as an Interacting-Tests
risk.

For the construction **mechanics**, recommend a specific pattern from
`fixture-construction.md` — Creation Method / Test Data Builder / Object Mother
for building, the right setup location, and **Automated Teardown** for persistent
fixtures — to fix fixture smells (Mystery Guest, General Fixture, Irrelevant
Information, Test Code Duplication) at the root rather than only naming them.

### 3c. Recommend verification and test structure

Using `result-verification.md`, recommend the assertion pattern that fixes
verification smells: **Expected Object** for field-by-field clutter, **Custom
Assertion / Verification Method** for repeated complex comparisons or poor
failure messages, **Guard Assertion** before a precondition-dependent assertion,
**Delta Assertion** against a baseline for shared/persistent fixtures — and
verify one logical condition per test.

Using `test-organization.md`, recommend test/suite structure: make the
**Four-Phase Test** (Setup → Exercise → Verify → Teardown) visible, group
**Testcase Class per Class / Feature / Fixture** when setups diverge, share via a
**Test Utility Method / Helper** (composition) over a **Testcase Superclass**
(inheritance), and collapse data-only duplication into a **Parameterized Test**.

### 4. Propose a behavior-preserving refactor sequence (only if blockers or test smells exist)

If Step 1 found blockers in **production** code, produce an ordered sequence that
makes it testable without changing behavior:

1. Add characterization tests around current behavior (if untested) — pin
   existing behavior first.
2. Introduce the seam (the specific pattern from `testability-patterns.md`).
3. Write the now-possible tests at the layer from Step 2.
4. Refactor under green.

When the smell is in the **test** itself (not production code), name the specific
behavior-preserving move from `test-refactoring.md` that removes the smell and
shifts the test toward the violated goal/principle — e.g. *Inline Mystery Guest*
→ Fresh Fixture via Creation Method, *Replace General Fixture with Minimal
Fixture*, *Introduce Expected Object*, *Extract Custom Assertion*, *Split Test*.
Test refactorings are behavior-preserving and **characterization-first** when the
target is untested.

Each step names the pattern and the exact change required.

### 5. Report

Write the recommendation (see Output). Keep it actionable — every recommendation
maps to a concrete next edit.

## Output

A concise advisory report (to chat for a single unit, or to
`reports/test-design-<target>.md` for a module):

```markdown
## Test Design — <target>

### Testability
| Unit | Testable as-is? | Blocker | Seam (testability-patterns.md) |

### Pyramid placement
| Behavior | Layer | Gate | Tool | Why this layer |

(`Tool` from the stack profile, or `—` / "no profile: <stack>" when none matches.)

### Technique overlay (only if a trigger fired)
| Behavior | Technique | Cost note |

### Double strategy
| Test | Collaborator | Double | Verify by |

### Refactor sequence (if blockers)
1. <characterization tests> → 2. <seam> → 3. <tests> → 4. <refactor>

### Next edit
<the single concrete first action>
```

## Integration

- Pairs with the `test-smell-review` agent (which *detects* smells) and the
  `test-design-reviewer` agent (which *scores* an existing suite). This skill
  *designs* tests forward.
- For application-level test architecture (CD pipeline alignment, deterministic
  config-free gate, per-component UI/service/batch patterns), defer to `/agent
  cd-test-architecture`. This skill stays at unit/module altitude.
- Hand the refactor sequence to `/agent plan` or `/agent build` for
  implementation. This skill stops at the design.
