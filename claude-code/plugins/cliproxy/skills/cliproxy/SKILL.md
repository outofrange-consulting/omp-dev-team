---
name: cliproxy
description: >-
  How this machine routes Claude Code through a CLIProxyAPI gateway. Use when the
  user asks how the model backend is configured, how to point Claude Code at the
  CLIProxyAPI gateway, which models are available, or how to change the
  opus/sonnet/haiku tier mappings.
---

# CLIProxyAPI as the model backend

[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) is a local gateway that
re-exposes CLI-account LLMs (Gemini, Codex/ChatGPT, Claude, Grok, …) on an
**Anthropic-compatible** endpoint (default `http://127.0.0.1:8317`). Claude Code
talks to it natively — no plugin tool or MCP needed.

## How it's wired (set by the installer in `~/.claude/settings.json` → `env`)
```jsonc
"env": {
  "ANTHROPIC_BASE_URL": "http://127.0.0.1:8317",
  "ANTHROPIC_AUTH_TOKEN": "<gateway key>",          // sent as Authorization: Bearer
  "ANTHROPIC_DEFAULT_OPUS_MODEL":   "<gateway model id>",
  "ANTHROPIC_DEFAULT_SONNET_MODEL": "<gateway model id>",
  "ANTHROPIC_DEFAULT_HAIKU_MODEL":  "<gateway model id>"
}
```

## Notes
- `ANTHROPIC_BASE_URL` must be a full absolute URL (`http://host:port`) and is read
  **once at process start** — restart `claude` after changing it.
- Use `ANTHROPIC_AUTH_TOKEN` (Bearer), not `ANTHROPIC_API_KEY`, for a gateway.
- The gateway, not Claude Code, owns upstream account auth and model availability —
  list models on the gateway side. Older CLIProxyAPI (v1) used `ANTHROPIC_MODEL` +
  `ANTHROPIC_SMALL_FAST_MODEL` instead of the per-tier `*_MODEL` vars.
- This redirects **all** Claude Code traffic on this machine. To go back to
  Anthropic direct, remove these env keys from `~/.claude/settings.json`.
