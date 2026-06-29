---
name: copilot-preset
description: >-
  How this OMP workspace is wired to GitHub Copilot models. Use when the user
  asks which model is running, how to switch Copilot models, about AI-credit /
  token billing, which model is cheapest, MAI-Code-1-Flash ("MIA Coding"), or
  how to run the dev-team cheaply on their Copilot license.
---

# GitHub Copilot model preset

This workspace can run on **GitHub Copilot** models (provider `github-copilot`),
so a team uses its Copilot license instead of direct provider billing.

## Auth

OAuth: run `omp`, then `/login` → **GitHub Copilot**. Or set a token:
`COPILOT_GITHUB_TOKEN` (falls back to `GH_TOKEN`, then `GITHUB_TOKEN`).

List what YOUR plan exposes (catalog is fetched live from your Copilot account):
`omp --list-models | grep github-copilot`.

## Billing (changed 2026-06-01)

Copilot is now **usage-based**: you pay per token (input/cached/output) at each
model's rate, drawn from your plan's monthly **AI-credit** allowance
(1 credit = $0.01). Model choice per tier is a direct cost lever, and **cached
input is ~10× cheaper than fresh input** — long-lived sessions beat cold
one-shots. Full rate table + comparison: `plugins/copilot-preset/pricing.md`.

## Tier mapping (see config.snippet.yml) — "solid but cheap"

| Role | Model | Rate in/out (per 1M) |
|---|---|---|
| `smol`/`task` (dev-team small tier) | `github-copilot/mai-code-1-flash` | $0.75 / $4.50 |
| `default`/`plan` (balanced) | `github-copilot/claude-sonnet-4.6` | $3.00 / $15.00 |
| `slow` (deep) | `github-copilot/claude-opus-4.8` | $5.00 / $25.00 |

Reserve **Fable 5** ($10/$50) for long-horizon autonomous tasks only.

## MAI-Code-1-Flash ("MIA Coding")

Microsoft's cheap, coding-tuned model ($0.75/$4.50), **GA on Copilot since
2026-06-02** (Business/Enterprise + all surfaces as of 2026-06-26). It beats
Claude Haiku 4.5 on every coding bench Microsoft tested — SWE-Bench Verified
71.6 vs 66.6, SWE-Bench Pro 51.2 vs 35.2, Terminal Bench 2 54.8 vs 41.6 — with
up to 60% fewer tokens, and it's cheaper than Haiku ($1/$5). So this preset now
runs the **cheap tiers (`smol`/`task`) on `github-copilot/mai-code-1-flash`** —
a strict Pareto win over Haiku.

It is *not* set as the `default`/`plan` (orchestration) model: at 71.6 SWE-bench
it's an "everyday" model still below Sonnet for cross-file reasoning. Teams that
want maximum savings can move `default`/`plan` to it too (commented block in
`config.snippet.yml`), trading some orchestration quality for ~4× cheaper output.

## Running the dev-team on Copilot

- The dev-team **small tier** uses the `pi/smol` role → follows `modelRoles.smol`
  here automatically (highest-volume tier, biggest savings).
- The **balanced/deep** dev-team agents pin Anthropic ids in frontmatter. To run
  them on Copilot too, either set your interactive default to a `github-copilot`
  model, or change those agents' `model:` to `github-copilot/...`.
