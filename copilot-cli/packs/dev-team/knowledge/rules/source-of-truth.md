---
description: Source-of-truth hierarchy — verify claims against code/data/telemetry, never fabricate
globs:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.py"
  - "**/*.go"
  - "**/*.rs"
  - "**/*.java"
  - "**/*.kt"
  - "**/*.cs"
  - "**/*.sql"
  - "**/*.md"
---

# Source of truth — verify, don't fabricate

When sources conflict, the **higher rung wins**. Ground every factual claim in
the highest rung you can reach:

1. **Code** — the source actually in the repo.
2. **Database / SQL data** — real rows, schema, migrations.
3. **Telemetry** — logs, metrics, traces, test output you ran.
4. **Documentation** — READMEs, comments, design docs (may be stale).
5. **AI/model output** — the lowest rung; never self-authoritative.

Rules:

- **Make no claim you cannot cite to rungs 1–3.** For anything else, say
  *"unverified"* or *"I don't know"* — never invent an answer to fill the gap.
- **Show the evidence.** Paste the command output, the query result, the test
  run — don't assert success from memory or expectation.
- **Don't trust docs over code.** If a README and the code disagree, the code
  wins; flag the stale doc.
- **Don't trust your own prior output.** Re-derive from rungs 1–3 rather than
  citing something you said earlier.

This is the verification half of `output-discipline` ("every quantitative claim
names the instrument that measures it").
