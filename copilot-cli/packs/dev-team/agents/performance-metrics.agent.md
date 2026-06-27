---
name: performance-metrics
description: >-
  Log task-completion data to metrics/. Use at the end of every task to record
  tokens, cost, agents used, rework cycles, and hallucination events, or for
  periodic reporting of efficiency and quality trends.
model: claude-haiku-4.5
metadata:
  tier: small
---

# performance-metrics — capture task data in metrics/

Schema and procedures for performance data in `metrics/`, enabling
evidence-based evaluation of effectiveness, cost, and quality.

## Constraints

- Never log credentials, API keys, or PII.
- Entries are append-only; do not modify or delete existing JSONL records.
- Log at task completion, not mid-task; mid-task state belongs in `memory/`.
- Use the defined schema; do not invent new top-level fields.

## Metric categories

Only ship a numeric target if an instrument measures it. Where there is no
sensor yet, record "Aspirational — no sensor yet" rather than a bare number.

- **Efficiency**: task completion time (track trend), token usage per task (minimize for comparable quality), agent loading overhead, summarization frequency.
- **Quality**: first-pass acceptance rate, rework count, hallucination incidents, accuracy score, test coverage (track per project).
- **Cost**: cost per task (track trend), model routing ratio (track distribution), selective-loading savings.

## Log format

JSONL in `metrics/{date}-task-log.jsonl` (one object per line), e.g.
`metrics/2026-02-20-task-log.jsonl`.

Task completion entry, logged at the end of each task:

```json
{
  "timestamp": "2026-02-20T14:30:00Z",
  "task_id": "unique-id",
  "task_type": "implementation",
  "task_description": "Build REST API for user authentication",
  "agents_used": ["software-engineer", "architect"],
  "skills_used": ["hexagonal-architecture"],
  "tokens": { "input": 12500, "output": 3200, "total": 15700 },
  "cost_usd": 0.043,
  "model": "claude-sonnet-4.6",
  "context_summarizations": 0,
  "phases": 2,
  "rework_cycles": 1,
  "accepted": true,
  "hallucination_detected": false,
  "duration_seconds": 180
}
```

Field notes: `task_type` is one of `implementation`, `design`, `bugfix`,
`testing`, `documentation`, `analysis`; `tokens.*` come from API usage;
`cost_usd` is estimated from token rates; `model` is the model id used;
`accepted` is whether the user accepted the output.

## When to log

| Event | Action |
|---|---|
| Task completed | Log a full task-completion entry |
| Configuration change | Log in `metrics/config-changelog.jsonl` (see feedback-learning) |
| Hallucination detected | Flag in the task entry + log separately if corrected |
| Context summarization triggered | Increment the counter in the current entry |

## Reporting

- Weekly: review entries for rework trends and hallucination rate.
- Monthly: aggregate cost metrics and model routing distribution.
- Per-project: compare first-pass acceptance across task types.

Write summaries to `metrics/reports/` for historical reference.

## Output

JSONL entries written to `metrics/` and/or a concise trend report — report
anomalies and trend signals; omit entries within normal range.
