#!/usr/bin/env bash
# cc-dev-team — global installer (Linux/macOS).
# Installs the Claude Code CLI, registers this marketplace, then interactively
# offers each plugin and each external dependency (ctx-wire, codebase-memory-mcp,
# pup, …). Configures ~/.claude/settings.json by MERGING (never clobbering — the
# config is JSON, so the merge is structural, not a fragile YAML append).
#
# Flags:
#   -y, --yes        non-interactive: install all plugins + their default deps
#   --no-update      keep tools already installed (don't refresh them)
#   --no-node        skip installing Node.js (assume it's present; required by the
#                    plugin hooks/statusline/gate, all of which run on `node`)
#   --insecure-tls   disable TLS cert verification for this run (corporate MITM);
#                    also via CC_INSECURE_TLS=1. Prefer --ca-file.
#   --ca-file=PATH   trust a corporate root CA for node/curl/git (keeps verify ON)
#   -h, --help       this help
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # the claude-code/ dir
MARKET="cc-dev-team"
YES=0; NO_UPDATE=0; NODE=1; INSECURE_TLS=0; CA_FILE="${CC_CA_FILE:-}"
for a in "$@"; do case "$a" in
  -y|--yes) YES=1 ;; --no-update) NO_UPDATE=1 ;; --no-node) NODE=0 ;;
  --insecure-tls) INSECURE_TLS=1 ;; --ca-file=*) CA_FILE="${a#*=}" ;;
  -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
SETTINGS="$HOME/.claude/settings.json"
SECRETS="$HOME/.claude/cc-dev-team.env"
PROFILES=("$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc")

if [ "$INSECURE_TLS" = 1 ] || [ -n "${CC_INSECURE_TLS:-}" ]; then
  warn "Insecure TLS: certificate verification DISABLED for this run."
  export GIT_SSL_NO_VERIFY=true NODE_TLS_REJECT_UNAUTHORIZED=0 NPM_CONFIG_STRICT_SSL=false
  CURLF="-k"; else CURLF=""
fi
trust_ca() {
  local f="$1" abs v p
  [ -f "$f" ] || { warn "CA file not found: $f"; return 0; }
  abs="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
  say "Trusting corporate CA: $abs"
  for v in NODE_EXTRA_CA_CERTS CURL_CA_BUNDLE GIT_SSL_CAINFO REQUESTS_CA_BUNDLE; do export "$v=$abs"; done
  for p in "${PROFILES[@]}"; do [ -e "$p" ] || continue; grep -qsF "NODE_EXTRA_CA_CERTS=" "$p" && continue
    { echo; echo "# cc-dev-team corporate CA"; for v in NODE_EXTRA_CA_CERTS CURL_CA_BUNDLE GIT_SSL_CAINFO REQUESTS_CA_BUNDLE; do printf 'export %s=%q\n' "$v" "$abs"; done; } >> "$p"; done
}
[ -n "$CA_FILE" ] && trust_ca "$CA_FILE"

# ask "Q?" default(Y/n) -> 0 for yes
ask() {
  local q="$1" def="${2:-Y}" ans
  [ "$YES" = 1 ] && return 0
  [ -r /dev/tty ] || { case "$def" in [Yy]*) return 0 ;; *) return 1 ;; esac; }
  if [ "$def" = Y ]; then q="$q [Y/n] "; else q="$q [y/N] "; fi
  read -r -p "$q" ans </dev/tty || ans=""; ans="${ans:-$def}"
  case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
}
# prompt "label" [hidden] -> echoes typed value
prompt() {
  local label="$1" mode="${2:-}" ans=""
  { [ "$YES" = 1 ] || [ ! -r /dev/tty ]; } && { printf ''; return 0; }
  if [ "$mode" = hidden ]; then read -r -s -p "    $label: " ans </dev/tty || ans=""; printf '\n' >/dev/tty
  else read -r -p "    $label: " ans </dev/tty || ans=""; fi
  printf '%s' "$ans"
}
ensure_path() {
  local dir="$1" p
  [ -d "$dir" ] || return 0
  case ":$PATH:" in *":$dir:"*) ;; *) PATH="$dir:$PATH"; export PATH ;; esac
  for p in "${PROFILES[@]}"; do [ -e "$p" ] || continue
    grep -qsF "$dir" "$p" 2>/dev/null && continue
    printf '\n# cc-dev-team\nexport PATH="%s:$PATH"\n' "$dir" >> "$p"; done
}
fetch() { curl -fsSL $CURLF "$@"; }

ensure_node() {
  [ "$NODE" = 0 ] && { warn "skipping Node install (--no-node)"; return; }
  if have node && [ "$NO_UPDATE" = 1 ]; then ok "node $(node --version)"; return; fi
  if have node && [ "$NO_UPDATE" = 0 ]; then ok "node $(node --version)"; return; fi
  say "Installing Node.js (LTS)"
  if have brew; then brew install node || brew upgrade node || true; return; fi
  local os arch ver file tmp dir b
  case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) warn "auto Node unsupported"; return ;; esac
  case "$(uname -m)" in x86_64|amd64) arch=x64 ;; aarch64|arm64) arch=arm64 ;; *) warn "auto Node unsupported"; return ;; esac
  ver="$(fetch https://nodejs.org/dist/index.json 2>/dev/null | tr '}' '\n' | grep -m1 '"lts":"' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  [ -n "$ver" ] || { warn "could not resolve Node LTS"; return; }
  file="node-${ver}-${os}-${arch}.tar.gz"; tmp="$(mktemp -d)"; mkdir -p "$HOME/.local/bin"
  if fetch "https://nodejs.org/dist/${ver}/${file}" -o "$tmp/node.tgz" && tar -xzf "$tmp/node.tgz" -C "$HOME/.local"; then
    dir="$HOME/.local/${file%.tar.gz}"
    for b in node npm npx; do [ -e "$dir/bin/$b" ] && ln -sf "$dir/bin/$b" "$HOME/.local/bin/$b"; done
    ensure_path "$HOME/.local/bin"; hash -r 2>/dev/null || true
  fi
  rm -rf "$tmp" 2>/dev/null || true
  have node && ok "node $(node --version)" || warn "Node install failed — see https://nodejs.org"
}

ensure_claude() {
  ensure_path "$HOME/.local/bin"
  if have claude && [ "$NO_UPDATE" = 1 ]; then ok "claude present ($(claude --version 2>/dev/null | head -1))"; return; fi
  if have claude; then say "Updating Claude Code"; claude update >/dev/null 2>&1 || true; ok "claude $(claude --version 2>/dev/null | head -1)"; return; fi
  say "Installing Claude Code CLI"
  if fetch https://claude.ai/install.sh | bash; then :; else
    have npm && npm install -g @anthropic-ai/claude-code || warn "Claude Code install failed — see https://docs.claude.com/claude-code"
  fi
  ensure_path "$HOME/.local/bin"; hash -r 2>/dev/null || true
  have claude && ok "claude $(claude --version 2>/dev/null | head -1)" || warn "claude not on PATH yet — open a new shell"
}

# JSON merge into ~/.claude/settings.json (existing values preserved).
merge_settings() {  # merge_settings <<'JSON' ... JSON
  local patch; patch="$(mktemp)"; cat > "$patch"
  mkdir -p "$(dirname "$SETTINGS")"
  node "$ROOT/scripts/merge-json.mjs" "$SETTINGS" "$patch" >/dev/null 2>&1 \
    || warn "settings merge failed (need node) — patch left at $patch"
  rm -f "$patch" 2>/dev/null || true
}
plugin_install() {  # plugin_install <name>
  have claude && claude plugin install "$1@$MARKET" --scope user >/dev/null 2>&1 \
    && ok "plugin $1 installed" || warn "could not auto-install $1 (enable it later with: claude plugin install $1@$MARKET)"
}

# --- external deps ----------------------------------------------------------
install_ctxwire() {
  if have ctx-wire && [ "$NO_UPDATE" = 1 ]; then ok "ctx-wire present"; else
    say "Installing ctx-wire (transparent command-output compression)"
    fetch https://ctx-wire.dev/install.sh | sh || warn "ctx-wire install failed — see https://ctx-wire.dev"
  fi
  ensure_path "$HOME/.local/bin"; hash -r 2>/dev/null || true
  have ctx-wire && { ctx-wire shims install >/dev/null 2>&1 || true; ok "ctx-wire shims installed"; }
}
install_codebase_memory() {
  if have codebase-memory-mcp && [ "$NO_UPDATE" = 1 ]; then ok "codebase-memory-mcp present"; else
    say "Installing codebase-memory-mcp"
    fetch https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash \
      || warn "codebase-memory-mcp install failed — the token-diet MCP server won't start until it's on PATH"
  fi
  ensure_path "$HOME/.local/bin"; hash -r 2>/dev/null || true
  have codebase-memory-mcp && { codebase-memory-mcp config set auto_index true >/dev/null 2>&1 || true; ok "codebase-memory-mcp ready"; }
}
install_pup() {
  if have pup && [ "$NO_UPDATE" = 1 ]; then ok "pup present"; return; fi
  say "Installing the Datadog pup CLI"
  if have brew && brew install datadog-labs/pack/pup 2>/dev/null; then ok "pup (brew)"; return; fi
  local os arch ver tmp
  case "$(uname -s)" in Linux) os=Linux ;; Darwin) os=Darwin ;; *) warn "pup: unsupported OS"; return ;; esac
  case "$(uname -m)" in x86_64|amd64) arch=x86_64 ;; aarch64|arm64) arch=arm64 ;; *) warn "pup: unsupported arch"; return ;; esac
  ver="$(fetch https://api.github.com/repos/DataDog/pup/releases/latest 2>/dev/null | grep -m1 '"tag_name"' | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  [ -n "$ver" ] || { warn "pup: could not resolve latest release — see https://github.com/DataDog/pup"; return; }
  tmp="$(mktemp -d)"; mkdir -p "$HOME/.local/bin"
  if fetch "https://github.com/DataDog/pup/releases/download/${ver}/pup_${ver#v}_${os}_${arch}.tar.gz" -o "$tmp/pup.tgz" \
     && tar -xzf "$tmp/pup.tgz" -C "$tmp"; then
    install -m 0755 "$tmp/pup" "$HOME/.local/bin/pup" 2>/dev/null || { cp "$tmp/pup" "$HOME/.local/bin/pup"; chmod 0755 "$HOME/.local/bin/pup"; }
    ensure_path "$HOME/.local/bin"; hash -r 2>/dev/null || true; ok "pup $ver"
  else warn "pup download failed — see https://github.com/DataDog/pup"; fi
  rm -rf "$tmp" 2>/dev/null || true
}
datadog_auth() {
  have pup || return 0
  if ask "    Authenticate Datadog now via OAuth (pup auth login)?" "Y"; then
    pup auth login || warn "pup auth login failed — you can set DD_API_KEY/DD_APP_KEY/DD_SITE instead"
  else
    local site key app
    site="$(prompt 'DD_SITE (e.g. datadoghq.com / datadoghq.eu; blank to skip)')"
    [ -n "$site" ] && { key="$(prompt 'DD_API_KEY' hidden)"; app="$(prompt 'DD_APP_KEY' hidden)"; }
    if [ -n "${key:-}" ]; then
      mkdir -p "$(dirname "$SECRETS")"; touch "$SECRETS"; chmod 600 "$SECRETS"
      { echo "export DD_SITE=${site}"; echo "export DD_API_KEY=${key}"; echo "export DD_APP_KEY=${app}"; } >> "$SECRETS"
      for p in "${PROFILES[@]}"; do [ -e "$p" ] || continue; grep -qsF "cc-dev-team.env" "$p" || printf '\n[ -f "%s" ] && . "%s"\n' "$SECRETS" "$SECRETS" >> "$p"; done
      ok "Datadog keys saved to $SECRETS (chmod 600, sourced from your profile)"
    fi
  fi
}

bold "cc-dev-team installer"
echo "Marketplace: $ROOT"

# --- 0) prerequisites -------------------------------------------------------
ensure_node
ensure_claude

# --- 1) register the marketplace -------------------------------------------
if have claude; then
  say "Registering marketplace ($MARKET)"
  claude plugin marketplace add "$ROOT" >/dev/null 2>&1 || claude plugin marketplace update "$MARKET" >/dev/null 2>&1 || true
fi

# --- 2) per-plugin / per-dependency prompts --------------------------------
bold "Plugins & dependencies — check each one"
SEL_DEV=0; SEL_TD=0; SEL_DD=0; WIRE_STATUSLINE=0

if ask "[dev-team]  Agentic dev team (/specs → /plan → /build → /pr, 30 agents, gates)?"; then
  SEL_DEV=1; plugin_install dev-team
fi

if ask "[token-diet] Token-reduction toolkit (statusline + skills)?"; then
  SEL_TD=1; plugin_install token-diet
  ask "    └─ [ctx-wire]            transparent command-output compression + secret scrub?" "Y" && install_ctxwire
  ask "    └─ [codebase-memory-mcp] symbol/call-graph MCP (the token-diet .mcp.json server)?" "Y" && install_codebase_memory
  ask "    └─ wire the live cache/cost statusline into settings.json?" "Y" && WIRE_STATUSLINE=1
fi

if ask "[datadog]   Datadog observability via the pup CLI?"; then
  SEL_DD=1; plugin_install datadog
  ask "    └─ [pup] install the Datadog pup CLI now?" "Y" && { install_pup; datadog_auth; }
fi

# --- 3) settings.json (merge, never clobber) -------------------------------
bold "Settings"
say "Merging defaults into $SETTINGS (existing values preserved)"

# Native safety guardrails — these replace the OMP path/destructive guards with
# Claude Code's own permission engine (deny is hard, ask prompts the human).
if [ "$SEL_DEV" = 1 ] || [ "$SEL_TD" = 1 ] || [ "$SEL_DD" = 1 ]; then
  merge_settings <<'JSON'
{
  "permissions": {
    "deny": [
      "Read(./.env)", "Read(./.env.*)", "Read(./**/*.pem)", "Read(./**/*.key)",
      "Read(./**/id_rsa)", "Read(./**/*secret*)", "Read(./**/*credential*)"
    ],
    "ask": [
      "Bash(rm -rf *)", "Bash(git push --force *)", "Bash(git push -f *)",
      "Bash(git reset --hard *)", "Bash(dd *)", "Bash(mkfs *)"
    ]
  }
}
JSON
fi
if [ "$WIRE_STATUSLINE" = 1 ]; then
  TD_DIR="$ROOT/plugins/token-diet"
  patch="$(mktemp)"
  printf '{ "statusLine": { "type": "command", "command": "node \\"%s/statusline/cache-meter.mjs\\"", "padding": 0 } }\n' "$TD_DIR" > "$patch"
  if node -e "const s=require('$SETTINGS');process.exit(s.statusLine?1:0)" 2>/dev/null; then
    warn "you already have a statusLine — leaving it. To use the cache-meter: node $TD_DIR/statusline/cache-meter.mjs"
  else
    node "$ROOT/scripts/merge-json.mjs" "$SETTINGS" "$patch" >/dev/null 2>&1 && ok "cache-meter statusline wired" || warn "statusline merge failed"
  fi
  rm -f "$patch" 2>/dev/null || true
fi
ok "Settings merged"

# --- 4) doctor -------------------------------------------------------------
bold "Doctor"
fail=0
check() { local t="$1" req="$2" vc="${3:-}"; if have "$t"; then local v=""; [ -n "$vc" ] && v="$(eval "$vc" 2>/dev/null | head -1)"; ok "$t ${v:+($v)} -> $(command -v "$t")"; elif [ "$req" = required ]; then warn "$t MISSING (required)"; fail=1; else warn "$t not found (optional)"; fi; }
check git    required    "git --version"
check node   required    "node --version"
check claude required    "claude --version"
[ "$SEL_TD" = 1 ] && { check ctx-wire optional "ctx-wire --version"; check codebase-memory-mcp optional "codebase-memory-mcp --version"; }
[ "$SEL_DD" = 1 ] && check pup optional "pup version"

if have claude; then bold "Plugins"; claude plugin list 2>/dev/null | grep -E "$MARKET|dev-team|token-diet|datadog" | sed 's/^/  /' || true; fi

echo
[ "$fail" = 0 ] && bold "All set ✓" || bold "Finished with warnings — see above"
echo "Open a NEW shell (or 'source ~/.profile'), then run: claude"
[ "$fail" = 0 ] || exit 1
