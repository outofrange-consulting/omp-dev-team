---
name: datadog
description: >-
  Query and operate Datadog from the terminal: logs, metrics, traces/APM, monitors and alerts, incidents, dashboards, SLOs, synthetics, RUM, security and audit trail, CI/CD test visibility and pipeline triage, agent/SSI install, and LLM/agent observability. Use whenever the user mentions Datadog (or DD), asks to investigate an alert/incident/error/latency/log/trace/flaky test, check service health, or manage Datadog monitors/dashboards/SLOs. This is the single entry point — it drives the Datadog `pup` CLI, which carries the per-domain skills.
---

# datadog — Datadog from the CLI via `pup`

This is the **one** Datadog skill. Rather than exposing Datadog's ~30 domain
skills individually (which would flood the skill list), everything routes through
the **[`pup` CLI](https://github.com/DataDog/pup)** — a single binary with 200+
commands across Datadog's products, plus its own embedded domain skills and
subagents. Use `pup` directly; it is the source of truth and stays current.

## Preconditions

1. `pup` must be installed — `bash plugins/datadog/install.sh` (or `brew install
   datadog-labs/pack/pup`). Check with `pup --version`.
2. You must be authenticated. Check `pup auth status`. If not:
   - `pup auth login` (OAuth, opens a browser — preferred), or
   - set `DD_API_KEY` + `DD_APP_KEY` (+ `DD_SITE`, e.g. `datadoghq.eu`).

If either is missing, tell the user how to fix it before proceeding.

## How to work

Run `pup` via the bash tool. Start broad, then narrow:

```sh
pup --help                 # top-level command groups
pup <group> --help         # e.g. pup logs --help, pup monitors --help
pup skills list            # the embedded domain skills/workflows pup ships
```

`pup` covers (non-exhaustive — discover the exact commands with `--help`):

- **logs** — search and tail logs.
- **metrics / apm** — query metrics; inspect services, traces, latency,
  performance; Single-Step Instrumentation (SSI) install & verification.
- **monitors** — create, edit, mute, and triage monitors and alerts.
- **incidents / events** — investigate and manage incidents.
- **dashboards / slo** — read and manage dashboards and SLOs.
- **synthetics / rum** — synthetic tests and Real User Monitoring / browser SDK.
- **security / audit** — Audit Trail investigations (who changed what, key
  compromise, cost spikes, compliance).
- **software delivery** — CI/CD test visibility: unblock PR pipelines, triage
  flaky tests.
- **agent observability** — LLM/agent experiments, eval pipelines, trace RCA,
  session classification.
- **docs** — search Datadog documentation.

For guided, multi-step investigations, prefer pup's embedded workflows. Reach them
**on demand through pup itself** — `pup skills list` enumerates them and
`pup skills show <name>` / `pup skills run <name>` (see `pup skills --help`) executes
one — instead of installing them as Claude Code skills. The capability lives in the
`pup` CLI; you don't need it mirrored into your context to use it.

## Why this is one umbrella skill (don't bulk-install pup's skills)

`pup skills install claude` would copy pup's ~30 per-domain skills **and** native
subagents into `~/.claude/`. Claude Code loads every skill's frontmatter
`description` into context on every request, so that bulk install is a large,
permanent context tax for capability you can already reach by calling `pup` here.

This plugin therefore ships **one** umbrella skill that drives `pup` via bash, and
the installer does **not** run `pup skills install` by default. If you genuinely want
the per-domain skills/subagents as first-class Claude Code skills (and accept the
frontmatter cost), opt in explicitly: `install.sh --with-datadog-skills` (or
`install.ps1 -WithDatadogSkills`). Likewise, avoid `/plugin marketplace add DataDog/pup`
unless you want that full skill set installed — this umbrella already covers the product.
