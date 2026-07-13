#!/usr/bin/env bash
# token-diet component installer (Copilot CLI, Linux/macOS).
# Installs ctx-wire (transparent shell-output compression + secret scrub) and its
# PATH shims, codebase-memory-mcp (registered into ~/.copilot/mcp-config.json),
# the postToolUse output-compression hook, and the caveman/yagni instructions.
# Flags:
#   --sources-root=PATH  parent dir of your repos to index (default: cwd)
#   --depth=N            repo search depth under the root (default 3)
#   --no-update --no-config --insecure-tls --ca-file=PATH  -y/--yes
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$(cd "$HERE/../../lib" && pwd)"
COPILOT_HOME="${COPILOT_HOME:-$HOME/.copilot}"
YES=0; SROOT=""; DEPTH=3; NO_UPDATE=0; NO_CONFIG=0; INSECURE_TLS=0
for a in "$@"; do case "$a" in
  -y|--yes) YES=1 ;; --no-update) NO_UPDATE=1 ;; --no-config) NO_CONFIG=1 ;;
  --insecure-tls) INSECURE_TLS=1 ;; --ca-file=*) CA_FILE="${a#*=}" ;;
  --sources-root=*|--project=*) SROOT="${a#*=}" ;; --depth=*) DEPTH="${a#*=}" ;;
  -h|--help) sed -n '2,12p' "$0"; exit 0 ;; *) : ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { eval "$@"; }
{ [ "${INSECURE_TLS:-0}" = 1 ] || [ -n "${OMP_INSECURE_TLS:-}" ]; } && export GIT_SSL_NO_VERIFY=true NODE_TLS_REJECT_UNAUTHORIZED=0
CA_FILE="${CA_FILE:-${OMP_CA_FILE:-}}"
[ -n "$CA_FILE" ] && [ -f "$CA_FILE" ] && export CURL_CA_BUNDLE="$CA_FILE" GIT_SSL_CAINFO="$CA_FILE" NODE_EXTRA_CA_CERTS="$CA_FILE"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

# --- ctx-wire ---------------------------------------------------------------
if have ctx-wire && [ "$NO_UPDATE" = 1 ]; then say "ctx-wire present"
elif have ctx-wire; then say "Updating ctx-wire"; run "ctx-wire update || true"
else
  say "Installing latest ctx-wire"
  if have curl; then run "curl -fsSL https://ctx-wire.dev/install.sh | sh || true"
  else warn "need curl to install ctx-wire — see https://ctx-wire.dev"; fi
fi
have ctx-wire && run "ctx-wire shims install || true"

# Optional EN+FR filter pack (reused from the sibling OMP token-diet plugin if the
# full repo is present). ctx-wire's user filter tier overrides the built-ins.
PACK_DIR="$HERE/../../../plugins/token-diet/ctx-wire/filters.d"
if [ -d "$PACK_DIR" ] && have ctx-wire; then
  CTXW_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ctx-wire"; mkdir -p "$CTXW_DIR"
  say "Adding EN+FR ctx-wire filters (git-status + dotnet build/test/restore/run/tool)"
  for f in "$PACK_DIR"/*.toml; do cp -f "$f" "$CTXW_DIR/" 2>/dev/null || true; done
  run "ctx-wire verify || true"
fi

# --- codebase-memory-mcp ----------------------------------------------------
CBM="codebase-memory-mcp"
if have "$CBM" && [ "$NO_UPDATE" = 1 ]; then say "$CBM present"
else
  say "Installing latest $CBM"
  if have curl; then run "curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash || true"
  else warn "need curl to install $CBM — see https://github.com/DeusData/codebase-memory-mcp"; fi
fi
hash -r 2>/dev/null || true

# Register in ~/.copilot/mcp-config.json (absolute command path; merge preserves
# anything you already configured — GitHub MCP, etc.).
if [ "$NO_CONFIG" = 0 ] && { have "$CBM" || [ -x "$HOME/.local/bin/$CBM" ]; }; then
  CBMBIN="$(command -v "$CBM" 2>/dev/null || echo "$HOME/.local/bin/$CBM")"
  MCP="$COPILOT_HOME/mcp-config.json"; mkdir -p "$COPILOT_HOME"
  patch="$(mktemp)"
  cat > "$patch" <<EOF
{ "mcpServers": { "$CBM": { "type": "local", "command": "$CBMBIN", "args": [], "tools": ["*"] } } }
EOF
  say "Registering $CBM in $MCP"
  if have node; then run "node \"$LIB/merge-json.mjs\" \"$MCP\" \"$patch\" >/dev/null || true"
  else warn "node not found — add $CBM to $MCP manually"; fi
  rm -f "$patch"
fi

# --- runtime (postToolUse compression hook + instructions) ------------------
say "Installing token-diet runtime into $COPILOT_HOME/token-diet"
DEST="$COPILOT_HOME/token-diet"
rm -rf "$DEST"; mkdir -p "$DEST/hooks/scripts" "$DEST/instructions"
cp -f "$HERE"/hooks/scripts/*.mjs "$DEST/hooks/scripts/"
cp -f "$HERE"/instructions/*.md "$DEST/instructions/"
ok "postToolUse output-compression hook + caveman/yagni instructions installed"

# --- index source repos with codebase-memory-mcp ----------------------------
if have "$CBM"; then
  if [ -z "$SROOT" ]; then
    if [ "$YES" = 0 ] && [ -r /dev/tty ]; then
      printf 'Sources ROOT to index (every git repo under it)? [default: %s] ' "$PWD"; read -r SROOT </dev/tty || SROOT=""
    fi
    SROOT="${SROOT:-$PWD}"
  fi
  run "$CBM config set auto_index true" || true
  index_one() { say "  $CBM: $1"; run "$CBM cli index_repository '{\"repo_path\": \"$1\"}'" || true; }
  if [ -d "$SROOT/.git" ]; then index_one "$SROOT"
  else
    found=0
    while IFS= read -r g; do [ -n "$g" ] || continue; found=$((found+1)); index_one "$(dirname "$g")"; done <<EOF
$(find "$SROOT" -maxdepth "$DEPTH" -type d -name .git 2>/dev/null)
EOF
    [ "$found" = 0 ] && { warn "no git repos under $SROOT — indexing it as one project"; index_one "$SROOT"; } || say "Indexed $found repo(s)."
  fi
fi

say "token-diet ready. ctx-wire shims active; $CBM registered. The output-compression hook is"
echo "    armed per-repo by 'dt init' (dev-team), or add packs/token-diet/hooks to .github/hooks manually."
echo "    Add the caveman/yagni guidance: append $DEST/instructions/token-diet.md to .github/copilot-instructions.md"
