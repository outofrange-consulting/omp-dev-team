# copilot-preset

> 🌐 **English** · [Français](README.fr.md)

A **ready model configuration** that routes [Oh-My-Pi](https://github.com/can1357/oh-my-pi)
— and, if installed, the **dev-team** plugin — through **GitHub Copilot**
(`github-copilot` provider). For teams that already pay for Copilot and want a
**solid-but-cheap** setup that limits token spend.

Standalone and config-only: it ships a skill + a config snippet + a pricing
reference. It deliberately has **no extensions** — model routing (`modelRoles`)
is a user setting, so you paste the snippet rather than have a plugin set it.

## Setup

```sh
omp plugin install copilot-preset@omp-dev-team

# 1) authenticate Copilot
omp            # then /login -> GitHub Copilot   (OAuth)
#   or: export COPILOT_GITHUB_TOKEN=...   (falls back to GH_TOKEN / GITHUB_TOKEN)

# 2) see what your plan exposes (fetched live from your Copilot account)
omp --list-models | grep github-copilot

# 3) paste config.snippet.yml into ~/.omp/agent/config.yml (adjust ids to match)
```

## Billing changed on 2026-06-01

Copilot moved from premium-request units to **usage-based AI credits**: you pay
per token (input/cached/output) at each model's rate (1 credit = $0.01). Picking
the right model per tier is now a direct $ lever. Full rate table and a
cheapest-first comparison: **[`pricing.md`](pricing.md)**.

## What it sets ("solid but cheap")

`modelRoles` mapping tiers to Copilot models, `enabledModels: [github-copilot/*]`,
`modelProviderOrder: [github-copilot]`:

| Role | Tier | Model | in / out (per 1M) |
|---|---|---|---|
| `smol` | nano (lexical/scan) | `github-copilot/gpt-5-mini` | $0.25 / $2.00 |
| `task` | code (coding/tool-use) | `github-copilot/mai-code-1-flash` | $0.75 / $4.50 |
| `default` / `plan` | balanced (+ archi/domain design) | `github-copilot/claude-sonnet-5` | $3.00 / $15.00 |
| `slow` | deep (security verdicts) | `github-copilot/claude-opus-4.8` | $5.00 / $25.00 |

## MAI-Code-1-Flash ("MIA Coding")

Microsoft's cheap, coding-tuned model ($0.75 / $4.50), **GA on Copilot since
2026-06-02** (Business/Enterprise + all surfaces by 2026-06-26). It beats Claude
Haiku 4.5 on every coding bench Microsoft tested (SWE-Bench Verified 71.6 vs 66.6,
SWE-Bench Pro 51.2 vs 35.2, Terminal Bench 2 54.8 vs 41.6) with up to 60% fewer
tokens — and it's cheaper than Haiku ($1/$5). The snippet runs the **`task`/code
tier on `github-copilot/mai-code-1-flash`** (post-plan implementation + structural
code review), while the lower `smol`/nano tier drops to even-cheaper `gpt-5-mini`
for pure-lexical work. It's left below Sonnet for `default`/`plan` orchestration;
a commented block lets you move that to it too for an ultra-cheap profile.

## Notes

- **Model ids vary by plan/date** — the `github-copilot` provider discovers models
  live from your account, so confirm ids with `omp --list-models | grep
  github-copilot` and edit the snippet (current Anthropic set: Haiku 4.5,
  Sonnet 4.5/4.6, Opus 4.6/4.8, Fable 5).
- **Caching is a real lever now** — cached input is ~10× cheaper; stable system
  prompts / reused context get cached automatically.
- **dev-team interplay**: the nano (`pi/smol`) and code (`pi/task`) tiers follow
  this automatically; agents that pin Anthropic ids need an interactive Copilot
  default or a `model:` edit. See `skill://copilot-preset`.
- Independent of `dev-team` and `azure-devops-fs`.
