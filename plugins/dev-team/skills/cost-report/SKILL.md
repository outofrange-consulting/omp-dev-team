---
name: cost-report
description: >-
  Answer "how much did that cost" and "what is this session burning" using the
  numbers that actually exist: the /cost-report friction line from the telemetry
  extension, and Oh-My-Pi's own cost/usage surfaces. Use when the user asks for
  token spend, cost of a run, a cost regression check after /code-review or an
  orchestration run, or budget pace.
argument-hint: none
user-invocable: true
allowed-tools: read, bash(omp usage *), bash(omp stats *)
---

# Cost Report

Two things share this name. Keep them apart:

1. **`/cost-report`** — a command registered by the **`telemetry` extension**. It
   prints one friction line for the current session and appends it to
   `~/.omp/state/dev-team/<repoId>/telemetry.jsonl`:

   ```
   turns=12 ctx=n/a errors=1 | read:31 bash:14 edit:9 task:3
   ```

   Turns, per-tool call counts, and errored tool calls. **It does not know about
   tokens, models, or dollars** — the extension never sees `usage` data.

2. **Money and tokens** — those live in OMP, which meters every request itself.
   Use the native surfaces below; do not reconstruct them here.

## Steps

1. Run `/cost-report` for this session's friction line. Report it verbatim.

2. For spend, tokens, and cache economics, use the native surfaces:

   | question | surface |
   |---|---|
   | live cost, cache read/write, cache hit-rate, context fill | statusline segments `cost`, `cache_read`, `cache_write`, `cache_hit`, `context_pct`, `usage` |
   | what has this account spent, and against which limits | `/usage`, or `omp usage --json` for parseable output |
   | am I on pace / trending over a window | `omp usage --history --days 30` |
   | full breakdown, dashboard or JSON dump | `/stats`, `omp stats --summary`, `omp stats --json` |

3. **Cost-regression check.** There is no per-run regression detector in this
   plugin. Compare the current run against a prior one with
   `omp usage --history --days <n>` (or two `omp stats --json` snapshots) and say
   plainly what moved. Name the window you compared; a "regression" with no
   stated baseline is not a finding.

4. **Budget pace.** `omp usage --history --days N` gives cumulative spend over a
   window; divide by N for the daily rate and multiply by the billing period for
   the projection. If the projection exceeds a budget the user stated, say so and
   suggest dropping a *role* (e.g. move the reviewers that declare `@plan` down to
   `@smol` in `modelRoles`) rather than naming a specific model — the model behind
   each role is the user's config, not ours.

Print exactly what the tools emit. **Do not invent numbers**, and do not multiply
token counts by a price table to synthesise a cost: OMP already prices each
request from the live catalog, and a second, staler price table would only
disagree with it.

## What this skill no longer claims

- There is **no** `cost_meter.py`, no `Stop`/`SubagentStop` meter, and no
  `metrics/cost-metering.jsonl`. That whole path was a Claude-Code-era port that
  documented a script this repo has never contained (there is no `hooks/`
  directory at all), and it printed four runnable-looking command blocks for it.
- There is **no** `/cache-health` command. It belonged to token-diet's
  `cache-meter` extension, which was deleted once OMP's statusline shipped the
  same cache-hit formula natively.
- `DEV_TEAM_COST_METER` is read by nothing.
- `skill://dev-team-knowledge/model-pricing.json` still ships, but nothing in the
  runtime consumes it; treat it as reference data, not as the instrument behind
  any number you report.

## Attribution — what is actually attributable

OMP records usage per request and can split by account and provider. What a
*plugin* cannot do is attribute spend to a command, an orchestration phase, or a
fix-loop iteration: those fields were removed once it was verified the harness
never writes them (0/312 turns in a real transcript) and that a plugin has no
write path into the transcript. If the user wants per-phase cost, the honest
answer is that it is not recorded — offer the session-level numbers instead.

## Privacy boundary

`/cost-report` persists only turn counts, per-tool counts, and an error count —
never prompt text, code, file paths, or tool payloads. It is written out of tree,
so it cannot be committed by accident, and nothing is written unless the command
is run.
