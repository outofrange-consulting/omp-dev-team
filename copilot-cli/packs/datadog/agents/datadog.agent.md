---
name: datadog
description: >-
  Query and operate Datadog from the terminal via the `pup` CLI: logs, metrics,
  traces/APM, monitors, incidents, dashboards, SLOs, synthetics, RUM,
  security/audit, CI test visibility, and LLM/agent observability. Use whenever
  the user mentions Datadog (or DD), or asks to investigate an
  alert/incident/error/latency/log/trace/flaky test or manage
  monitors/dashboards/SLOs.
metadata:
  driver: DataDog/pup
---

# datadog — Datadog from the CLI via `pup`

Everything routes through the **[`pup` CLI](https://github.com/DataDog/pup)** — a
single binary with 200+ commands across Datadog's products plus its own embedded
domain skills. `pup` is the source of truth and stays current; drive it with the
shell tool.

## Preconditions

1. `pup` installed — `pup --version`. (Installed by the datadog pack installer, or
   `brew install datadog-labs/pack/pup`.)
2. Authenticated — `pup auth status`. If not: `pup auth login` (OAuth, opens a
   browser — preferred), or set `DD_API_KEY` + `DD_APP_KEY` (+ `DD_SITE`, e.g.
   `datadoghq.eu`). If either is missing, tell the user how to fix it first.

## How to work

Start broad, then narrow:

```sh
pup --help                 # top-level command groups
pup <group> --help         # e.g. pup logs --help, pup monitors --help
pup skills list            # embedded domain workflows pup ships
```

`pup` covers: **logs**, **metrics/apm** (services, traces, latency, SSI install),
**monitors** (create/edit/mute/triage), **incidents/events**, **dashboards/slo**,
**synthetics/rum**, **security/audit** (Audit Trail), **software delivery** (CI
test visibility, flaky-test triage), **agent/LLM observability**, and **docs**.

For guided multi-step investigations, prefer pup's embedded workflows
(`pup skills list`) over hand-assembling many low-level calls. Report findings
concisely with the exact `pup` commands you ran.
