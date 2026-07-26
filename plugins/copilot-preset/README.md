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
#   or: export COPILOT_GITHUB_TOKEN=...

# 2) see what your plan exposes (fetched live from your Copilot account)
omp --list-models | grep github-copilot

# 3) paste config.snippet.yml into ~/.omp/agent/config.yml (adjust ids to match)
```

> `COPILOT_GITHUB_TOKEN` is the **only** environment variable this provider
> reads — there is **no** `GH_TOKEN` / `GITHUB_TOKEN` fallback. OMP's provider
> descriptor declares a single-element `envVars` array and the credential
> resolver builds a single-key lookup from it. (Upstream's own
> `packages/ai/README.md` still claims a fallback; that text is stale.)

## Billing changed on 2026-06-01

Copilot moved from premium-request units to **usage-based AI credits**: you pay
per token (input/cached/cache-write/output) at each model's rate (1 credit =
$0.01). Picking the right model per role is now a direct $ lever. Full rate
table, plan allowances, reachability traps and a cheapest-first comparison:
**[`pricing.md`](pricing.md)**.

## What it sets ("solid but cheap")

**All eight routed roles are set explicitly** — that is the point of this
snippet, not an accident. OMP has built-in priority chains for only
`smol`/`slow`/`designer`, so an unset `plan` silently falls through to whatever
model your *session* happens to be on, and `@task` is session-inheriting by
design. Either one quietly defeats a "cheap tier".

| Role | Tier | Model | in / out (per 1M) |
|---|---|---|---|
| `smol` | nano (lexical/scan) | `github-copilot/gpt-5-mini` | $0.25 / $2.00 |
| `task` | code (coding/tool-use) | `github-copilot/mai-code-1-flash-picker` | $0.75 / $4.50 |
| `default` / `plan` | balanced (+ archi/domain design) | `github-copilot/claude-sonnet-5` | **$2.00 / $10.00** ⏳ |
| `designer` | UI/UX + a11y | `github-copilot/gemini-3.1-pro-preview` | $2.00 / $12.00 |
| `vision` | image handling | `github-copilot/gpt-5-mini` | $0.25 / $2.00 |
| `advisor` | second opinion (off by default) | `github-copilot/gpt-5.3-codex` | $1.75 / $14.00 |
| `slow` | deep (security verdicts) | `github-copilot/claude-opus-4.8` | $5.00 / $25.00 |

`tiny` and `commit` are deliberately **left unset**: OMP already aliases `tiny`
to the `smol` chain and resolves `commit` via `["commit","smol",…]`, so setting
them would be a no-op.

⏳ **Sonnet 5's $2/$10 is promotional through 2026-08-31** and the post-promo
rate is unpublished. Re-check on 2026-09-01; `github-copilot/gpt-5.6-terra`
($2.50/$15, 1.05M ctx) is already first in the `default` fallback chain for
exactly that reason.

It also sets `modelProviderOrder: [github-copilot]` (a preference, so the
Copilot-served copy wins ambiguous role resolution), `retry.fallbackChains`
including a `"github-copilot/*": ["anthropic/*"]` provider wildcard, and
`advisor.enabled: false`.

**`enabledModels: [github-copilot/*]` ships commented out.** It is an array, so
any higher config layer replaces it wholesale; a zero-match pattern yields an
**empty** model list with *no* fallback (bricking the session rather than
degrading it); and it forecloses the non-Copilot open-weight providers OMP
already supports (cerebras/GLM, qwen-portal, moonshot, deepseek). Uncomment it
only if you deliberately want a hard team lockdown.

## MAI-Code-1-Flash ("MIA Coding")

Microsoft's cheap, coding-tuned model ($0.75/$4.50, 256K ctx, **128K max
output**), GA on Copilot since 2026-06-02. It beats Claude Haiku 4.5 on every
coding bench Microsoft published (SWE-Bench Verified 71.6 vs 66.6, SWE-Bench Pro
51.2 vs 35.2, Terminal Bench 2 54.8 vs 41.6) with up to 60% fewer tokens — and
it is cheaper than Haiku ($1/$5). The snippet runs the **`task`/code tier** on
it (post-plan implementation + structural code review), while the lower
`smol`/nano tier drops to even-cheaper `gpt-5-mini` for pure-lexical work.

> **⚠ MAI is the only vision-incapable model in the entire Copilot catalog**
> (input modalities `["text"]`). Because `task` runs on it, this preset
> **pins `modelRoles.vision`** — `inspect_image` resolves `@vision → @default →`
> active model and then hard-errors on a text-only model. Never move MAI onto
> `default` without a pinned `vision`.

**On the old "VS-Code-only / 400 `unsupported_api_for_model`" warning:** it
could not be re-confirmed. GitHub's client table now shows MAI available on
every surface **including CLI**, and the 400s were far more likely an OMP-side
bug that is fixed — `@oh-my-pi/pi-catalog` 17.0.1 (2026-07-16) routed `mai-*`
models to `/responses` instead of `/chat/completions` (issue #5612). If your
tenant still 400s, `retry.fallbackChains.task` covers it.

## Open-weight option: Kimi K2.7 Code

`github-copilot/kimi-k2.7-code` is the **first and only open-weight model on
Copilot** (Modified-MIT weights, 1T/32B MoE, 256K ctx, vision-capable), and its
**$4.00 output undercuts MAI's $4.50**. `config.snippet.yml` ships it as a
clearly-marked **commented opt-in** on `task` rather than the default, for two
reasons: its `maxTokens` is **32K vs MAI's 128K**, so a large single-shot build
slice can truncate — and `task` *is* the build tier — and it is **off by default
on Business/Enterprise** tenants until an admin enables the policy. Uncomment
the block to adopt it; it keeps MAI first in the fallback chain.

Note the broader open-weight lineup people expect is **not** on Copilot —
GPT-OSS, Qwen, DeepSeek, GLM, Llama and Mistral are all absent, and xAI/Grok was
removed in 2026-05. OMP supports several of those natively through other
providers, which is the argument against locking `enabledModels` to Copilot.

## Notes

- **Model ids vary by plan/date** — the `github-copilot` provider discovers
  models live from your account, so confirm ids with `omp --list-models | grep
  github-copilot` before editing the snippet. `pricing.md` marks which ids are
  priced-but-unroutable (`gpt-5.4-nano`, `raptor-mini`, `gemini-3-flash-preview`,
  `gemini-2.5-pro`) and which are retired but still listed (`gpt-4.1`,
  `gpt-5.2`, `gpt-5.2-codex`, `claude-sonnet-4`, `grok-code-fast-1`).
- **Two billing traps** — crossing a long-context input threshold re-prices the
  **whole** request (not just the excess), and Anthropic 1M-context is a
  **separate model id** (`claude-opus-4.7-1m` style), not a flag. See
  `pricing.md`.
- **Caching is a real lever** — cached input is ~10× cheaper ($0.20 vs $2.00 on
  Sonnet 5); stable system prompts and reused context get cached automatically.
- **dev-team interplay**: dev-team agents declare provider-agnostic role aliases
  (`@smol`, `@plan`, `@slow`, `@designer`) as comma-separated fallback lists, so
  every tier resolves through the `modelRoles` above and no agent pins a
  concrete Anthropic id. `pi/` is still accepted as the legacy prefix, but `@`
  is canonical. See `skill://copilot-preset`.
- Independent of `dev-team` and `azure-devops-fs`.
