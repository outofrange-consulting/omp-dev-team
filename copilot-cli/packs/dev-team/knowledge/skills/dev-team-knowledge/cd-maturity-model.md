# CD Maturity Model

A self-assessment grid for continuous-delivery capability, and a disciplined way
to improve it one step at a time. Adapted from *Continuous Delivery* (Humble &
Farley, ch. 15). Use it when assessing a team/repo's delivery health or planning
a platform improvement.

## Six practice areas

1. **Build management & CI** — how code is built and integrated.
2. **Environments & deployment** — how environments are provisioned and code is shipped.
3. **Release management & compliance** — how releases are governed and audited.
4. **Testing** — the automated test strategy across the pipeline.
5. **Data management** — schema/data evolution and test data.
6. **Configuration management** — version control of everything, incl. config.

## Five levels (per area)

| Level | Name | Signature |
|---|---|---|
| **−1** | Regressive | Ad hoc, manual, unrepeatable; tribal knowledge |
| **0** | Repeatable | Documented, partly automated, version-controlled |
| **1** | Consistent | Automated across the lifecycle, used universally |
| **2** | Quantitatively managed | Metrics gathered; risk understood and bounded |
| **3** | Optimizing | Continuous improvement; cycle-time/stability trends acted on |

Score each area independently — a team is usually uneven (e.g. Testing at 1,
Data management at −1). The lowest areas dominate real cycle time.

## How to improve (Deming / PDCA)

1. **Map the value stream**; find the slowest or most painful area.
2. Define **measurable** acceptance criteria for raising that area one level.
3. Implement the **smallest** change that achieves it.
4. **Measure**, retrospect, then roll out incrementally.
5. Repeat on the next constraint.

Target outcomes: shorter **cycle time** (commit→releasable), higher **deployment
frequency**, lower **change-failure rate**, faster **MTTR**.

## Guiding principles

- Automation over documentation; embed compliance **in the pipeline**.
- Release as frequently as the business can absorb (smaller = safer).
- Cross-functional teams over siloed hand-offs.

## Connections

- The pipeline being scored → `deployment-pipeline.md`.
- Test maturity detail → `test-automation-maturity.md`.
- Architecture health → `architecture-assessment.md`.
