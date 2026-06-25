# Extraction from upstream agentic-dev-team (v7.7–v7.9)

Survey of `bdfinst/agentic-dev-team` releases since our v7.6 extraction, and what
we pulled into our OMP port — filtered through omp-dev-team's choices:
**test-after with refactoring (no TDD), quality first, cost efficiency.**

## Upstream evolution since v7.6

| Release | Highlight |
|---|---|
| v7.7.0 | harness fixes from session-review/audit; **closed learning loop**; **when-tdd-pays** experiment fixtures; ambiguity-resolution protocol for `/specs` + `/ship` gate |
| v7.8.0 | **craftsmanship-axis review rules** — use-the-platform, comment hygiene; named shipped AC references |
| v7.9.0 | **deterministic status + finding grouping** for doc/naming review agents |

## Extracted (respecting omp choices)

1. **Deterministic status + finding grouping (v7.9).** New shared knowledge file
   `skills/dev-team-knowledge/review-output-discipline.md`:
   - **Deterministic status** — an agent's `status` is a pure function of the
     highest-severity finding, never of volume.
   - **Finding grouping** — Enumerate → Classify → Group; consolidate same-kind
     findings into ~3–5 concept-level findings per file; keep `error` findings
     individual.

   Wired as a one-line anchored reference into **all 17** finding-emitting review
   agents (upstream changed only doc/naming — we factored it into one shared file
   instead of copy-pasting; this is the DRY, cost-efficient win and propagates
   determinism + token savings to every review). Added to `index.json`.

2. **Comment hygiene (v7.8) → `doc-review`.** Tracker-ID references in shipped
   comments (`JIRA-123`, `#456`), detached/orphaned doc comments; **capped at
   `suggestion`** (never raise status above `warn`); durable external standards
   (`RFC-2119`, `ISO-4217`, CVE) are explicitly not flagged.

3. **Use-the-platform (v7.8) → `refactor-opportunity-review`.** Reinvented
   built-ins (`min`/`max`/`sum`/`clamp`/`copy`), reinvented helpers, open-coded
   idioms repeated 3+ times — mapped by concept, honoring language **and version**
   (e.g. Go <1.21 has no builtin `min`/`max`). Framing de-TDD'd to test-after.

4. **Closed learning loop (v7.7) → `feedback-learning` skill.** We already had
   post-task reflection + recurring-correction detection (3+); the missing
   "closed" half was a persistent queue + disposition. Added a
   `metrics/pending-review.jsonl` queue (system proposals enqueued, never
   dropped) and a **session-review** disposition flow (`review` keyword) that
   previews, then approves (apply + log + stamp `approved`) or rejects (stamp
   `rejected`). Project-local only — plugin-cache-safe. Asynchronous/batched by
   design, which keeps it cheap.

## Test-after reinforcement (omp north star)

Beyond extraction, a pass to make **test-after with refactoring** explicit and to
remove residual TDD framing the earlier plan-gate-over-tdd move had left behind:

- **Refactor after green, every step** — promoted from "optional" to a deliberate
  always-taken pass (the `refactor-opportunity-review` lens) in `skills/build`,
  `prompts/implementer.md`, and the orchestrator's Phase 3. Changes are made only
  when there's a real opportunity, but the pass is always taken — the *refactoring*
  half of test-after-with-refactoring.
- **Residual TDD traces reframed** to test-after: `triage` skill + command (RED/GREEN
  fix plan → regression-test + fix + refactor), `qa-engineer` (ATDD → acceptance
  scenarios; unit tests follow, test-after), `plan` (TDD step/traceability →
  build step / step-to-scenario), `progress-guardian` (flagged "tests not written
  first" → flags missing tests, order-agnostic), `mutation-testing` /
  `quality-gate-pipeline` / `init-dev-team` (RED-GREEN labels dropped, semantics
  kept), `test-design-reviewer` ("First/written-first" rubric → "Timely/ships with
  the implementation"), plus the root `README`/`README.fr` ("strict TDD" → forced
  plan gate, test-after) and `REVIEW.md` (stale `tdd-guard` → `spec-guard`).

## Deliberately NOT extracted (with rationale)

- **when-tdd-pays experiment fixtures (v7.7).** Upstream is re-litigating where
  test-first pays. omp-dev-team has already made the call (test-after + plan gate);
  importing TDD experiment fixtures would reintroduce exactly what we removed.
- **`/ship` gate + ambiguity-resolution protocol (v7.7).** The ambiguity protocol
  is reasonable, but it is wired to a `/ship` command we don't have; our `/specs`
  already runs a consistency gate. Candidate for a focused follow-up if a gap shows.
- **Bibliographic TDD citations kept as-is.** e.g. `testability-patterns.md` cites
  *Growing Object-Oriented Software, Guided by Tests* ("outside-in TDD") — that is
  the book's actual subject; rewriting a citation would misrepresent the source.

## Verified

`ci-validate-json` 23/23 · all 10 dev-team extensions compile · unit suite green ·
both `review-output-discipline` anchors (`#deterministic-status`,
`#finding-grouping`) resolve from all 17 wired agents · no prescriptive TDD /
test-first / RED-GREEN traces remain outside historical `docs/` and the one book
citation.
