# Test Review — Division of Labor

`test-review` and `test-smell-review` run over the same test files and can detect
several of the same signals under different names. This file is the single source
of truth for **how the two agents divide the work**, so the rule lives in one
place instead of being restated in both agent bodies and again in `/skill:test-design`.

Two agents each restating their own boundary is two things to keep in sync and
two chances to drift; it also costs the same tokens twice on every review that
runs both.

## The two roles

- **`test-review`** owns the **tactical per-file gate**: an assertion is missing
  entirely, an `await` is missing, a mock is not reset, a coverage path (edge /
  error / happy) is untested, or production code is untestable (static factory,
  singleton, no injectable constructor → recommend the seam, never a test
  workaround).
- **`test-smell-review`** owns the **named design smell** and its remedy: it names
  the xUnit smell, judges test-double choice, and checks pyramid-layer placement,
  citing the remedy pattern (`fixture-construction.md`, `result-verification.md`,
  `test-organization.md`, `test-refactoring.md`).

## Shared signals — who reports when both run

Several signals are detectable by both agents. **When both run** (e.g. under
`/skill:test-design`, which dispatches them in one batch), the owner below reports it
and the other agent stays silent on it; the design-level framing wins. When an
agent runs **solo** — `test-smell-review` under `/code-review`, or either via
`/review-agent <name>` — it reports the signal itself.

| Shared signal | Reported by (when both run) | Framing |
|---|---|---|
| Non-determinism (clock / RNG / sleep / real-I/O timing) | **test-smell-review** | the **Erratic Test** smell, with root cause |
| Weak / no-message assertions | **test-smell-review** | **Assertion Roulette** → `result-verification.md` |
| Copy-pasted arrange/assert blocks | **test-smell-review** | **Test Code Duplication** → builder / custom assertion |
| Magic literals in assertions | **test-smell-review** | **Hard-Coded / Magic Values** → `value-patterns.md` |
| Mocking concrete classes; wrong double choice | **test-smell-review** | test-double misuse → `test-doubles.md` |
| Unit test doing real I/O; wrong pyramid layer | **test-smell-review** | **Slow Tests** / pyramid placement |
| Missing assertion entirely; missing `await`; mock-reset hygiene | **test-review** | tactical mechanical gate |
| Testability blocker (static factory, singleton, no injectable ctor) | **test-review** | flag the blocker; recommend the production-code seam |

## The rule in one line

When both agents run, `test-smell-review` defers the pure mechanics (missing
assertion, missing `await`, mock-reset) to `test-review`, and `test-review` defers
the named-smell signals above to `test-smell-review`. `/skill:test-design` step 4 drops
any duplicate that slips through, keeping the design-level framing.

## test-smell-review ↔ test-design-advisor — remedy division

`test-smell-review` (an agent) and `test-design-advisor` (a skill) both draw
remedy guidance from the same knowledge set (`fixture-construction.md`,
`result-verification.md`, `test-organization.md`, `test-refactoring.md`). Rather
than de-duplicate remedy prose at report time, the two components divide the row
**structurally**. `test-smell-review` names the **smell + its remedy family** (the
knowledge-file cite); `test-design-advisor` names the **specific remedy pattern**
and its refactor sequence. `/skill:test-design` joins the two on `remedyFamily` — no
prose matching, no silent drops.

| Column | Owner | Content |
|---|---|---|
| Smell name + location | test-smell-review | e.g. "Assertion Roulette at foo_test.js:42" |
| Severity + confidence | test-smell-review | `error` / `warning` / `suggestion`; `high` / `medium` / `none` |
| Remedy family (knowledge file) | test-smell-review | one of `fixture-construction`, `result-verification`, `test-organization`, `test-refactoring`, or `null` when no family applies |
| Specific remedy pattern | test-design-advisor | e.g. "Expected Object", "Custom Assertion", "Creation Method", "Delta Assertion" |
| Refactor sequence (behavior-preserving) | test-design-advisor | ordered steps from `test-refactoring.md` |
| Forward-design placement (pyramid, doubles) | test-design-advisor | table row from `test-pyramid.md` / `test-doubles.md` |

**Invocation rule.** When both components run together under `/skill:test-design`, the
advisor owns the remedy-pattern columns and `test-smell-review` cites the family
only — the advisor's per-behavior recommendation is the specific fix. When
`test-smell-review` runs **solo** (e.g. under `/code-review`, where the advisor is
not dispatched), it fills the whole row: `suggestedFix` still names a specific
pattern from the family, not just the family slug, so no downstream consumer —
`/skill:apply-fixes` in particular — is blocked on the advisor.

**Emit the family slug in the message too.** `remedyFamily` is a structural
field, and nothing downstream reads it structurally today: `/skill:apply-fixes` reads
`instruction` / `suggestedFix` prose, and `/skill:test-design`'s report table is
assembled from the merged findings. So `test-smell-review` also writes the family
slug verbatim into the finding's `message`. That keeps the cite visible to a
prose consumer without any consumer having to learn a new field — and it is what
makes the join above auditable by reading the report.

## Connections

- The two agents → `agents/test-review.md`, `agents/test-smell-review.md`.
- The command that runs both → the `test-design` skill (dispatch in step 2,
  de-duplication in step 4).
- The smell catalog itself → `test-smells.md`; the remedies →
  `fixture-construction.md`, `result-verification.md`, `test-organization.md`,
  `test-refactoring.md`, `value-patterns.md`, `test-doubles.md`.
- Status/grouping rules both agents share → `review-output-discipline.md`.
