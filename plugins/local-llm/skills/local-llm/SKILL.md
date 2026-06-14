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

## Role policy — conservative by default (`--level`)

Local models are good at the cheap/high-volume roles long before they're good
enough to be your everyday driver. So local **only takes a role when it can
actually do it well** — controlled by `--level` (default `smol`):

| `--level` | What goes local | Good for |
|---|---|---|
| **`smol`** (default) | `smol`, `commit`, `vision` only — `task`/`default`/`plan` stay cloud | any ≥8GB GPU |
| **`balanced`** | + `task`, `slow` **if** a strong model fits (q≥78, no spill) | a 16GB box with a strong MoE (GLM-4.7-Flash) |
| **`max`** | + `default` **only if** a top model fits *fully on the GPU* (oncard, q≥85) | 24GB+ / big unified memory |
| **`local-only`** | everything local incl. `plan`/`default` | power users / offline |

`plan` stays on cloud except at `local-only`. The escalation is gated by real
fit: e.g. on 16GB, `max` still leaves `default` on cloud (the 30B is expert-
offloaded, not fully resident); on 24GB it promotes Qwen3.6-27B to `default`.

Flags: `--level=`, `--all` (pull every fitting model, not just the wired ones),
`--vram=N --ram=N` (plan for another machine), `--backend=llama.cpp`. Env:
`OMP_LOCAL_LEVEL`, `OMP_LOCAL_VRAM_GB`, `OMP_LOCAL_RAM_GB`, `OMP_LOCAL_BACKEND`.

Pairs with **copilot-preset** (cheap cloud for plan/default) and **dev-team**
(point its small tier at a `local-llm/…` model).
