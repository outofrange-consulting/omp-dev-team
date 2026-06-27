---
description: Backend/persistence files in scope — data-access and API-boundary guardrails
globs:
  - "**/*Repository*.*"
  - "**/Migrations/**"
  - "**/*Consumer*.*"
  - "**/*Controller*.*"
  - "**/*.sql"
---

**A backend / persistence / API-boundary file is in scope.** Path-scoped: this
rule loads only when such a file is being read or edited. Stack-agnostic
guardrails — tailor the specifics to your project:

- **Validate at the boundary.** Untrusted input is checked where it enters
  (controller/consumer), not deep in the call stack. Never interpolate it into a
  query — parameterize.
- **Keep business logic out of controllers and repositories.** Controllers
  translate transport↔domain; repositories do data access only. Invariants live
  in the domain layer.
- **Migrations are append-only and reversible.** Never edit a shipped migration —
  add a new one. State the data backfill explicitly.
- **Least privilege on data.** Return only the fields the caller needs; don't leak
  internal entities across the API boundary.
