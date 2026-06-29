# openai-compatible

Register any **OpenAI-compatible** endpoint (LiteLLM, Ollama, vLLM, LocalAI, …)
as a named model provider in Oh-My-Pi.

## Install

```sh
bash plugins/openai-compatible/install.sh
#   pwsh -File plugins/openai-compatible/install.ps1     # Windows
# non-interactive:
bash plugins/openai-compatible/install.sh --name=litellm --url=http://localhost:4000 --api-key=YOURKEY
```

What it does:

1. **Asks** for a provider name (default `litellm`), base URL, and API key.
2. **Lists** the endpoint's models (`GET <url>/v1/models`) to confirm it works.
3. **Writes** the provider into `~/.omp/agent/models.yml` with
   `discovery: openai-models-list`, so the model list stays current at runtime.
4. Stores the key in `~/.omp/<name>.key` (chmod 600), referenced from
   `models.yml` via `apiKey: "!cat …"` — never written inline or in env.
5. Loads the extension so `/oai-provider` re-lists models on demand.

## Use

Set model roles in `~/.omp/agent/config.yml`:

```yaml
modelRoles:
  default: litellm/claude-sonnet-4-5
  smol:    litellm/gpt-4o-mini
```

`/oai-provider` re-lists the endpoint's models and re-registers the provider live.

## Notes

- The base URL is normalised to end in `/v1` (so `http://host:4000` works).
- Re-running preserves an existing provider block — delete it from `models.yml`
  to regenerate.
- The provider name is configurable: `--name=mygateway` creates a `mygateway`
  provider usable as `mygateway/<model-id>`.
