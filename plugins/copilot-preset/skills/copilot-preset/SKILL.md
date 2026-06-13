---
name: copilot-preset
description: >-
  How this OMP workspace is wired to GitHub Copilot models. Use when the user
  asks which model is running, how to switch Copilot models, about premium
  requests, or how to run the dev-team on their Copilot license.
---

# GitHub Copilot model preset

This workspace can run on **GitHub Copilot** models (provider `github-copilot`),
so a team uses its Copilot license instead of direct provider billing.

## Auth

OAuth: run `omp`, then `/login` → **GitHub Copilot**. Or set a token:
`COPILOT_GITHUB_TOKEN` (falls back to `GH_TOKEN`, then `GITHUB_TOKEN`).

List what your plan exposes: `omp --list-models | grep github-copilot`.

## Tier mapping (see config.snippet.yml)

| Role | Model | Notes |
|---|---|---|
| `smol` (dev-team small tier) | `github-copilot/gpt-5.4-mini` | cheap/fast; `grok-code-fast-1` is cheapest |
| `default` / `task` (balanced) | `github-copilot/claude-sonnet-4.5` | everyday work |
| `slow` (deep reasoning) | `github-copilot/claude-opus-4.6` | premium-heavy; or `gpt-5.5` |

## Premium requests

Copilot bills many models in **premium requests** (a multiplier per call).
`*-mini` and `grok-code-fast-1` are cheap/free-tier; Opus/GPT-5.5 are expensive.
For high-volume fan-out (the dev-team review agents), keep `smol` on a cheap
model. The `github-copilot` provider sends the correct premium-request headers
automatically.

## Running the dev-team on Copilot

- The dev-team **small tier** uses the `pi/smol` role → follows `modelRoles.smol`
  here automatically (this is the high-volume tier, so the win is biggest).
- The **balanced/deep** dev-team agents pin Anthropic ids in frontmatter. To run
  them on Copilot too, either set your interactive default to a `github-copilot`
  model, or change those agents' `model:` to `github-copilot/...`.
