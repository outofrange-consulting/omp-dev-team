# Database Test Patterns

A DB test must leave the world exactly as it found it and never collide with a
concurrent run. Most DB-test pain is **state leakage** (Interacting Tests) and
**concurrency** (Test Run Wars). Adapted from *xUnit Test Patterns* (Meszaros).
Complements `database-change-management.md` (evolving the schema) and
`cd-test-architecture.md` (where these run).

## Does this test need a real DB at all?

| Under test | Use |
|---|---|
| Business logic that happens to read/write data | A **Fake** (in-memory repository) — the DB is incidental |
| Mapping, queries, ORM config, schema, constraints | The **real DB is the SUT** — apply isolation + teardown |
| Stored procedures / DB-side logic | A real engine, isolated per run (but prefer moving logic out) |

Spinning up a full database to test domain logic is the **Slow Tests**
anti-pattern. Push business rules into the domain and Fake the repository.

## Isolation (no Test Run Wars)

- **Database Sandbox** — each test run gets its own data space (baseline).
- **Dedicated Sandbox** (per user/runner) — flexible; or **Schema per Test
  Runner** — cheaper, one engine. Sandboxing isolates *runs*; **within-run**
  independence still needs a Fresh Fixture + teardown per test.

## Teardown (leave no trace)

| Technique | When | Note |
|---|---|---|
| **Transaction Rollback** | SUT does not commit | Fastest; needs a Humble Transaction Controller so the test owns the tx |
| **Table Truncation** | commits happen | Delete in FK-safe order |
| **Delete-by-key / scoped** | targeted cleanup | For shared reference data |

Prefer rollback; fall back to truncation when the SUT commits.

## CD pipeline placement

Real-DB tests run roughly an **order of magnitude (~50×) slower** than Fakes.
Put Fakes in the **pre-merge gate**; run a narrow real-DB band later in the
pipeline. Manual seeding/reset is a **Manual Intervention** smell — automate it
or the stage can't gate.

## Connections

- Evolving the schema safely → `database-change-management.md`.
- Test value sourcing for fixtures → `value-patterns.md`, `fixture-construction.md`.
- Pipeline stages → `deployment-pipeline.md`, `cd-test-architecture.md`.
