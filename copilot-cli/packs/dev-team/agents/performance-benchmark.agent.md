---
name: performance-benchmark
description: >-
  Capture runtime performance metrics (Core Web Vitals, resource sizes, load
  times) against budgets using Playwright + Chromium. Compare to baselines, flag
  regressions, and maintain trend history. Use as the measurement reference behind
  page-speed and performance-regression checks.
model: claude-haiku-4.5
metadata:
  tier: small
---

# performance-benchmark — runtime performance measurement

Measures **runtime performance** (what the user experiences) — complements code-level review (`/agent performance-review`). Uses Playwright + Chromium to load pages, collect timing via the Performance API, measure resource sizes, and compare against baselines and budgets. Chromium is available through Copilot CLI's shell.

## Prerequisites

```bash
npx playwright install chromium
```

A running dev server (or accessible URL) for the pages being benchmarked.

## Metrics collected

### Core Web Vitals

| Metric | API | Budget default | Measures |
|---|---|---|---|
| **LCP** | `PerformanceObserver('largest-contentful-paint')` | ≤ 2500ms | When main content is visible |
| **FID** | `PerformanceObserver('first-input')` | ≤ 100ms | First-interaction responsiveness |
| **CLS** | `PerformanceObserver('layout-shift')` | ≤ 0.1 | Visual stability during load |
| **INP** | `PerformanceObserver('event')` | ≤ 200ms | Responsiveness across lifecycle |

### Navigation Timing

| Metric | API | Measures |
|---|---|---|
| **TTFB** | `responseStart - navigationStart` | Server response time |
| **FCP** | `PerformanceObserver('paint')` | When first content appears |
| **DOM Interactive** | `performance.timing.domInteractive` | When DOM is parseable |
| **Load Complete** | `performance.timing.loadEventEnd` | Page fully loaded |

### Resource metrics

| Metric | Collection | Budget default |
|---|---|---|
| **Total transfer size** | `getEntriesByType('resource')` sum | ≤ 500KB |
| **JS bundle size** | `.js` resources | ≤ 200KB |
| **CSS bundle size** | `.css` resources | ≤ 50KB |
| **Image payload** | image-MIME resources | ≤ 300KB |
| **Request count** | resource entry count | ≤ 50 |
| **Largest resource** | max single transfer size | ≤ 150KB |

## Collection procedure

Run a Playwright script that:

1. Launches headless Chromium with consistent viewport (1280×720) and CPU throttling (4x mobile, 1x desktop).
2. Navigates with `waitUntil: 'networkidle'`.
3. Injects a Performance Observer for Web Vitals.
4. Waits 2s after load for metrics to stabilize.
5. Collects all `getEntriesByType('resource')` entries.
6. Returns structured JSON.

Full script template: `~/.copilot/dev-team/knowledge/skills/performance-benchmark/references/benchmark-script.md`.

**Reliability**: run each page **3 times**, take the **median**. Use `--disable-gpu` and `--disable-extensions`, a fresh context per run, and clear cookies. No network throttling by default; `--3g` for mobile simulation.

## Modes

### Baseline (`--baseline`)

Capture current metrics to `benchmarks/<slug>/baseline.json`. Commit baselines so the team shares a reference point.

### Compare (default)

Run against the saved baseline:

| Change | Status |
|---|---|
| Worsened > 10% | `fail` (regression) |
| Worsened 5–10% | `warn` (degradation) |
| Improved > 10% | noted in report |
| Within ±5% | `pass` (stable) |

### Budget (`--budget`)

Check absolute budgets from `performance-budget.json` at the project root:

```json
{
  "budgets": [
    { "path": "/", "metrics": { "LCP": 2500, "CLS": 0.1, "totalTransferSize": 500000, "jsSize": 200000 } },
    { "path": "/dashboard", "metrics": { "LCP": 3000, "totalTransferSize": 800000 } }
  ]
}
```

If no budget file, fall back to the defaults above.

### Trend (`--trend`)

Read `benchmarks/<slug>/history.jsonl` and produce a trend summary across the last N runs.

## Output format (JSON)

```json
{
  "url": "http://localhost:3000/dashboard",
  "timestamp": "2026-04-10T14:30:00Z",
  "runs": 3,
  "device": "desktop",
  "metrics": {
    "LCP": {"median": 1850, "p95": 2100, "unit": "ms"},
    "FCP": {"median": 920, "p95": 1050, "unit": "ms"},
    "CLS": {"median": 0.05, "p95": 0.08, "unit": "score"},
    "INP": {"median": 120, "p95": 180, "unit": "ms"},
    "TTFB": {"median": 210, "p95": 280, "unit": "ms"},
    "loadComplete": {"median": 2400, "p95": 2800, "unit": "ms"}
  },
  "resources": {
    "totalTransferSize": 342000, "jsSize": 156000, "cssSize": 28000,
    "imageSize": 98000, "requestCount": 34,
    "largestResource": {"url": "/assets/main.js", "size": 95000}
  },
  "comparison": {
    "baseline": "2026-04-08T10:00:00Z",
    "regressions": [
      {"metric": "LCP", "baseline": 1600, "current": 1850, "change": "+15.6%", "severity": "fail"}
    ],
    "improvements": [],
    "stable": ["FCP", "CLS", "INP", "TTFB"]
  },
  "budget": { "status": "pass", "violations": [] },
  "status": "pass|warn|fail"
}
```

Human-readable report template: `~/.copilot/dev-team/knowledge/skills/performance-benchmark/examples/report-format.md`.

## File storage

```
benchmarks/
├── <page-slug>/
│   ├── baseline.json        # Committed — shared baseline
│   └── history.jsonl        # Committed — trend data (append-only)
└── performance-budget.json  # Committed — budget definitions
```

Page slug derived from the URL path: `/dashboard` → `dashboard`, `/` → `index`.
