# cliproxy

Register a [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) gateway as
an **OpenAI-compatible model provider** in Oh-My-Pi.

CLIProxyAPI is a self-hosted proxy that exposes upstream models (Gemini, Codex,
Claude, Grok — typically via CLI/OAuth accounts) behind the standard OpenAI API
(`GET /v1/models`, `POST /v1/chat/completions`, `Authorization: Bearer <key>`,
default port `8317`). This plugin turns that gateway into the **`cliproxy`**
provider so its models are usable as `cliproxy/<model-id>` anywhere in OMP.

## Install

```sh
bash plugins/cliproxy/install.sh
#   pwsh -File plugins/cliproxy/install.ps1     # Windows
# non-interactive:
bash plugins/cliproxy/install.sh --url=http://localhost:8317 --api-key=YOURKEY
```

What it does:

1. **Prompts** for the gateway URL and API key (or reads `--url`/`--api-key`, or
   `CLIPROXY_URL`/`CLIPROXY_API_KEY`).
2. **Lists** the gateway's models (`GET <url>/v1/models`) to confirm it works.
3. **Writes** a `cliproxy` provider into `~/.omp/agent/models.yml` with
   `discovery: openai-models-list`, so the model list stays current at runtime.
4. Stores the key in `~/.omp/cliproxy.key` (chmod 600), referenced from
   `models.yml` via `apiKey: "!cat …"` — never written inline.
5. Loads the provider extension so `/cliproxy` re-lists models on demand.

## Use

```yaml
# ~/.omp/agent/config.yml
modelRoles:
  default: cliproxy/gemini-2.5-flash
  smol: cliproxy/gpt-5-mini
```

`/cliproxy` re-lists the gateway's models and re-registers the provider live.

## Notes

- The base URL is normalised to end in `/v1` (so `http://host:8317` works).
- Re-running preserves an existing `cliproxy` provider block — delete it from
  `models.yml` to regenerate.
