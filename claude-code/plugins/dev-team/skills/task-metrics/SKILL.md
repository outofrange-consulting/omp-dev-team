---
name: task-metrics
description: >-
  Record and report task accounting — token/dollar spend per agent (cost), the
  opt-in usage telemetry beacon, and end-of-task completion metrics (tokens, cost,
  agents, rework, hallucinations) to metrics/. Use when the user asks "how much did
  that cost", "show telemetry", "enable/disable telemetry", or to log task metrics.
---

# Task metrics (cost · telemetry · completion logging)

All task-accounting outputs in one place. Pick the sub-capability in `references/`:
- **cost-report** — actual token spend + dollar cost per agent and total; flag regressions.
- **telemetry** — manage/report the opt-in, privacy-clean usage beacon.
- **performance-metrics** — log per-task completion data (tokens, cost, agents, rework, hallucinations) to metrics/.
