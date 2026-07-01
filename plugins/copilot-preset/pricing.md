# GitHub Copilot pricing after the 2026-06-01 change

On **June 1, 2026** Copilot replaced premium-request units (PRUs) with
**GitHub AI Credits**: you now pay **per token** — input, cached input, and
output — at each model's published rate, drawn from your plan's monthly credit
allowance. **1 AI credit = $0.01 USD.** Token-heavy work (agentic sessions,
code review, big context) is now metered for what it actually consumes, so the
model you pick per tier is a direct cost lever.

> Monthly Pro/Pro+ plans auto-migrated to usage-based billing; **annual** Pro/Pro+
> stay on legacy PRU pricing until renewal. Plans include a monthly credit
> allowance; overage is billed at the rates below. Confirm your exact allowance
> in GitHub's billing docs (figures vary by plan and promo windows through
> Sept 2026).

## Per-model rates (per 1M tokens)

Source: GitHub Docs — *Models and pricing for GitHub Copilot*.

### Anthropic
| Model | Input | Cached in | Cache write | Output |
|---|---|---|---|---|
| Claude Haiku 4.5 | $1.00 | $0.10 | $1.25 | $5.00 |
| Claude Sonnet 4.5 | $3.00 | $0.30 | $3.75 | $15.00 |
| Claude Sonnet 4.6 | $3.00 | $0.30 | $3.75 | $15.00 |
| **Claude Sonnet 5** | **$3.00** | **$0.30** | **$3.75** | **$15.00** |
| Claude Opus 4.6 | $5.00 | $0.50 | $6.25 | $25.00 |
| Claude Opus 4.8 | $5.00 | $0.50 | $6.25 | $25.00 |
| Claude Fable 5 | $10.00 | $1.00 | $12.50 | $50.00 |

### OpenAI
| Model | Input | Cached in | Output |
|---|---|---|---|
| GPT-5 mini | $0.25 | $0.025 | $2.00 |
| GPT-5.4 mini | $0.75 | $0.075 | $4.50 |
| GPT-5.3-Codex | $1.75 | $0.175 | $14.00 |
| GPT-5.4 (default) | $2.50 | $0.25 | $15.00 |
| GPT-5.4 (long ctx) | $5.00 | $0.50 | $22.50 |
| GPT-5.5 (default) | $5.00 | $0.50 | $30.00 |
| GPT-5.5 (long ctx) | $10.00 | $1.00 | $45.00 |

### Microsoft — "MIA Coding"
| Model | Input | Cached in | Output |
|---|---|---|---|
| **MAI-Code-1-Flash** | **$0.75** | **$0.075** | **$4.50** |

MAI-Code-1-Flash is Microsoft's cheap, coding-tuned model (Build 2026), **GA on
GitHub Copilot since 2026-06-02** (Free/Pro/Pro+/Max, then CLI/cloud-agent/IDEs
from 2026-06-18, and Business/Enterprise from 2026-06-26). Microsoft's own
benchmarks put it *above* Claude Haiku 4.5 on coding — and it's **cheaper** than
Haiku ($1/$5):

| Bench (vendor-run) | MAI-Code-1-Flash | Claude Haiku 4.5 |
|---|---|---|
| SWE-Bench Verified | **71.6** | 66.6 |
| SWE-Bench Pro | **51.2** | 35.2 |
| Terminal Bench 2 | **54.8** | 41.6 |

…with up to **60% fewer tokens** (vendor results, not independent). That makes it
a strict Pareto improvement over Haiku for the high-volume cheap tiers — this
preset now routes `smol`/`task` to it. It still sits below Sonnet (71.6
SWE-bench), so it is *not* the default orchestration model.

## Cheapest-first guidance (limit token spend)

- **High-volume cheap end, split by workload shape** (dev-team's `nano` + `code`):
  - `smol` → **nano** ($0.25/$2.00 `gpt-5-mini`): pure lexical/checklist reviewers
    (naming, complexity, token-efficiency, a11y, progress-guardian) and
    input-bound scan — no code semantics or tool-use, so the cheapest model wins.
  - `task` → **code** ($0.75/$4.50 `mai-code-1-flash`): work that edits code or
    drives tools (post-plan implementation, js-fp/svelte structural review) —
    best coding quality per dollar, beats Haiku 4.5 on every bench at lower cost.
  - Don't put coding/tool-use work on `gpt-5-mini` (weaker at code) or lexical
    checklists on `mai-code-1-flash` (over-pays ~2×) — match the model to the shape.
- **Balanced everyday** (`default`/`plan`): `claude-sonnet-5` ($3/$15) — same
  price as Sonnet 4.6 but near-Opus quality on coding/agentic work and `xhigh`
  effort, so it now also carries architecture/domain design synthesis
  (architect, arch-review, domain-review, moved down from the deep tier). Or
  `mai-code-1-flash` / `gpt-5.4-mini` for an ultra-cheap profile.
- **Deep reasoning** (`slow`): `claude-opus-4.8` ($5/$25), reserved for
  high-stakes SECURITY verdicts (security-review, security-engineer) where Opus
  still leads Sonnet 5 — routing those to Sonnet 5 would save 40% in/40% out but
  bets Sonnet 5 matches Opus on the exact class of task where a wrong verdict is
  most expensive. Reserve **Fable 5** ($10/$50) for genuinely long-horizon
  autonomous tasks — it's 2× Opus.
- **Caching matters now**: cached input is ~10× cheaper than fresh input
  ($0.30 vs $3.00 on Sonnet). Stable system prompts / reused context get cached,
  so long-lived sessions are cheaper than many cold one-shots.
- **Avoid for cheap workflows**: GPT-5.5 ($30 out) and long-context variants —
  output and long-ctx multipliers are where bills spike.

Rough output-cost ranking (cheapest → priciest): GPT-5 mini ($2) <
MAI-Code-1-Flash ≈ GPT-5.4 mini ($4.50) < Haiku 4.5 ($5) < GPT-5.3-Codex ($14) <
Sonnet 4.5/4.6/5 ≈ GPT-5.4 ($15) < Opus 4.6/4.8 ($25) < GPT-5.5 ($30) < Fable 5 ($50).

## Cost impact of the cheap-tier switches

The cheap tiers are the highest-volume (parallel checklist/pattern + impl agents),
and output dominates the bill. Two switches compound here, and the cheap end is
now split by workload shape:

**`task`/code tier — Haiku 4.5 → MAI-Code-1-Flash** (coding/tool-use work).
Cheaper on two compounding levers — lower rate *and* fewer tokens — and never
more expensive than Haiku:

| | Input | Cached in | Output |
|---|---|---|---|
| Claude Haiku 4.5 (before) | $1.00 | $0.10 | $5.00 |
| MAI-Code-1-Flash (after) | $0.75 | $0.075 | $4.50 |
| Δ per token | −25% | −25% | −10% |

Worked example — 1M output tokens at this tier (1 AI credit = $0.01):

- Haiku 4.5: $5.00 → **500 credits**
- MAI at equal token volume: $4.50 → **450 credits** (−10%)
- MAI with up to 60% fewer tokens (≈0.4M): $1.80 → **180 credits** (**−64%**)

So expect **−10% to −64%** on the code tier, with *better* coding quality (Haiku
is beaten on all three benches).

**`smol`/nano tier — → GPT-5-mini** (pure lexical/checklist + scan). For work
with no code-semantics or tool-use, `gpt-5-mini` ($0.25/$2.00) is a further
~67% input / ~56% output cut vs MAI on the highest-volume tier — coding quality
is irrelevant there, so the trade-off MAI was protecting against doesn't apply.
Keep code-semantic work (js-fp, svelte, implementation) on the code tier.
