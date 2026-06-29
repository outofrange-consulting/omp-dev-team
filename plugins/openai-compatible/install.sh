#!/usr/bin/env bash
# openai-compatible installer (Linux/macOS) — register any OpenAI-compatible
# endpoint (LiteLLM, Ollama, vLLM, LocalAI, …) as a named provider in OMP.
# Prompts for the provider name, base URL, and API key (unless already
# provided via flags/env), lists the available models to confirm connectivity,
# and writes the provider into ~/.omp/agent/models.yml. The key is stored in
# ~/.omp/<name>.key (chmod 600) and referenced from models.yml via
# `apiKey: "!cat …"` — never written inline or exported to shell profiles.
#
# Flags:
#   --name=NAME        provider name in models.yml (default: litellm)
#   --url=URL          endpoint base URL (e.g. http://localhost:4000)
#   --api-key=KEY      API key (blank if the endpoint needs none)
#   --no-config        don't touch models.yml (just mirror the extension)
#   --no-update        no-op (kept for installer compatibility)
#   -y, --yes          non-interactive (use flags/env only)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="${OAI_PROVIDER_NAME:-litellm}"; URL="${OAI_PROVIDER_URL:-}"; KEY="${OAI_PROVIDER_API_KEY:-}"
YES=0; NO_CONFIG=0; INSECURE_TLS=0
for a in "$@"; do case "$a" in
  -y|--yes) YES=1 ;; --no-update) ;; --insecure-tls) INSECURE_TLS=1 ;; --ca-file=*) CA_FILE="${a#*=}" ;;
  --name=*) NAME="${a#*=}" ;; --url=*) URL="${a#*=}" ;; --api-key=*) KEY="${a#*=}" ;; --no-config) NO_CONFIG=1 ;;
  -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
{ [ "${INSECURE_TLS:-0}" = 1 ] || [ -n "${OMP_INSECURE_TLS:-}" ]; } && export NODE_TLS_REJECT_UNAUTHORIZED=0
CA_FILE="${CA_FILE:-${OMP_CA_FILE:-}}"
[ -n "$CA_FILE" ] && [ -f "$CA_FILE" ] && export NODE_EXTRA_CA_CERTS="$CA_FILE"

BUN="$(command -v bun || echo "$HOME/.bun/bin/bun")"
[ -x "$BUN" ] || { warn "bun not found — install OMP first (bash install.sh at repo root)"; exit 0; }

EXT="$HERE/extensions/openai-provider.ts"

# --- gather name + URL + key ------------------------------------------------
if [ -z "$URL" ] && [ "$YES" = 0 ] && [ -r /dev/tty ]; then
  printf '    Provider name (default: %s): ' "$NAME"; read -r _N </dev/tty || _N=""
  [ -n "$_N" ] && NAME="$_N"
  printf '    Base URL (e.g. http://localhost:4000): '; read -r URL </dev/tty || URL=""
fi
if [ -z "$URL" ]; then
  say "No URL given — skipping provider config (set OAI_PROVIDER_URL or pass --url=… and re-run)."
  URL=""
fi
if [ -n "$URL" ] && [ -z "$KEY" ] && [ "$YES" = 0 ] && [ -r /dev/tty ]; then
  printf '    API key (hidden; blank if the endpoint needs none): '; read -r -s KEY </dev/tty || KEY=""; echo
fi

if [ -n "$URL" ]; then
  say "Listing models for provider '${NAME}' from ${URL}"
  if MODELS="$("$BUN" "$EXT" --list --url "$URL" ${KEY:+--api-key "$KEY"} 2>/dev/null)" && [ -n "$MODELS" ]; then
    printf '%s\n' "$MODELS" | sed 's/^/      • /'
  else
    warn "could not list models from $URL (check URL/key and that the endpoint is running). Writing config anyway — OMP discovers models at runtime."
  fi

  if [ "$NO_CONFIG" = 0 ]; then
    KEYFILE="$HOME/.omp/${NAME}.key"; MODELS_YML="$HOME/.omp/agent/models.yml"
    mkdir -p "$HOME/.omp/agent"

    if [ -n "$KEY" ]; then
      umask 077; printf '%s' "$KEY" > "$KEYFILE"; chmod 600 "$KEYFILE"
      APIREF="\"!cat $KEYFILE\""
    else
      APIREF='""'
    fi

    # Persist URL + name to shell profiles so the extension can register live on
    # startup. The API key is NEVER exported — it lives only in the key file.
    for p in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
      [ -e "$p" ] || continue
      grep -qsF OAI_PROVIDER_URL "$p" || printf '\nexport OAI_PROVIDER_URL=%q\n' "$URL" >> "$p"
      grep -qsF OAI_PROVIDER_NAME "$p" || printf 'export OAI_PROVIDER_NAME=%q\n' "$NAME" >> "$p"
    done

    touch "$MODELS_YML"
    if grep -qE "^[[:space:]]+${NAME}:" "$MODELS_YML" 2>/dev/null; then
      say "Provider '${NAME}' already in $MODELS_YML — preserved (delete it to regenerate)."
    else
      BLOCK="$("$BUN" "$EXT" --yaml --name "$NAME" --url "$URL" --api-key-ref "$APIREF")"
      INNER="$(printf '%s\n' "$BLOCK" | sed '1d')"
      BAK="$MODELS_YML.bak"; cp "$MODELS_YML" "$BAK"
      if grep -qE "^providers:[[:space:]]*$" "$MODELS_YML" 2>/dev/null; then
        awk -v blk="$INNER" 'BEGIN{done=0} {print} /^providers:[[:space:]]*$/ && !done {print blk; done=1}' "$MODELS_YML" > "$MODELS_YML.tmp" && mv "$MODELS_YML.tmp" "$MODELS_YML"
      else
        { printf '\n'; printf '%s\n' "$BLOCK"; } >> "$MODELS_YML"
      fi
      if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
        if python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "$MODELS_YML" >/dev/null 2>&1; then
          rm -f "$BAK"; say "Wrote the '${NAME}' provider to $MODELS_YML (validated)"
        else
          mv "$BAK" "$MODELS_YML"
          warn "Result was not valid YAML — restored $MODELS_YML from backup. Add the provider manually."
        fi
      else
        rm -f "$BAK"; say "Wrote the '${NAME}' provider to $MODELS_YML (no YAML validator found — skipped validation)"
      fi
    fi
  fi
fi

# --- Load the provider extension into OMP's native dir ----------------------
if [ -d "$HERE/extensions" ]; then
  DEST="$HOME/.omp/agent/extensions/openai-compatible"
  rm -rf "$DEST"; mkdir -p "$DEST"; cp -R "$HERE/extensions" "$DEST/"
  [ -f "$HERE/package.json" ] && cp "$HERE/package.json" "$DEST/"
  say "openai-compatible provider extension loaded"
fi

say "openai-compatible ready. Restart omp; reference models as '${NAME}/<model-id>' in modelRoles. Re-list anytime with /oai-provider."
