# copilot-preset

A **ready model configuration** that routes [Oh-My-Pi](https://github.com/can1357/oh-my-pi)
— and, if installed, the **dev-team** plugin — through **GitHub Copilot**
(`github-copilot` provider). For teams that already pay for Copilot and want OMP
to run on that license instead of direct provider billing.

Standalone and config-only: it ships a skill + a config snippet. It deliberately
has **no extensions** — model routing (`modelRoles`) is a user setting, so you
paste the snippet rather than have a plugin set it for you.

## Setup

```sh
omp plugin install copilot-preset@omp-dev-team

# 1) authenticate Copilot
omp            # then /login -> GitHub Copilot   (OAuth)
#   or: export COPILOT_GITHUB_TOKEN=...   (falls back to GH_TOKEN / GITHUB_TOKEN)

# 2) see what your plan exposes
omp --list-models | grep github-copilot

# 3) paste config.snippet.yml into ~/.omp/agent/config.yml (adjust ids to match)
```

## What it sets

`modelRoles` mapping the tiers to Copilot models, `enabledModels: [github-copilot/*]`,
and `modelProviderOrder: [github-copilot]`:

| Role | Model |
|---|---|
| `smol` (dev-team small tier) | `github-copilot/gpt-5.4-mini` (or `grok-code-fast-1`) |
| `default` / `task` | `github-copilot/claude-sonnet-4.5` |
| `slow` (deep) | `github-copilot/claude-opus-4.6` (or `gpt-5.5`) |

## Notes

- **Premium requests**: Copilot meters most models by a premium-request
  multiplier. Keep the high-volume `smol` tier on a cheap model (`*-mini`,
  `grok-code-fast-1`). The provider sends the right headers automatically.
- **Model ids vary by plan/date** — confirm with `omp --list-models | grep
  github-copilot` and edit the snippet.
- **dev-team interplay**: the small tier (`pi/smol`) follows this automatically;
  agents that pin Anthropic ids need an interactive Copilot default or a
  `model:` edit to run on Copilot. See `skill://copilot-preset`.
- This plugin is independent of `dev-team` and `azure-devops-fs`.
