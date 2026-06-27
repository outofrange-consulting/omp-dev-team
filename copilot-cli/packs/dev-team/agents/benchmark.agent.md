---
name: benchmark
description: >-
  Measure runtime performance of a web page with Playwright — Core Web Vitals,
  resource sizes, load times. Compare against baselines and budgets, flag
  regressions, and keep trend history. Use for "benchmark", "page speed", or
  "performance regression" checks on a running page.
model: claude-haiku-4.5
metadata:
  tier: small
---

# benchmark — measure runtime page performance

Measure only; do not modify the page or app under test. Compare against the declared budget; do not invent thresholds. Be concise — report the metrics table and verdict, no narration.

Metric definitions, collection methodology, output format, and the Playwright script template live in `~/.copilot/dev-team/knowledge/skills/performance-benchmark/SKILL.md` and `~/.copilot/dev-team/knowledge/skills/performance-benchmark/references/benchmark-script.md`. Chromium is available through Copilot CLI's shell.

## Inputs

- `<url>` (required) — full URL or a path (prefixed with the dev-server URL). If omitted, look for `performance-budget.json` and benchmark all paths listed there.
- `--baseline` — capture current metrics as the new baseline (overwrites existing).
- `--budget` — check against `performance-budget.json`.
- `--trend` — show trends from historical data.
- `--mobile` — simulate mobile (375×812 viewport, 4x CPU throttle).
- `--3g` — simulate slow 3G (400 Kbps, 400ms latency, 4x CPU).
- `--runs <n>` — measurement runs (default: 3, median reported).

## Prerequisites

1. `npx playwright --version` — if missing, run `npx playwright install chromium`.
2. If the URL is localhost, verify the dev server is running (attempt a fetch). If not, tell the user to start it.

## Steps

### 1. Generate and run the benchmark script

Generate a Node.js script from the template that:

- Navigates to the target URL.
- Collects Core Web Vitals (LCP, FCP, CLS, INP) via Performance Observer.
- Collects Navigation Timing (TTFB, DOM Interactive, Load Complete).
- Collects resource metrics (transfer sizes by type, request count, largest resource).
- Captures console errors during load.
- Runs the specified number of times (default 3), computing median and p95.

Run with `node` and capture the JSON output.

### 2. Compare against baseline (unless `--baseline`)

- `--baseline` set: save metrics to `benchmarks/<page-slug>/baseline.json` (create dir if needed), report "Baseline saved for <url>".
- Otherwise: read `benchmarks/<page-slug>/baseline.json` if present and compare per metric — regression (>10% worse) → `fail`, degradation (5–10%) → `warn`, stable (±5%) → `pass`, improvement (>10% better) → noted. If no baseline, report metrics and suggest `--baseline`.

### 3. Check budgets (if `--budget` or budget file exists)

Read `performance-budget.json` from the project root. Match the benchmarked path against budget entries; flag any metric over budget.

### 4. Append trend history

Append current metrics to `benchmarks/<page-slug>/history.jsonl` (one JSON object per line, with timestamp). With `--trend`, read the history file and summarize changes over the last 10 entries.

### 5. Report

Write a markdown report to `benchmarks/<page-slug>/report.md`. In chat, display the Core Web Vitals table with pass/warn/fail, the resource budget table, any regressions with severity, and an overall verdict.

## Integration

Complements code-level performance review (`/agent performance-review`) with runtime measurement. Baselines feed SLI/SLO definition. Can run as part of `/agent build` for performance-critical plan steps.
