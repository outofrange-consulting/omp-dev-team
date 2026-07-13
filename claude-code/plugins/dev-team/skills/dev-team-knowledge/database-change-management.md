# Database Change Management

Schema and data evolve through the pipeline like code — versioned, scripted,
reversible. Adapted from *Continuous Delivery* (Humble & Farley) and the
expand/contract (parallel-change) pattern. Used by domain/arch/security reviewers
and the platform-engineer when a change touches persistence.

## Everything is a versioned migration

- Schema version tracked in the database (a migration table); a tool owns it
  (Flyway, Liquibase, dbmate, Alembic, EF, Prisma Migrate).
- Every change is a script **in version control**. No manual SQL anywhere,
  including prod.
- Migrations provision from an empty database up to current — repeatably.
- Each forward migration has a **paired, tested rollback** (apply-then-revert in
  CI).

## Expand / contract (parallel-change)

Make schema changes in phases so the DB always works for the **currently
deployed** app version *and* the next one:

1. **Expand** — add the new structures; keep the old; backfill data.
2. **Migrate** — app writes **both**, reads the **new**.
3. **Contract** — drop the old **only** once no running version depends on it
   (a later release).

Example — rename `qty` → `quantity`: add `quantity` + backfill (expand) → write
both, read `quantity` (migrate) → drop `qty` next release (contract).

## Keep changes reversible without data loss

| Change | Safe approach |
|---|---|
| Drop column/table | Archive first; never drop in the same release it's deprecated |
| Narrow a type / add `NOT NULL` | Add nullable → backfill → enforce in a later release |
| Add a constraint | Validate existing rows first (`NOT VALID` then `VALIDATE`) |
| Destructive data fix | Snapshot affected rows; replay on rollback |

## Decouple DB change from app change

The schema must satisfy current **and** next app version simultaneously — so a
deploy and its rollback both work. Evolve incrementally; rehearse in a
production-like environment.

## Review checks (flag these)

- A column/table dropped or renamed in the **same release** it's still
  referenced.
- A migration with **no** rollback.
- `NOT NULL` / new constraint without a backfill step.
- App + schema change assumed to deploy **atomically** (breaks rolling/canary).
- Manual SQL in a runbook instead of a migration.

## Connections

- Rollback/release context → `release-strategies.md`, `deployment-pipeline.md`.
- Testing the data layer → `database-test-patterns.md` (if present),
  `microservice-testing.md`.
