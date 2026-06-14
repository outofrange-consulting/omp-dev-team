# local-llm

> 🌐 **English** · [Français](README.fr.md)

Run OMP roles on **local models sized to your hardware**. Detects VRAM/RAM, picks
the best-fit GGUF models **per role**, installs the backend (**Ollama** or
**llama.cpp**), pulls the models, and registers them as the `local-llm` provider.

Hybrid by default: deep **planning stays on cloud** (Opus); **execution and cheap
roles run locally** at zero token cost.

## Install

```sh
omp plugin install local-llm@omp-dev-team
bash plugins/local-llm/install.sh          # detect → ask → install → pull → wire
#   pwsh -File plugins/local-llm/install.ps1   # Windows
```

The installer **asks first** (and warns under 8GB VRAM), then installs the chosen
backend, pulls the role models, and appends the role wiring to
`~/.omp/agent/config.yml`. Flags: `--backend ollama|llama.cpp`, `--vram=N --ram=N`,
`--all` (pull every fitting model), `--apply-config`, `--dry-run`, `-y`.

## How it works

- **`extensions/lib/catalog.ts`** — the tier map: each model's VRAM (full / on-card
  when offloading), MoE RAM offload, quality, and eligible roles.
- **`selector.ts`** — classifies every model for your box (`oncard` /
  `moe-offload` / `dense-spill` / `no-fit`), scores quality×speed, assigns the best
  per role (`smol`/`commit` pick the cheapest fast fit).
- **`extensions/local-llm.ts`** — at session start, detects hardware and registers
  the fitting models as the `local-llm` provider (`pi.registerProvider`); `/local-llm`
  re-runs detection and prints the plan + role YAML. The same file is the CLI
  (`bun extensions/local-llm.ts --json`) that drives the installer.

## Roles — conservative by default (`--level`)

Local models take a role **only when they can do it well**. Default keeps local to
the cheap/high-volume roles; you opt into more with `--level`:

| `--level` | Local roles | Cloud roles |
|---|---|---|
| **`smol`** (default) | `smol`, `commit`, `vision` | `plan`, `default`, `task`, `slow` |
| **`balanced`** | + `task`, `slow` (if a strong model fits, no spill) | `plan`, `default` |
| **`max`** | + `default` (only if a top model fits *fully on the GPU*) | `plan` |
| **`local-only`** | everything | — |

The escalation is gated by real fit, not just the flag: on 16GB, `max` still keeps
`default` on cloud (the 30B is expert-offloaded); on 24GB+ it promotes a top model
to `default`. `plan` stays cloud except at `local-only`. Set the level with
`--level=…` or `OMP_LOCAL_LEVEL`.

## Backends

- **Ollama** (default, recommended): multi-model, auto expert-offload, OMP
  auto-discovers it on `:11434`. The installer pulls each role model.
- **llama.cpp** (advanced): one model per `llama-server` (`:8080`); the installer
  installs the binary and prints the recommended serve command for your primary
  model. Set `OMP_LOCAL_BACKEND=llama.cpp`.

## Overrides

`OMP_LOCAL_VRAM_GB`, `OMP_LOCAL_RAM_GB` (force the plan), `OMP_LOCAL_BACKEND`
(`ollama`|`llama.cpp`). Edit `catalog.ts` to add/retune models — it *is* the map.

Pairs with **copilot-preset** (cheap cloud for plan/default) and **dev-team**
(point its small tier at a `local-llm/…` model). Independent of the other plugins.
