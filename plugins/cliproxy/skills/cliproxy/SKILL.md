---
name: cliproxy
description: >-
  Register and use a CLIProxyAPI gateway as a model provider in OMP. Use when the
  user mentions CLIProxyAPI, a self-hosted OpenAI-compatible model gateway/proxy,
  routing models through a proxy URL + API key, or the `/cliproxy` command.
---

# cliproxy — a CLIProxyAPI gateway as an OMP model provider

[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) is a self-hosted
gateway that exposes upstream models (Gemini, Codex, Claude, Grok — often via
CLI/OAuth accounts) behind a standard **OpenAI-compatible** API. This plugin
registers it as the **`cliproxy`** provider so its models are usable as
`cliproxy/<model-id>` in `modelRoles`.

## Setup

```sh
bash plugins/cliproxy/install.sh        # prompts for URL + API key
#   pwsh -File plugins/cliproxy/install.ps1   # Windows
# or non-interactively:
bash plugins/cliproxy/install.sh --url=http://localhost:8317 --api-key=YOURKEY
```

The installer probes `GET <url>/v1/models` (Bearer auth) to confirm connectivity
and **list the models**, then writes the provider to `~/.omp/agent/models.yml`:

```yaml
providers:
  cliproxy:
    baseUrl: http://localhost:8317/v1
    api: openai-completions
    apiKey: "!cat ~/.omp/cliproxy.key"   # key stored chmod 600, not inline
    authHeader: true
    discovery:
      type: openai-models-list           # model list stays fresh at runtime
```

The default CLIProxyAPI port is **8317**; the base URL is normalised to end in
`/v1`. The API key is saved to `~/.omp/cliproxy.key` (chmod 600) and referenced
by command expansion — it is never written inline.

## Use it

- Reference any gateway model in `~/.omp/agent/config.yml`:
  ```yaml
  modelRoles:
    default: cliproxy/gemini-2.5-flash
    smol: cliproxy/gpt-5-mini
  ```
- `/cliproxy` — re-list the gateway's models and re-register the provider live
  (reads `CLIPROXY_URL` / `CLIPROXY_API_KEY`).

Because discovery is `openai-models-list`, you don't pin a model catalogue: OMP
asks the gateway for its current models each session.
