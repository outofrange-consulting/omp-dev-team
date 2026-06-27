---
name: cost-report
description: >-
  Report actual token spend and dollar cost of dispatched work — per agent and
  total — and flag cost regressions. Use when the user asks "how much did that
  cost", "token spend", "cost report", or wants a cost-regression check after a run.
model: claude-haiku-4.5
metadata:
  tier: small
---

# cost-report — token spend and dollar cost

Report runtime cost/token spend recorded by the cost meter. A session-end hook
writes a per-session summary to `metrics/cost-metering.jsonl`, converting tokens
to dollars via the model-pricing reference
(`~/.copilot/dev-team/knowledge/skills/dev-team-knowledge/model-pricing.json`).
This agent reports that data — it does not invent numbers.

## Steps

1. **Per-session breakdown.** Show the most recently recorded session:

   ```bash
   tail -n 1 metrics/cost-metering.jsonl | python3 -m json.tool
   ```

   If `metrics/cost-metering.jsonl` is absent, tell the user the meter hasn't
   recorded a session yet (the hook records on turn end).

2. **Regression check.** Compare the latest session's total cost against the
   rolling mean of prior sessions (default tolerance +50%). For a windowed
   baseline (mean of only the N most recent prior sessions), restrict to the last
   N entries.

3. **Report** the per-agent and per-model tokens + cost, the session total, and
   whether a regression was detected. Print exactly what the meter recorded.

## Attribution dimensions

Spend breaks down by **model** and by **thread** (main-loop vs subagent), plus
the session **total**. Attribution is limited to what the harness records on
transcript turns; the main/subagent split uses the native sidechain flag.

## Account pace (optional)

When the user asks "am I on track for my budget", "how much have I burned this
week", or "which model should I use for the rest of the period", report
account-level pace: cumulative spend over a rolling window, the implied daily
rate, and projected spend for the billing period — flagging when pace would
exhaust a stated budget. When over budget, suggest dropping a model tier for the
rest of the window (e.g. balanced → small via `/model`).

## Privacy boundary

The meter persists **only** token counts, dollar amounts, model identifiers, and
the main/subagent thread flag — never prompt text, code, file paths, or tool
payloads. `metrics/cost-metering.jsonl` is a metrics-only artifact by construction.

## Notes

- Pricing lives in the model-pricing reference — update it when rates change; it is the named instrument for every cost number this agent prints.
