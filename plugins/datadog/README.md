# datadog

Datadog observability from the terminal for Oh-My-Pi, via the Datadog
**[`pup` CLI](https://github.com/DataDog/pup)** — a single binary with 200+
commands across Datadog's products (logs, metrics, traces/APM, monitors,
incidents, dashboards, SLOs, synthetics, RUM, security/audit, CI test
visibility, LLM/agent observability).

## One skill, on purpose

`pup` ships ~30 domain skills/subagents. Surfacing each as its own OMP skill
would flood the skill list, so this plugin ships **one** broad `datadog` skill
that drives the `pup` CLI. The CLI carries the per-domain skills internally
(`pup skills list`), and the agent discovers exact commands with `pup --help`.

## Install

```sh
bash plugins/datadog/install.sh
#   pwsh -File plugins/datadog/install.ps1     # Windows
```

What it does:

1. Installs the **pup CLI** — Homebrew (`datadog-labs/pack/pup`) when available,
   otherwise the prebuilt release binary into `~/.local/bin` (no sudo).
2. Sets up **authentication**: `pup auth login` (OAuth, browser) when
   interactive, or persists `DD_API_KEY`/`DD_APP_KEY`/`DD_SITE` to
   `~/.omp/secrets.env` (chmod 600).
3. Leaves the broad `datadog` skill to route everything through pup.

Flags: `--with-skills` (also run `pup skills install pi` to add pup's domain
skills as first-class OMP skills — off by default), `--no-config` (skip auth),
`-y` (non-interactive).

## Use

Once authenticated, just ask in natural language ("investigate the latency
alert on checkout-service", "show error logs for payments in the last hour",
"triage the flaky tests blocking my PR"). The `datadog` skill drives `pup`
accordingly. Manually:

```sh
pup auth status
pup --help
pup logs --help
pup skills list
```

## Auth notes

- OAuth (`pup auth login`) is preferred; it requires Dynamic Client Registration
  enabled on your Datadog site.
- Fallback: `export DD_API_KEY=… DD_APP_KEY=… DD_SITE=datadoghq.com` (use your
  region, e.g. `datadoghq.eu`, `us5.datadoghq.com`).
