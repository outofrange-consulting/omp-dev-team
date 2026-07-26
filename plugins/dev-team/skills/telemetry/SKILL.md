---
name: telemetry
description: >-
  Explain what the dev-team telemetry extension actually records, where it puts
  it, and which native Oh-My-Pi surface to use instead for cost, token and usage
  numbers. Use when the user asks to "show telemetry", "usage stats", "which
  tools am I burning turns on", "is anything being sent anywhere", or wants this
  session's friction numbers.
argument-hint: none
user-invocable: true
allowed-tools: read, bash(omp usage *), bash(omp stats *)
---

# Telemetry

The **`telemetry` extension** is a per-session *friction meter*, not a beacon.
There is no consent file, no enable/disable switch, no env var, and **no network
egress** — nothing to opt into, because nothing leaves the machine and nothing is
written until you ask for it.

## What it records

Three in-memory counters, reset on every `session_start`:

| counter | source | meaning |
|---|---|---|
| `turns` | `turn_end` | assistant turns this session |
| `toolCalls` | `tool_result`, keyed by tool name | how tool use is distributed |
| `errors` | `tool_result` where `isError` | tool calls that **errored** — not policy blocks (the field is named `errors` precisely so neither the JSONL nor the report overstates it) |

No prompt text, no paths, no code, no tool payloads, no model ids, no dollar
amounts. The meter cannot see any of those.

## Where it goes

Running `/cost-report` prints one line and appends one JSON object to
`~/.omp/state/dev-team/<repoId>/telemetry.jsonl` (`<repoId>` = sha256 of the git
root, first 16 hex; relocate with `OMP_DEVTEAM_STATE_DIR`). Out of the working
tree, so it can never be committed by accident.

**Nothing is appended unless `/cost-report` runs.** That is the whole privacy
story: recording is user-triggered, per invocation.

## Use the native surfaces for anything about money or tokens

This meter deliberately does not compute cost. OMP already does, with real
provider numbers:

| you want | use |
|---|---|
| live cost / cache hit-rate / context fill | statusline segments `cost`, `cache_read`, `cache_write`, `cache_hit`, `context_pct`, `usage` |
| spend and limits per account | `/usage`, or `omp usage --json` |
| usage-limit trend over time | `omp usage --history --days 30` |
| a stats dashboard, or a machine-readable dump | `/stats`, `omp stats --summary`, `omp stats --json` |
| per-tool-call intent, to see *why* a tool ran | `tools.intentTracing` (default `true`) |

Report exactly what those emit. Do not invent counts.

## Scope — keep this small

The meter is intentionally a **cheap local counter**: turns, tool churn, error
rate. It is not the self-improvement loop and must not grow into one. If you find
yourself adding cost math, cross-machine aggregation, or network egress here,
that work belongs in the self-improvement loop, or in OMP's own usage stack —
which already extracts a superset of these signals.

## Notes

- **Known gap:** `/cost-report`'s `ctx=` field currently reports `n/a`. The
  extension reads `percentage` off `getContextUsage()`, but OMP's `ContextUsage`
  is `{ tokens, contextWindow, percent }` — there is no `percentage` key, so the
  guard never matches. Use the statusline `context_pct` segment until the
  extension is corrected.
- Supersedes the Claude-Code-era design in which a `hooks/telemetry.sh` beacon
  wrote `metrics/telemetry.jsonl`, consent lived in a JSON file under the
  harness config directory, and a `telemetry_report.py` summarised it. None of
  those files — nor a `hooks/` directory — exist in this repo. The extension
  replaced all of them, and the `on|off|status|report` argument surface this
  skill used to describe was never implemented.
