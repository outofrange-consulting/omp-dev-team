---
name: local-llm
description: >-
  Run OMP roles on local models (Ollama / llama.cpp) sized to the machine's
  VRAM/RAM. Use when the user asks about local/offline models, GPU model setup,
  saving on cloud tokens with local inference, or the `/local-llm` command.
---

# local-llm — hardware-sized local models for OMP

Detects your **VRAM/RAM**, picks the best-fit local models **per role**, and
registers them as the `local-llm` provider. Hybrid by design: deep **planning
stays on cloud** (Opus); **execution and cheap roles run locally** at zero token
cost.

## Setup

```sh
bash plugins/local-llm/install.sh        # detect → ask → install backend → pull → wire
#   pwsh -File plugins/local-llm/install.ps1   # Windows
```

The installer: detects hardware (NVIDIA `nvidia-smi`, AMD `rocm-smi`, Apple
unified memory; RAM via the OS), **asks** before doing anything (and warns if
< 8GB VRAM), lets you pick **Ollama** (recommended, auto) or **llama.cpp**
(advanced), installs it, **pulls the role models**, and appends the role wiring
to `~/.omp/agent/config.yml`.

## Command

- `/local-llm` — re-detect hardware, (re)register the fitting models live, and
  print the plan + the `modelRoles` block to paste. No reload needed.

## How models are chosen

`extensions/lib/catalog.ts` is the tier map (each model's VRAM full/min, MoE RAM
offload, quality, eligible roles). `selector.ts` classifies every model for your
box — `oncard` / `moe-offload` / `dense-spill` / `no-fit` — scores quality×speed,
and assigns the best per role (`smol`/`commit` pick the cheapest fast fit). MoE
models (GLM-4.7-Flash, Qwen3-Coder-30B-A3B) shine on 16GB via expert offload.

## Role philosophy

| Role | Goes to |
|---|---|
| `plan`, `default` | **cloud** Opus (local can't match deep planning yet) |
| `task` | best local agentic model that fits (e.g. GLM-4.7-Flash) |
| `smol`, `commit` | smallest fast local coder (e.g. Qwen2.5-Coder-7B) |
| `slow` | highest-quality local (offload OK) |
| `vision` | local VLM (Ministral-3) |

Set `--all` to pull every fitting model, `--vram=N --ram=N` to plan for another
machine, `--backend=llama.cpp` to use llama.cpp. Override detection any time with
`OMP_LOCAL_VRAM_GB` / `OMP_LOCAL_RAM_GB`; pick the backend with `OMP_LOCAL_BACKEND`.

Pairs with **copilot-preset** (cheap cloud for plan/default) and **dev-team**
(point its small tier at a `local-llm/…` model).
