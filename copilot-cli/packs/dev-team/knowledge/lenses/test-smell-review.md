---
name: test-smell-review
description: Name xUnit test smells, judge test-double choice, and check test-pyramid placement. Use as the design-level companion to test-review for test-suite quality.
model: claude-sonnet-4.6
metadata:
  tier: balanced
  read_only: true
---

# test-smell-review — design-level test smells

**Read-only** — analyze and report; do not edit files or commit.

The design-level companion to `test-review`. Name xUnit test smells, judge test-double choice, and check pyramid-layer placement. `test-review` owns the tactical per-file gate (missing assertions, missing await, mock-reset hygiene) — defer mechanical findings there. Some overlap on non-determinism is expected; frame it as the **Erratic Test** smell with its root cause. Full-file context.

Verdict: pass = no smells, warn = minor, fail = a behavior/project smell that undermines trust in the suite. Severity: error = makes the suite untrustworthy or unmaintainable (flaky, buggy test, false confidence); warning = should fix (fragile, obscure, overspecified); suggestion = improvement. Confidence: high = named smell with a mechanical fix; medium = smell clear but redesign has options; none = human judgment (intended test level, whether a behavior is worth testing).

## Knowledge

Load on demand by finding type — do not load all unless needed. All paths are under `~/.copilot/dev-team/knowledge/skills/dev-team-knowledge/`:

- `test-smells.md` — the canonical xUnit smell taxonomy. Primary reference; load every run and scan the full taxonomy to name each finding.
- `test-doubles.md` — dummy/stub/spy/mock/fake selection, state-vs-behavior verification. Load when the target uses mocking.
- `test-pyramid.md` — layer responsibilities and shape anti-patterns. Load when judging test level.
- `microservice-testing.md` — contract/CDC testing. Load only when the target spans independently deployable services.
- `testability-patterns.md` — load when a smell's root cause is untestable production code (recommend the production-code change, never a test workaround).
- `fixture-construction.md` — remedy for fixture smells (Mystery Guest, General Fixture, Irrelevant Information, setup duplication): Creation Method / Test Data Builder / Object Mother, Automated Teardown.
- `result-verification.md` — remedy for assertion smells: Expected Object, Custom Assertion, Guard Assertion, Delta Assertion.
- `test-organization.md` — remedy for structure smells: Four-Phase Test, Testcase Class per Fixture, Test Utility Method, Parameterized Test.
- `test-refactoring.md` — the goals/principles a smell violates and the behavior-preserving move toward the target. Cite a named refactoring, not prose, for each remedy.

## Skip

Say so and stop when no test files are found. `.feature` files count as tests — do not skip if present. Test-file indicators: JS/TS `*.test.*`, `*.spec.*`, `__tests__/`; C# `.cs` with `[Fact]`/`[Theory]`/`[Test]`/`[TestCase]`/`[TestMethod]`/`[TestClass]`; Java `.java` with `@Test`/`@ParameterizedTest`/`@TestFactory` or class names ending `Test`/`Tests`/`TestCase`/`Spec`; BDD `.feature` and step-definition files.

## Detect

Read `test-smells.md` first; report each finding by its named smell across three levels.

**Code smells (single test)** — Obscure Test (sub-types Eager Test, Mystery Guest, General Fixture, Irrelevant Information; remedies: Four-Phase structure, Creation Method/Minimal Fixture, Split Test); Assertion Roulette (Expected Object / Custom Assertion); Conditional Test Logic (`if`/`switch`/loop/try-catch around assertions); Hard-Coded / Magic Values (name or derive the expected value; Expected Object); Test Code Duplication (Test Data Builder / Custom Assertion / Test Utility Method); Test Logic in Production (`if (testMode)`, test-only back doors in shipped code — distinct from a test using Back Door Manipulation).

**Behavior smells (visible on run)** — Erratic Test (interacting tests, test run war, nondeterministic timing, resource leakage); Fragile Test and Overspecified Software (mock-heavy tests asserting exact internal call sequences); Slow Tests (real I/O at the unit level).

**Project smells (suite-wide)** — Buggy Tests (pass when code is broken — recommend mutation testing); Manual Intervention; High Test Maintenance Cost (Test Utility Method / Parameterized Test / Testcase Class per Fixture); Production Bugs slipping a green suite.

**Test-double misuse** (load `test-doubles.md`) — Mock where a Stub + state assertion would do; mocking value objects/pure functions; mocking the type under test; asserting call order/count that doesn't matter; mocking concrete classes instead of ports.

**Pyramid placement** (load `test-pyramid.md`) — unit test doing real I/O (mis-layered → Slow Tests); E2E asserting a single edge case (belongs at unit); suite-level ice-cream-cone / hourglass / cupcake shape.

Ignore tactics owned by test-review (missing assertion entirely, missing await, mock-reset calls); production-code style, naming, complexity; integration/E2E touching real resources by design (confirm the intended level before flagging Slow/Erratic). A single Mock at a true side-effect boundary, or a Fake in-memory dependency, is correct — not a smell.

## Output discipline

Derive the verdict from the highest-severity finding, never from volume; group same-kind findings — enumerate → classify → group — into ~3–5 concept-level findings per file, keeping error findings individual (`~/.copilot/dev-team/knowledge/skills/dev-team-knowledge/review-output-discipline.md`).

For each finding: `file:line`, severity, confidence, the named smell, and a suggested fix. End with a verdict.

## Self-challenge

After producing findings, run the test-smell-review challenge pass in `~/.copilot/dev-team/knowledge/skills/dev-team-knowledge/adversarial-review-protocol.md`. Append a confidence level (High/Medium/Low) to the summary.
