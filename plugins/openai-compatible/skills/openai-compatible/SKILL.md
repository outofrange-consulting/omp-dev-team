---
name: openai-compatible
description: >-
  Register or use any OpenAI-compatible provider (LiteLLM, Ollama, vLLM,
  LocalAI, …) in OMP. Use when the user mentions LiteLLM, a self-hosted
  OpenAI-compatible endpoint, a local model gateway, routing through a proxy
  URL + API key, or the `/oai-provider` command.
---

# openai-compatible — any OpenAI-compatible endpoint as an OMP provider

Any service that speaks `GET /v1/models` + `POST /v1/chat/completions` with
`Authorization: Bearer <key>` (e.g. **LiteLLM**, **Ollama**, **vLLM**,
**LocalAI**) can be registered as a named OMP provider with this plugin.

## Setup

```sh
bash plugins/openai-compatible/install.sh        # interactive: prompts for name, URL, key
#   pwsh -File plugins/openai-compatible/install.ps1   # Windows
# or non-interactively:
bash plugins/openai-compatible/install.sh --name=litellm --url=http://localhost:4000 --api-key=YOURKEY
```

The installer probes `GET <url>/v1/models` (Bearer auth) to confirm connectivity
and **list the models**, then writes the provider to `~/.omp/agent/models.yml`:

```yaml
providers:
  litellm:
    baseUrl: http://localhost:4000/v1
    api: openai-completions
    apiKey: "!cat ~/.omp/litellm.key"   # key stored chmod 600, not inline
    authHeader: true
    discovery:
      type: openai-models-list           # model list stays fresh at runtime
```

The base URL is normalised to end in `/v1`. The API key is saved to
`~/.omp/<name>.key` (chmod 600) and referenced by command expansion — it is
**never** written inline or exported to shell profiles.

## Use it

- Reference any gateway model in `~/.omp/agent/config.yml`:
  ```yaml
  modelRoles:
    default: litellm/claude-sonnet-4-5
    smol:    litellm/gpt-4o-mini
  ```
- `/oai-provider` — re-list the endpoint's models and re-register the provider
  live (reads `OAI_PROVIDER_URL` / `OAI_PROVIDER_NAME`).

Because discovery is `openai-models-list`, you don't pin a model catalogue: OMP
asks the endpoint for its current models each session.

## Env vars (set by the installer)

| Var | Purpose |
|---|---|
| `OAI_PROVIDER_URL` | Base URL of the endpoint (exported to shell profiles) |
| `OAI_PROVIDER_NAME` | Provider name used in models.yml (exported to shell profiles) |

The API key is **never** in env — only in `~/.omp/<name>.key`.
