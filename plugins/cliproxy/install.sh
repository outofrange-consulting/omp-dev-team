#!/usr/bin/env bash
# cliproxy installer (Linux/macOS) — register a CLIProxyAPI gateway as an
# OpenAI-compatible model provider in OMP. Prompts for the gateway URL + API key
# (unless already provided via flags/env), lists the available models to confirm
# connectivity, and writes the provider into ~/.omp/agent/models.yml. The key is
# stored in ~/.omp/cliproxy.key (chmod 600) and referenced from models.yml.
# Flags:
#   --url=URL          gateway base URL (e.g. http://localhost:8317)
#   --api-key=KEY      gateway API key
#   --no-config        don't touch models.yml (just mirror the extension)
#   --no-update        no-op (kept for installer compatibility)
#   -y, --yes          non-interactive (skip prompts; use flags/env only)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YES=0; URL="${CLIPROXY_URL:-}"; KEY="${CLIPROXY_API_KEY:-}"; NO_CONFIG=0; INSECURE_TLS=0
for a in "$@"; do case "$a" in
  -y|--yes) YES=1 ;; --no-update) ;; --insecure-tls) INSECURE_TLS=1 ;; --ca-file=*) CA_FILE="${a#*=}" ;;
  --url=*) URL="${a#*=}" ;; --api-key=*) KEY="${a#*=}" ;; --no-config) NO_CONFIG=1 ;;
  -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
# Corporate TLS / CA passthrough (consistent with the other plugin installers).
{ [ "${INSECURE_TLS:-0}" = 1 ] || [ -n "${OMP_INSECURE_TLS:-}" ]; } && export NODE_TLS_REJECT_UNAUTHORIZED=0
CA_FILE="${CA_FILE:-${OMP_CA_FILE:-}}"
[ -n "$CA_FILE" ] && [ -f "$CA_FILE" ] && export NODE_EXTRA_CA_CERTS="$CA_FILE"

BUN="$(command -v bun || echo "$HOME/.bun/bin/bun")"
[ -x "$BUN" ] || { warn "bun not found — install OMP first (bash install.sh at repo root)"; exit 0; }

# --- gather URL + key -------------------------------------------------------
if [ -z "$URL" ] && [ "$YES" = 0 ] && [ -r /dev/tty ]; then
  printf '    CLIProxyAPI gateway URL (e.g. http://localhost:8317): '; read -r URL </dev/tty || URL=""
fi
if [ -z "$URL" ]; then
  say "No gateway URL given — skipping provider config (set CLIPROXY_URL or pass --url=… and re-run)."
  # still mirror the extension below so /cliproxy works once configured
  URL=""
fi
if [ -n "$URL" ] && [ -z "$KEY" ] && [ "$YES" = 0 ] && [ -r /dev/tty ]; then
  printf '    API key (hidden; blank if the gateway needs none): '; read -r -s KEY </dev/tty || KEY=""; echo
fi

if [ -n "$URL" ]; then
  say "Listing models from $URL"
  if MODELS="$("$BUN" "$HERE/extensions/cliproxy.ts" --list --url "$URL" ${KEY:+--api-key "$KEY"} 2>/dev/null)" && [ -n "$MODELS" ]; then
    printf '%s\n' "$MODELS" | sed 's/^/      • /'
  else
    warn "could not list models from $URL (check the URL/key and the gateway is running). Writing config anyway — OMP discovers models at runtime."
  fi

  if [ "$NO_CONFIG" = 0 ]; then
    KEYFILE="$HOME/.omp/cliproxy.key"; MODELS_YML="$HOME/.omp/agent/models.yml"
    mkdir -p "$HOME/.omp/agent"
    if [ -n "$KEY" ]; then
      umask 077; printf '%s' "$KEY" > "$KEYFILE"; chmod 600 "$KEYFILE"
      APIREF="\"!cat $KEYFILE\""
      # Export for the live extension + persist for new shells.
      for p in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -e "$p" ] || continue
        grep -qsF CLIPROXY_URL "$p" || printf '\nexport CLIPROXY_URL=%q\n' "$URL" >> "$p"
        grep -qsF CLIPROXY_API_KEY "$p" || printf 'export CLIPROXY_API_KEY="$(cat %q 2>/dev/null)"\n' "$KEYFILE" >> "$p"
      done
    else
      APIREF='""'
      for p in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -e "$p" ] || continue; grep -qsF CLIPROXY_URL "$p" || printf '\nexport CLIPROXY_URL=%q\n' "$URL" >> "$p"
      done
    fi

    touch "$MODELS_YML"
    if grep -qE "^[[:space:]]+cliproxy:" "$MODELS_YML" 2>/dev/null; then
      say "Provider 'cliproxy' already in $MODELS_YML — preserved (delete it to regenerate)."
    else
      # Generate the provider block, then merge under any existing `providers:`.
      BLOCK="$("$BUN" "$HERE/extensions/cliproxy.ts" --yaml --url "$URL" --api-key-ref "$APIREF")"
      # Drop the leading `providers:` line from the generated block when merging
      # into a file that already has one.
      INNER="$(printf '%s\n' "$BLOCK" | sed '1d')"
      if grep -qE "^providers:" "$MODELS_YML" 2>/dev/null; then
        awk -v blk="$INNER" 'BEGIN{done=0} {print} /^providers:[[:space:]]*$/ && !done {print blk; done=1}' "$MODELS_YML" > "$MODELS_YML.tmp" && mv "$MODELS_YML.tmp" "$MODELS_YML"
      else
        { printf '\n'; printf '%s\n' "$BLOCK"; } >> "$MODELS_YML"
      fi
      say "Wrote the cliproxy provider to $MODELS_YML"
    fi
  fi
fi

# --- Load the provider extension into OMP's native dir ----------------------
if [ -d "$HERE/extensions" ]; then
  DEST="$HOME/.omp/agent/extensions/cliproxy"
  rm -rf "$DEST"; mkdir -p "$DEST"; cp -R "$HERE/extensions" "$DEST/"
  [ -f "$HERE/package.json" ] && cp "$HERE/package.json" "$DEST/"
  say "cliproxy provider extension loaded"
fi

say "cliproxy ready. Restart omp; reference models as 'cliproxy/<model-id>' in modelRoles. Re-list anytime with /cliproxy."
