# Review Output Discipline

Shared output contract for every blocking review agent. Read it before emitting
the findings JSON. Two rules — a deterministic status, and grouped findings —
make reviews reproducible and cheap to read. Each agent's own `Status:` /
`Severity:` lines explain what each severity *means* for that agent; this file
fixes how severity maps to status and how findings are consolidated.

## Deterministic status

`status` is a pure function of the **highest-severity finding** — never of how
many findings there are. Volume never elevates the tier.

| status | condition |
|--------|-----------|
| `fail` | at least one `error` finding |
| `warn` | at least one `warning` or `suggestion` finding (no `error`) |
| `pass` | no findings |
| `skip` | nothing in this agent's scope in the changed files |

So 1 error → `fail`; 50 suggestions and 0 errors → `warn`; 0 findings → `pass`.
Two findings of the same severity never combine into a higher status.

Some findings are **capped**: an agent may declare that a class of finding
(e.g. comment hygiene, tracker-ID references) is capped at `suggestion`, so on
its own it can never raise status above `warn`. A cap lowers severity; it never
raises it.

> Note vs upstream: we keep `warning → warn` (not `warning → fail`) so the
> orchestrator's `review-rubric.md` warn tier stays meaningful and escalation
> stays calibrated to omp's gates. The determinism is the same; only the
> warning threshold differs.

## Finding grouping

Report **distinct problems at the concept level**, not one finding per
occurrence. Run three phases before emitting:

1. **Enumerate** — list every candidate in scope (identifiers, doc targets,
   refactor sites, …). Enumerate *all* of them before judging any.
2. **Classify** — apply the detection rules; assign a severity only to what is
   actually flagged.
3. **Group** — consolidate related violations into one finding. All occurrences
   of one idiom become a single finding (e.g. "non-standard abbreviations: `usr`,
   `cfg`, `tmp`" → one finding; all magic numbers → one cluster). Cite the
   representative `file`/`line` and list the rest in the `message`.

Target roughly **3–5 findings per file**. Keep `error`-severity findings
(misleading names, semantic duplication, actively wrong docs) **individual** —
each is independently actionable. Group only the lower-severity, same-kind noise.

Grouping cuts review tokens and the human's triage time without losing signal:
fewer, denser findings that each map to one fix.
