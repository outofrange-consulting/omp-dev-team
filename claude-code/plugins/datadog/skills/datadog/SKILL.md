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

For guided, multi-step investigations, prefer pup's embedded workflows
(`pup skills list` shows them, e.g. an SRE-style cross-signal investigation)
over hand-assembling many low-level calls.

## Deeper integration (optional)

Power users can install pup's per-domain skills as first-class Claude Code
skills by re-running the installer with `--with-skills` (which runs
`pup skills install claude`, falling back to `pup skills install` if the target
isn't recognized). It's off by default to keep the skill surface small — this
umbrella skill plus the `pup` CLI already covers the full product.
