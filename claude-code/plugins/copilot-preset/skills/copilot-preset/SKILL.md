---
name: copilot-preset
description: >-
  How this machine runs Claude Code on a GitHub Copilot license via the copilot-api
  bridge. Use when the user asks how to use Copilot models with Claude Code, how the
  bridge is configured, or how to change the tier→model mapping.
---

# Run Claude Code on GitHub Copilot

Claude Code speaks the **Anthropic API**; GitHub Copilot does not, so they can't
connect directly. The accepted approach is a local translation bridge —
[`copilot-api`](https://github.com/ericc-ch/copilot-api) — that exposes Copilot as
an Anthropic-compatible server, with Claude Code pointed at it via
`ANTHROPIC_BASE_URL`.

## Start the bridge
```sh
npx copilot-api@latest start --claude-code        # interactive model pick, port 4141
# non-interactive: npx copilot-api@latest start --github-token ghp_xxx
```

## How it's wired (set by the installer in `~/.claude/settings.json` → `env`)
```jsonc
"env": {
  "ANTHROPIC_BASE_URL": "http://localhost:4141",
  "ANTHROPIC_AUTH_TOKEN": "dummy",
  "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4.5",   // a Copilot-served id
  "ANTHROPIC_DEFAULT_OPUS_MODEL":   "claude-opus-41",
  "ANTHROPIC_DEFAULT_HAIKU_MODEL":  "claude-haiku-4.5"
}
```

## Notes
- The bridge must be **running** (`npx copilot-api start`) whenever you use Claude
  Code, or requests fail. Consider a login item / service if you use it daily.
- Pick model ids that your Copilot plan actually serves (the bridge lists them).
- `ANTHROPIC_BASE_URL` is read once at startup — restart `claude` after changing it.
- This redirects **all** Claude Code traffic. Remove the env keys from
  `~/.claude/settings.json` to go back to Anthropic direct.
- Alternatives to `copilot-api`: a LiteLLM gateway exposing an Anthropic endpoint, or
  `cc-copilot-bridge`. Same `ANTHROPIC_BASE_URL` mechanism either way.
