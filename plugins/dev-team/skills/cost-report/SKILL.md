---
name: cost-report
description: >-
  Report actual token spend and dollar cost of dispatched work — per agent and
  total — and flag cost regressions. Use when the user asks "how much did that
  cost", "token spend", "cost of this run", "cost report", or wants to check for
  a cost regression after /code-review or an orchestration run.
argument-hint: "[--transcript <path>] [--tolerance <n>]"
user-invocable: true
allowed-tools: >-
  bash(python3 *, jq *, tail *, cat *, ls *)
---

# Cost Report (#102)

Role: worker. Reports runtime cost/token spend captured by the cost meter.

Token cost is recoverable two ways, both converting tokens→dollars via
`skill://dev-team-knowledge/model-pricing.json`:

- **Live (current OMP).** Every assistant message carries per-turn `usage`
  (input/output/**cacheRead/cacheWrite**/`cost`/`reasoningTokens`) on the
  `turn_end`/`message_end` events, and provider rate-limit headers arrive on
  `after_provider_response`. token-diet's read-only **`cache-meter`** extension
  consumes this for **`/cache-health`** (prompt-cache read-rate, churn, cost,
  thinking-share, quota). Prefer it for live numbers.
- **Post-hoc (transcript).** A `Stop`/`SubagentStop` meter parses the session
  transcript into `metrics/cost-metering.jsonl` for the per-agent/total report
  below. **Caveat:** the `hooks/lib/cost_meter.py` this skill documents is **not
  present in this repo**, so this path is aspirational until it (or a live port
  over `turn_end.usage`) is implemented — use `/cache-health` meanwhile.

> Historical note: this skill is a Claude-Code-era port that assumed "token usage
> is not available to hooks." That is no longer true on current OMP (see the Live
> path above and `docs/upstream-omp-runtime.md`).

## Steps

1. **Per-session breakdown.** If the user passes `--transcript <path>` (or you
   know the current transcript path), run an exact per-agent report:

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/hooks/lib/cost_meter.py report --transcript <path>
   ```

   Otherwise show the most recently recorded session from the metrics log:

   ```bash
   tail -n 1 metrics/cost-metering.jsonl | python3 -m json.tool
   ```

2. **Regression check.** Compare the latest session's total cost against the
   rolling mean of prior sessions (default tolerance +50%):

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/hooks/lib/cost_meter.py regression \
     --log metrics/cost-metering.jsonl --tolerance 0.5
   ```

3. Report the per-agent, per-command, and per-fix-loop-iteration tokens + cost,
   the session total, and whether a cost regression was detected. Do not invent
   numbers — print exactly what the meter emits. If `metrics/cost-metering.jsonl`
   is absent, tell the user the meter hasn't recorded a session yet (the hook
   records on turn end).

   For a windowed cost-regression baseline (mean of only the N most recent prior
   sessions instead of all-time), pass `--window N`:

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/hooks/lib/cost_meter.py regression \
     --log metrics/cost-metering.jsonl --tolerance 0.5 --window 10
   ```

## Attribution dimensions (#102, #170)

`report` breaks spend down by **model** and by **thread** (main-loop vs
subagent), plus the session **total**.

Attribution is limited to what the Oh-My-Pi (OMP) harness actually records on
transcript turns. Per-command, per-phase, and per-fix-loop-iteration buckets
were **removed** (#170): they relied on `attributionSkill` / `orchestrationPhase`
/ `fixLoopIteration` fields the harness never writes (verified 0/312 in a real
transcript), and a plugin has no write-path into the transcript — so those
dimensions were always empty. The main/subagent split uses the native
`isSidechain` flag, which the harness does provide.

## Privacy boundary

The meter persists **only** token counts, dollar amounts, model identifiers, and
the main/subagent thread flag — never prompt text, code, file paths, or tool
payloads. `metrics/cost-metering.jsonl` is a metrics-only artifact by
construction.

1. **Account pace (optional, #142).** When the user asks "am I on track for my
   budget", "how much have I burned this week", or "which model should I use for
   the rest of the period", report account-level pace: cumulative spend over a
   rolling window, the implied daily rate, and the projected spend for a billing
   period — flagging when pace would exhaust a stated budget:

   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/hooks/lib/cost_meter.py pace \
     --log metrics/cost-metering.jsonl --budget 100 --period-days 30 --window-days 7
   ```

   Without `--budget` it reports pace only (no flag). When it flags an
   over-budget pace it suggests dropping a model tier (Opus→Sonnet) for the rest
   of the window.

## Notes

- Disable the meter with `DEV_TEAM_COST_METER=off`.
- Pricing lives in `skill://dev-team-knowledge/model-pricing.json` — update it when rates change
  (it is the named instrument for every cost number this skill prints).
