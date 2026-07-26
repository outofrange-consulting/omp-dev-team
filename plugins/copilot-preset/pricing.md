# GitHub Copilot pricing after the 2026-06-01 change

*Catalog re-verified 2026-07-26 against GitHub's own data tables and against
OMP's bundled catalog (`packages/catalog/src/models.json`, 38 `github-copilot`
ids at OMP 17.1.4).*

On **June 1, 2026** Copilot replaced premium-request units (PRUs) with
**GitHub AI Credits**: you now pay **per token** — input, cached input, cache
write, and output — at each model's published rate, drawn from your plan's
monthly credit allowance. **1 AI credit = $0.01 USD.** Token-heavy work
(agentic sessions, code review, big context) is metered for what it actually
consumes, so the model you pick per role is a direct cost lever.

## Allowances (confirmed, no longer "check your plan")

| Plan | Price | Base credits | Flex allotment | Total / mo |
|---|---|---|---|---|
| Pro | $10 | 1,000 | 500 | **1,500** |
| Pro+ | $39 | 3,900 | 3,100 | **7,000** |
| Max | $100 | 10,000 | 10,000 | **20,000** |
| Business | $19/user | 1,900/user | — | **1,900/user, pooled** |
| Enterprise | $39/user | 3,900/user | — | **3,900/user, pooled** |

- **Base** is fixed and matches the subscription price; the **flex allotment** is
  variable — GitHub adjusts it as model economics change. Do not budget on flex.
- **Promo through 2026-09-01:** Business gets 3,000 and Enterprise 7,000 per
  user (from 2026-06-01).
- Credits **do not carry over**; they reset at 00:00:00 UTC on the 1st.
- Code completions and Next Edit Suggestions are **not** billed in credits and
  stay unlimited on paid plans.
- **Legacy path still live:** Pro/Pro+ subscribers on an existing **annual** plan
  remain on request-based (premium request) billing — 300 req/mo Pro, 1,500
  Pro+, $0.04 per extra request, with per-model multipliers. Monthly plans
  auto-migrated to usage-based.
- **Auto model selection earns a 10% discount** on model costs on any paid plan.
  OMP pins explicit ids, so this preset **forfeits that 10%** by design — the
  savings from routing cheap roles to cheap models are far larger.

## Per-model rates (per 1M tokens)

Source: GitHub Docs — *Models and pricing for GitHub Copilot*
(`data/tables/copilot/models-and-pricing.yml`), cross-checked against OMP's
bundled catalog. Rows marked ⛔ exist but must **not** be routed to; see
[Reachability traps](#reachability-traps).

### Anthropic
| Model | Input | Cached in | Cache write | Output |
|---|---|---|---|---|
| Claude Haiku 4.5 | $1.00 | $0.10 | $1.25 | $5.00 |
| **Claude Sonnet 5** | **$2.00** | **$0.20** | **$2.50** | **$10.00** ⏳ |
| Claude Sonnet 4.5 | $3.00 | $0.30 | $3.75 | $15.00 |
| Claude Sonnet 4.6 | $3.00 | $0.30 | $3.75 | $15.00 |
| Claude Sonnet 4 ⛔ | $3.00 | $0.30 | $3.75 | $15.00 |
| Claude Opus 4.5 | $5.00 | $0.50 | $6.25 | $25.00 |
| Claude Opus 4.6 | $5.00 | $0.50 | $6.25 | $25.00 |
| Claude Opus 4.7 | $5.00 | $0.50 | $6.25 | $25.00 |
| **Claude Opus 4.8** | **$5.00** | **$0.50** | **$6.25** | **$25.00** |
| Claude Opus 5 ⚠ | $5.00 | $0.50 | $6.25 | $25.00 |
| Claude Fable 5 | $10.00 | $1.00 | $12.50 | $50.00 |

⏳ **Sonnet 5's $2/$10 is PROMOTIONAL "through August 31, 2026"** (GitHub docs
footnote `[^sonnet-5-promo]`). The post-promo rate is **not published**. Assume
reversion to the $3/$15 Sonnet line and **re-check on 2026-09-01**. If it does
revert, `github-copilot/gpt-5.6-terra` ($2.50/$15, 1.05M ctx, GitHub's own
"balanced default") becomes the better `default` — it is already first in this
preset's `retry.fallbackChains.default`.

⚠ **Claude Opus 5** (GA 2026-07-24) is the same $5/$25 as Opus 4.8 but this
preset deliberately does **not** route `slow` to it: it is `pro=false` (breaks
Copilot Pro seats), and its launch changelog warns of *"enhanced safeguards for
high-harm cyber content"* that *"may block some cyber-related or
security-adjacent requests"* — which is exactly the `security-review` /
`security-engineer` workload the `slow` tier exists to serve.

**Claude Fable 5** carries a data-handling caveat no other Claude model on
Copilot does: *"Anthropic retains data, including prompts and outputs, to
operate safety classifiers."* It also requires explicit business/enterprise
enablement. Reserve it for genuinely long-horizon autonomous work — it is 2×
Opus.

### OpenAI
| Model | Input | Cached in | Output | Long-ctx tier |
|---|---|---|---|---|
| GPT-5.4 nano ⛔ | $0.20 | $0.02 | $1.25 | — |
| **GPT-5 mini** | **$0.25** | **$0.025** | **$2.00** | — |
| **GPT-5.4 mini** | **$0.75** | **$0.075** | **$4.50** | — |
| GPT-5.6 Luna | $1.00 | $0.10 | $6.00 | **>200K → $2.00 / $9.00** |
| **GPT-5.3-Codex** | **$1.75** | **$0.175** | **$14.00** | — |
| GPT-5.4 | $2.50 | $0.25 | $15.00 | **>272K → $5.00 / $22.50** |
| GPT-5.6 Terra | $2.50 | $0.25 | $15.00 | **>272K → $5.00 / $22.50** |
| GPT-5.5 | $5.00 | $0.50 | $30.00 | **>272K → $10.00 / $45.00** |
| GPT-5.6 Sol | $5.00 | $0.50 | $30.00 | **>272K → $10.00 / $45.00** |

The **GPT-5.6 family** (all GA 2026-07-09, all 1.05M ctx, all vision) splits by
role in GitHub's own words: **Luna** is the cost-efficient "Lightweight" member
(the cheapest 1M-class model in the catalog), **Terra** is *"the balanced
default and a strong all-round choice for everyday interactive and agentic
coding"*, and **Sol** *"has the highest reasoning ceiling in the family"* for
*"complex reasoning over large codebases and demanding, long-running agentic
work"*. Sol is **Pro+/Max/Business/Enterprise only** (not Pro), and its output
is 20% pricier than Opus.

**GPT-5.3-Codex is strategically important beyond its price:** GitHub designated
it on 2026-03-18 as *both* the Copilot **base model** and the **LTS model**,
committing to support it for one year. It is the single most rollout-stable id
in the catalog and the cheapest model in the "Powerful" category — which is why
this preset uses it for `advisor`.

⛔ Retired 2026-06-01 but **still present in OMP's catalog**: `gpt-4.1`,
`gpt-5.2`, `gpt-5.2-codex`. Do not route to them.

### Google
*(This section did not exist before — roughly half the catalog was missing.)*

| Model | Input | Cached in | Output | Long-ctx tier |
|---|---|---|---|---|
| Gemini 3 Flash (preview) ⛔ | $0.50 | $0.05 | $3.00 | — |
| Gemini 2.5 Pro ⛔ | $1.25 | $0.125 | $10.00 | — |
| Gemini 3.5 Flash | $1.50 | $0.15 | $9.00 | — |
| **Gemini 3.1 Pro (preview)** | **$2.00** | **$0.20** | **$12.00** | **>200K → $4.00 / $18.00** |

The OMP id carries the `-preview` suffix — **`gemini-3.1-pro-preview`**, not
plain `gemini-3.1-pro`. This preset uses it for `designer`, following OMP's own
native designer chain, which is Gemini-first (`priority.json`), and GitHub's
model-comparison doc, which lists Gemini 3.1 Pro under both "deep reasoning" and
"working with visuals".

`gemini-3-pro-preview` is also in OMP's bundled catalog but carries **no
published rate** there (all cost fields are $0 placeholders) — treat its price
as unknown.

### Microsoft
| Model | Input | Cached in | Output |
|---|---|---|---|
| **MAI-Code-1-Flash** | **$0.75** | **$0.075** | **$4.50** |

`mai-code-1-flash-picker` — coding-tuned, agentic, 137B total / 5B active MoE,
256K ctx, **128K max output**. Microsoft's own benchmarks put it above Claude
Haiku 4.5 on coding while being *cheaper* than Haiku ($1/$5):

| Bench (vendor-run, not independent) | MAI-Code-1-Flash | Claude Haiku 4.5 |
|---|---|---|
| SWE-Bench Verified | **71.6** | 66.6 |
| SWE-Bench Pro | **51.2** | 35.2 |
| Terminal Bench 2 | **54.8** | 41.6 |

…with up to **60% fewer tokens** (vendor results). That makes it a Pareto
improvement over Haiku for the `task` tier, which is where this preset puts it.

> **⚠ It is the ONLY vision-incapable model in the entire Copilot catalog** —
> its input modalities are `["text"]`; every other model accepts images. Because
> `task` runs on it, `modelRoles.vision` is **mandatory** in this preset:
> `inspect_image` resolves `@vision → @default →` active model and then
> *hard-errors* if what it lands on is text-only. Never move MAI onto `default`
> without a pinned `vision`.

> GitHub's docs also flag MAI as a *"continuously improving model"* whose
> behavior may change between checkpoints — so treat benchmark deltas as
> provisional.

**On the old "VS-Code-only / 400 `unsupported_api_for_model`" warning.** Earlier
versions of this file said GitHub gated MAI to VS-Code OAuth clients on some
tenants. That could **not** be re-confirmed: GitHub's
`model-supported-clients.yml` now shows MAI `true` on every surface **including
CLI**. The far more likely cause of the 400s people hit was on OMP's side, and
it is fixed: `@oh-my-pi/pi-catalog` **17.0.1 (2026-07-16)** — *"Fixed GitHub
Copilot `mai-code-1-flash-picker` (and other `mai-*` models) to route through
the `/responses` endpoint instead of `/chat/completions`, which rejected them
with `400 unsupported_api_for_model`"* (issue #5612). **If you are on OMP
≥ 17.0.1 and still 400, `retry.fallbackChains.task` covers it** — no action
needed.

### Moonshot AI — the only open-weight model on Copilot
| Model | Input | Cached in | Output |
|---|---|---|---|
| **Kimi K2.7 Code** | **$0.95** | **$0.19** | **$4.00** |

`kimi-k2.7-code` is the **first and only open-weight model in GitHub Copilot**.
GitHub's own `model-release-status.yml` groups it under a literal
`# Open-weight models` comment, and the 2026-07-01 changelog calls it *"the
first open-weight model offered as a selectable option in the Copilot model
picker"*. Weights are **Modified-MIT** at
`huggingface.co/moonshotai/Kimi-K2.7-Code`; 1T total / 32B active MoE; hosted by
GitHub on Azure. GA 2026-07-01 (Pro/Pro+/Max), 2026-07-07
(Business/Enterprise). 256K ctx, vision-capable, agentic.

**Its $4.00 output undercuts MAI ($4.50) and Haiku 4.5 ($5.00)** — and output
dominates the `task` tier. Two caveats decide why this preset ships MAI as
`task` and Kimi as a documented opt-in rather than the reverse:

1. **maxTokens 32K vs MAI's 128K.** `task` is the *build* tier; a large
   single-shot implementation slice can truncate.
2. **Off by default on Business/Enterprise** — an admin must enable the policy,
   so on those tenants it silently never resolves.

Its published benchmark numbers (e.g. SWE-Bench Pro 58.6) are **vendor-reported
and not independently verified**. Uncomment the opt-in block in
`config.snippet.yml` to adopt it; the block keeps MAI's 128K output first in the
fallback chain.

> The broader open-weight lineup people expect **is not on Copilot**. Explicitly
> checked and absent: GPT-OSS, Qwen/Qwen3-Coder, DeepSeek, GLM/Z.ai, Llama,
> Mistral/Devstral. xAI/Grok was **removed** (Grok Code Fast 1 retired
> 2026-05-15). The GA catalog is five vendors — OpenAI, Anthropic, Google,
> Microsoft, Moonshot AI — plus GitHub's own fine-tuned Raptor mini. OMP itself
> supports several of the absent ones natively (cerebras/GLM, qwen-portal,
> moonshot, deepseek), which is the argument for **not** pinning
> `enabledModels: [github-copilot/*]`.

### GitHub
| Model | Input | Cached in | Output |
|---|---|---|---|
| Raptor mini ⛔ | $0.25 | $0.025 | $2.00 |

A GitHub fine-tune of GPT-5 mini, billed at GPT-5 mini rates. **Unreachable from
the OMP CLI** — see below.

## Reachability traps

Cheapest on the price sheet ≠ usable. Four rows are priced but unroutable:

| id | Why it fails |
|---|---|
| `gpt-5.4-nano` | `model-supported-clients.yml` sets dotcom/cli/vscode/vs/eclipse/xcode/jetbrains **all false**; it is a Copilot **utility** model (background features only, not selectable). In OMP's catalog — routing to it will fail. |
| `raptor-mini` | `cli=false`, `dotcom=false`, `vs=false` (VS Code only), and Pro/Pro+/Max only — `business=false`, `enterprise=false`. |
| `gemini-3-flash-preview` | `cli=false` and `dotcom=false` despite the attractive $0.50/$3.00. IDE surfaces only. |
| `gemini-2.5-pro` | `cli=false`, `dotcom=false`; legacy, 128K ctx. |

**Retired but still in OMP's catalog — do not route:** `gpt-4.1`, `gpt-5.2`,
`gpt-5.2-codex` (all 2026-06-01), `claude-sonnet-4` (2026-05-01), and
`grok-code-fast-1` (xAI removed from Copilot 2026-05-15).

## The two billing traps

**1. Crossing a long-context input threshold re-prices the WHOLE request.**
It is not a marginal rate on the tokens above the line — the entire request is
billed at the long-context tier. GPT-5.4 and GPT-5.6 Terra jump from
$2.50/$15.00 to **$5.00/$22.50** above 272K input tokens; GPT-5.5 and GPT-5.6
Sol go $5.00/$30.00 → **$10.00/$45.00** above 272K; GPT-5.6 Luna goes
$1.00/$6.00 → **$2.00/$9.00** above 200K; Gemini 3.1 Pro goes $2.00/$12.00 →
**$4.00/$18.00** above 200K. One oversized context dump can double the bill for
a turn that would otherwise have been cheap.

**2. Anthropic 1M-context is a SEPARATE model id, not a flag.** On Copilot the
1M-context selection surfaces as its own id — OMP's Copilot fixtures show
`claude-opus-4.6-1m` / `claude-opus-4.7-1m`, and OMP's context-promotion machinery
targets them by id (`contextPromotionTarget: "github-copilot/claude-opus-4.7-1m"`).
These ids are **discovered live from your account**, not shipped in OMP's bundled
catalog, and they bill at the extended-capability rate. If you pin long context,
pin the `-1m` id knowingly.

## UNVERIFIED — priced by GitHub, not confirmed reachable from OMP

These are real ids in GitHub's docs, but the researcher could **not** confirm
them in OMP's *live resolved* catalog (`pi.dev/api/models`, 28 `github-copilot`
ids at the time of checking). **Do not route to them until
`omp --list-models | grep github-copilot` shows the id on your account.**

| id | Rate (in/out) | Status |
|---|---|---|
| `github-copilot/gemini-3.6-flash` | $1.50 / $7.50 | GA 2026-07-21. Price confirmed from GitHub docs; **absent from OMP's live resolved catalog AND from the bundled `models.json`**. Would be the best `designer` (cheaper than Gemini 3.1 Pro on both axes; Google built it "for web and app development… and longer-horizon agentic tasks" with parallel tool use). Business/Enterprise admins must enable the policy. |
| `github-copilot/claude-opus-5` | $5.00 / $25.00 | GA 2026-07-24. **In OMP's bundled `models.json`** but not seen in the live resolved list. Also `pro=false` and carries the cyber-safeguard refusal risk above. |
| `github-copilot/raptor-mini` | $0.25 / $2.00 | **In OMP's bundled `models.json`** but not seen in the live resolved list — and `cli=false` regardless. |
| `github-copilot/claude-opus-4.8-fast` | $10.00 / $50.00 | "Claude Opus 4.8 (fast mode) (preview)", 2× standard Opus for latency; replaced the Opus 4.6 fast mode retired 2026-06-29. **The id string is a GUESS** — absent from both the live and bundled catalogs. Does not support 1M context. Not recommended: a pure latency play at Fable-5 prices. |
| `github-copilot/claude-opus-4.6-1m`, `…-4.7-1m` | extended rate | Seen only in OMP's Copilot test fixtures; discovered live per account, never bundled. |

The gap between "in the bundled catalog" and "on your account" is normal — the
`github-copilot` provider fetches your entitlement live. **The bundled catalog
is what OMP knows how to price; your account decides what actually answers.**

## Cheapest-first guidance (limit token spend)

- **`smol` — nano ($0.25/$2.00 `gpt-5-mini`).** Pure lexical/checklist reviewers
  (naming, complexity, token-efficiency, a11y, progress-guardian) and
  input-bound scan: no code semantics, no tool-use, so the cheapest **reachable**
  model wins. It keeps vision and 264K ctx, and GitHub's own docs recommend it
  for reasoning/debugging as well as lexical work. Both cheaper price-sheet rows
  are traps (see [Reachability traps](#reachability-traps)).
- **`task` — code ($0.75/$4.50 `mai-code-1-flash-picker`).** Cheap work that
  *does* need code semantics or agentic tool-use: post-plan implementation,
  js-fp/svelte structural review. 128K max output matters here. Open-weight
  alternative: `kimi-k2.7-code` ($0.95/$4.00) — see the opt-in block in
  `config.snippet.yml`.
- **`default`/`plan` — balanced ($2.00/$10.00 `claude-sonnet-5`).** 1M ctx, 128K
  max output, vision, configurable reasoning, available on Pro. Best
  $/capability in the catalog *while the promo lasts* — watch 2026-08-31.
- **`designer` — ($2.00/$12.00 `gemini-3.1-pro-preview`).** Follows OMP's own
  Gemini-first designer chain rather than inventing one.
- **`vision` — ($0.25/$2.00 `gpt-5-mini`).** Cheapest vision-capable CLI model.
  Load-bearing because `task` runs on text-only MAI.
- **`advisor` — ($1.75/$14.00 `gpt-5.3-codex`).** Vendor-diverse against an
  Anthropic `slow`, 44% cheaper output than Opus, and GitHub's base + LTS model.
  Off by default (`advisor.enabled: false`).
- **`slow` — deep ($5.00/$25.00 `claude-opus-4.8`).** High-stakes SECURITY
  verdicts where Opus still leads Sonnet 5. Budget alternative worth knowing:
  `gpt-5.3-codex` at $1.75/$14.00 is 65% cheaper input / 44% cheaper output with
  1M ctx.
- **Don't set `tiny` or `commit`.** OMP already aliases `tiny` to the `smol`
  chain and resolves `commit` via `["commit","smol",…]` — setting them to the
  same id is a no-op.
- **Caching matters**: cached input is ~10× cheaper than fresh input ($0.20 vs
  $2.00 on Sonnet 5). Stable system prompts and reused context get cached, so
  long-lived sessions beat many cold one-shots.
- **Avoid for high-volume work**: GPT-5.5 / GPT-5.6 Sol ($30 out), Fable 5 and
  Opus 4.8-fast ($50 out), and any long-context tier.

**Corrected output-cost ranking** (cheapest → priciest; ⛔ = priced but
unroutable from the OMP CLI):

`gpt-5.4-nano` $1.25 ⛔ < `gpt-5-mini` / `raptor-mini` ⛔ $2.00 <
`gemini-3-flash-preview` $3.00 ⛔ < **`kimi-k2.7-code` $4.00** <
`mai-code-1-flash-picker` / `gpt-5.4-mini` $4.50 < `claude-haiku-4.5` $5.00 <
`gpt-5.6-luna` $6.00 < `gemini-3.6-flash` $7.50 (unverified) <
`gemini-3.5-flash` $9.00 < `gemini-2.5-pro` ⛔ / **`claude-sonnet-5` $10.00** <
`gemini-3.1-pro-preview` $12.00 < `gpt-5.3-codex` $14.00 <
`claude-sonnet-4.5`/`4.6` / `gpt-5.4` / `gpt-5.6-terra` $15.00 <
`claude-opus-4.5`/`4.6`/`4.7`/`4.8`/`5` $25.00 < `gpt-5.5` / `gpt-5.6-sol`
$30.00 < `claude-fable-5` / `claude-opus-4.8-fast` $50.00.

*(The previous ranking in this file omitted Kimi, the whole GPT-5.6 family,
every Google model, Raptor and gpt-5.4-nano — roughly half the catalog.)*

## Cost impact of the cheap-tier choices

The cheap roles are the highest-volume ones (parallel checklist/pattern agents
plus the implementation agent), and **output dominates the bill**.

**`task`/code tier — Haiku 4.5 → MAI-Code-1-Flash.** Cheaper on two compounding
levers — lower rate *and* fewer tokens — and never more expensive than Haiku:

| | Input | Cached in | Output |
|---|---|---|---|
| Claude Haiku 4.5 (before) | $1.00 | $0.10 | $5.00 |
| MAI-Code-1-Flash (after) | $0.75 | $0.075 | $4.50 |
| Δ per token | −25% | −25% | −10% |

Worked example — 1M output tokens at this tier (1 credit = $0.01):

- Haiku 4.5: $5.00 → **500 credits**
- MAI at equal token volume: $4.50 → **450 credits** (−10%)
- MAI with up to 60% fewer tokens (≈0.4M): $1.80 → **180 credits** (**−64%**)

So expect **−10% to −64%** on the code tier, with better coding quality on the
benches Microsoft published.

**The open-weight alternative, priced out.** Against MAI at the same 1M output:

| | Input | Cached in | Output | maxTokens |
|---|---|---|---|---|
| MAI-Code-1-Flash | $0.75 | $0.075 | $4.50 | **128K** |
| Kimi K2.7 Code | $0.95 (+27%) | $0.19 (+153%) | **$4.00 (−11%)** | 32K |

Kimi wins only when the tier is **output-heavy**, which `task` usually is — but
its 32K output ceiling is a correctness risk on a large slice, not just a
quality one, and it is policy-off by default on Business/Enterprise. That is why
it is an opt-in here rather than the default.

**`smol`/nano tier — GPT-5-mini.** For work with no code semantics and no
tool-use, `gpt-5-mini` ($0.25/$2.00) is a further **~67% input / ~56% output**
cut vs MAI on the highest-volume tier — coding quality is irrelevant there, so
the trade-off MAI protects against does not apply. Keep code-semantic work
(js-fp, svelte, implementation) on the code tier, and don't put lexical
checklists on MAI (over-pays ~2×). Match the model to the *shape* of the work.
