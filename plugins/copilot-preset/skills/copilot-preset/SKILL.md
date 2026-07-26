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
`COPILOT_GITHUB_TOKEN`. (It does **not** fall back to `GH_TOKEN`/`GITHUB_TOKEN` —
OMP's Copilot descriptor declares a single-element `envVars` list. Upstream's own
`packages/ai/README.md` still claims the fallback; it is stale.)

List what YOUR plan exposes (catalog is fetched live from your Copilot account):
`omp --list-models | grep github-copilot`.

## Billing (changed 2026-06-01)

Copilot is now **usage-based**: you pay per token (input/cached/output) at each
model's rate, drawn from your plan's monthly **AI-credit** allowance
(1 credit = $0.01). Model choice per tier is a direct cost lever, and **cached
input is ~10× cheaper than fresh input** — long-lived sessions beat cold
one-shots. Full rate table + comparison: `plugins/copilot-preset/pricing.md`.

## Tier mapping (see config.snippet.yml) — "solid but cheap"

The cheap end is **split by workload shape** (dev-team's `nano` + `code` tiers):

| Role | Tier | Model | Rate in/out (per 1M) |
|---|---|---|---|
| `smol` | nano (lexical/scan) | `github-copilot/gpt-5-mini` | $0.25 / $2.00 |
| `task` | code (coding/tool-use) | `github-copilot/mai-code-1-flash-picker` | $0.75 / $4.50 |
| `default`/`plan` | balanced | `github-copilot/claude-sonnet-5` | **$2.00 / $10.00 promo through 2026-08-31**, then unpublished |
| `slow` | deep (design synthesis + security verdicts) | `github-copilot/claude-opus-4.8` | $5.00 / $25.00 |
| `designer` | UI/UX + a11y | `github-copilot/gemini-3.1-pro-preview` | $2.00 / $12.00 |
| `vision` | image input | `github-copilot/gpt-5-mini` | $0.25 / $2.00 |
| `advisor` | second-opinion turn review | `github-copilot/gpt-5.3-codex` | $1.75 / $14.00 |

`vision` is **not optional**: `inspect_image` hard-errors on a text-only model
after falling back `@vision → @default → active`, and MAI-Code-1-Flash is one of
the only text-only entries in the catalog. `advisor` deliberately picks a
different vendor from `slow` — a second opinion from the same family is worth
less. `tiny` and `commit` are left unset on purpose: OMP already aliases `tiny` to
`smol` and resolves `commit` via `["commit","smol",…]`, so setting them is a no-op.

`smol` (**nano**) drops to **gpt-5-mini** because the lexical/checklist reviewers
it runs (naming, complexity, token-efficiency, a11y, progress-guardian) need no
code semantics or tool-use — ~55% cheaper output than MAI on the highest-volume
tier. `task` (**code**) stays on coding-tuned **mai-code-1-flash-picker** for work that
edits code or drives tools. Reserve **Fable 5** ($10/$50) for long-horizon
autonomous tasks only.

## Claude Sonnet 5 (balanced + design synthesis)

`default`/`plan` run **`github-copilot/claude-sonnet-5`**, currently at a
promotional **$2.00 / $10.00 through 2026-08-31**. The post-promo rate is
unpublished; if it reverts to $3/$15, `github-copilot/gpt-5.6-terra`
($2.50/$15, 1.05M context, GitHub's "balanced default") becomes the better
`default`. Re-check this in September.

`slow` stays **`claude-opus-4.8`**, not Opus 5, despite identical $5/$25: Opus 5
is `pro=false` (it breaks Pro users) and its own changelog warns of "enhanced
safeguards for high-harm cyber content… may block some cyber-related or
security-adjacent requests" — which is exactly what this tier exists to run.

## MAI-Code-1-Flash ("MIA Coding")

Microsoft's cheap, coding-tuned model ($0.75/$4.50), **GA on Copilot since
2026-06-02** (Business/Enterprise + all surfaces as of 2026-06-26). It beats
Claude Haiku 4.5 on every coding bench Microsoft tested — SWE-Bench Verified
71.6 vs 66.6, SWE-Bench Pro 51.2 vs 35.2, Terminal Bench 2 54.8 vs 41.6 — with
up to 60% fewer tokens, and it's cheaper than Haiku ($1/$5). So this preset now
runs the **cheap tiers (`smol`/`task`) on `github-copilot/mai-code-1-flash-picker`** —
a strict Pareto win over Haiku.

**On the `unsupported_api_for_model` 400s:** these were widely reported as tenant
gating, but OMP's own `packages/catalog/CHANGELOG.md` shows **17.0.1
(2026-07-16)** fixed `mai-*` models to route through `/responses` instead of
`/chat/completions`, "which rejected them with `400 unsupported_api_for_model`".
It was an OMP-side endpoint bug, not a Copilot entitlement. On OMP ≥ 17.0.1 you
should not see it. `config.snippet.yml` keeps a `retry.fallbackChains.task` entry
anyway, which costs nothing and covers a genuine outage.

It runs the **`task`/code tier** (post-plan implementation + structural code
review). It is *not* set as the `default`/`plan` (orchestration) model: at 71.6
SWE-bench it's an "everyday" model still below Sonnet for cross-file reasoning.
Teams that want maximum savings can move `default`/`plan` to it too (commented
block in `config.snippet.yml`), trading some orchestration quality for ~4× cheaper
output.

## Running the dev-team on Copilot

- **No dev-team agent pins a vendor model id.** Every agent declares a list of
  OMP role aliases (`"@smol, @default"`, `"@plan, @default"`, …) and OMP takes the
  first resolvable one, so setting `modelRoles` here routes the *entire* team
  through Copilot — nothing to edit per agent. (Earlier versions of this file said
  the balanced/deep agents pinned Anthropic ids. That was true then; it is not now.)
- Two OMP resolution facts worth knowing: `@task` is **session-inheriting**, not a
  cheap tier, and only `smol`/`slow`/`designer` inherit from `default` — so
  `modelRoles.plan` and `modelRoles.task` must be set explicitly or they silently
  follow your session model. The shipped snippet sets both.

## Open-weight option

**`github-copilot/kimi-k2.7-code`** is the only open-weight model in the Copilot
catalog (GitHub groups it under a literal `# Open-weight models` heading in its
own release-status manifest). Cheaper on output than MAI ($4.00 vs $4.50) and
vision-capable. It ships here as a **commented opt-in**, not the default, for two
reasons: `maxTokens` is 32K against MAI's 128K, so a large single-shot
implementation slice can truncate on the *build* tier; and it is off by default on
Business/Enterprise tenants. Uncomment the block in `config.snippet.yml` to use it.
