#!/usr/bin/env bash
# token-diet installer (Linux/macOS) — installs the LATEST ctx-wire. caveman/yagni
# ship as OMP skills. Also sets up the acli (Atlassian CLI), ast-grep, the .NET SDK +
# csharp-ls LSP, and the ctx7 docs CLI. Everything is refreshed to latest by default.
# (Symbolic C# navigation/edit is provided by the dev-team plugin's serena-forge
# integration, not token-diet.)
# Flags:
#   --no-update          keep tools already installed (don't refresh them)
#   --no-config          don't enable the bundled skills in ~/.omp/agent/config.yml
#   --no-context-mode    don't install the context-mode OMP plugin
#   --no-acli            don't install / authenticate the Atlassian CLI (acli)
#   --no-cleanup         don't remove obsolete predecessors (codebase-memory-mcp,
#                        CodeGraph, RTK) from this machine on install
#   ACLI_SITE/ACLI_EMAIL/ACLI_TOKEN (env)  non-interactive acli auth (auto-run
#                        on install when acli isn't already authenticated)
#   -y, --yes            non-interactive (don't prompt for auth)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YES=0; INSECURE_TLS=0; NO_CONFIG=0; NO_CTXMODE=0; NO_ACLI=0; NO_UPDATE=0; NO_CLEANUP=0
for a in "$@"; do case "$a" in
  --no-update) NO_UPDATE=1 ;; -y|--yes) YES=1 ;; --insecure-tls) INSECURE_TLS=1 ;; --ca-file=*) CA_FILE="${a#*=}" ;;
  --no-config) NO_CONFIG=1 ;;
  --no-context-mode) NO_CTXMODE=1 ;;
  --no-acli) NO_ACLI=1 ;;
  --no-cleanup) NO_CLEANUP=1 ;;
  -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { eval "$@"; }
PROFILES=("$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc")
ensure_path() {  # add $1 to PATH in this session + persist to shell profiles (idempotent)
  local dir="$1" p
  [ -d "$dir" ] || return 0
  case ":$PATH:" in *":$dir:"*) ;; *) PATH="$dir:$PATH"; export PATH ;; esac
  [ -e "$HOME/.profile" ] || : > "$HOME/.profile"
  for p in "${PROFILES[@]}"; do
    [ -e "$p" ] || continue
    grep -qsF "$dir" "$p" 2>/dev/null && continue
    printf '\n# omp-dev-team\nexport PATH="%s:$PATH"\n' "$dir" >> "$p"
  done
}
# Corporate TLS-intercepting proxy (Zscaler / Trend Micro under WSL): opt-in bypass.
enable_insecure_tls() {
  warn "Insecure TLS: certificate verification DISABLED for this run (corporate MITM proxy)."
  export GIT_SSL_NO_VERIFY=true NODE_TLS_REJECT_UNAUTHORIZED=0 NPM_CONFIG_STRICT_SSL=false \
         RUSTUP_USE_CURL=1 CARGO_HTTP_CHECK_REVOKE=false OMP_INSECURE_TLS=1
  local d; d="$(mktemp -d 2>/dev/null || echo "/tmp/omp-tls.$$")"; mkdir -p "$d"
  printf 'insecure\n' > "$d/.curlrc"; printf 'check_certificate = off\n' > "$d/.wgetrc"
  export CURL_HOME="$d" WGETRC="$d/.wgetrc"
}
{ [ "${INSECURE_TLS:-0}" = 1 ] || [ -n "${OMP_INSECURE_TLS:-}" ]; } && enable_insecure_tls
CA_FILE="${CA_FILE:-${OMP_CA_FILE:-}}"
if [ -n "$CA_FILE" ] && [ -f "$CA_FILE" ]; then
  export OMP_CA_FILE="$CA_FILE" NODE_EXTRA_CA_CERTS="$CA_FILE" SSL_CERT_FILE="$CA_FILE" CURL_CA_BUNDLE="$CA_FILE" GIT_SSL_CAINFO="$CA_FILE" REQUESTS_CA_BUNDLE="$CA_FILE"
fi

case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

# --- Clean up obsolete predecessors on (re)install --------------------------
# Earlier token-diet versions installed a code-graph MCP server (first CodeGraph,
# then codebase-memory-mcp) and, before ctx-wire, RTK. Those are gone now — the
# symbolic C# code intelligence moved to the dev-team plugin's serena-forge
# integration, and ctx-wire replaced RTK. But an upgrade/uninstall does NOT remove
# what a past install left on the machine (an OMP mcp.json entry + a leftover
# binary that keeps a dead MCP server wired). This step reverses that: it
# unregisters the obsolete MCP servers from OMP's mcp.json and removes the
# leftover binaries/caches. Idempotent, existence-guarded, fail-open, and it only
# ever touches these exact obsolete names. Skip with --no-cleanup.
cleanup_obsolete() {
  [ "${NO_CLEANUP:-0}" = 1 ] && return 0
  say "Cleaning up obsolete tools (codebase-memory-mcp, CodeGraph, RTK)"
  local removed=0 mcp="$HOME/.omp/agent/mcp.json" b d

  # 1) Unregister the obsolete MCP servers from OMP's mcp.json.
  if [ -f "$mcp" ]; then
    if have python3; then
      python3 - "$mcp" <<'PY' || true
import json,sys
p=sys.argv[1]
try:
    cfg=json.load(open(p))
except Exception:
    sys.exit(0)
srv=cfg.get("mcpServers") or {}
gone=[k for k in ("codebase-memory","codebase-memory-mcp","codegraph","code-graph") if k in srv]
for k in gone: srv.pop(k,None)
if gone:
    cfg["mcpServers"]=srv
    json.dump(cfg,open(p,"w"),indent=2); open(p,"a").write("\n")
    print("  unregistered MCP server(s): "+", ".join(gone))
PY
    else
      warn "  python3 not found — remove any codebase-memory-mcp/codegraph entry from $mcp by hand"
    fi
  fi

  # 2) Remove leftover binaries (exact names only, existence-guarded).
  for b in codebase-memory-mcp codegraph rtk; do
    for d in "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.bun/bin"; do
      if [ -e "$d/$b" ] || [ -L "$d/$b" ]; then
        rm -f "$d/$b" 2>/dev/null || true
        say "  removed $d/$b"; removed=1
      fi
    done
  done

  # 3) Remove obsolete global data/cache dirs (exact tool-named dirs only).
  for d in "$HOME/.codegraph" "$HOME/.codebase-memory-mcp" \
           "$HOME/.cache/codebase-memory-mcp" "$HOME/.local/share/codebase-memory-mcp"; do
    if [ -d "$d" ]; then
      rm -rf "$d" 2>/dev/null || true
      say "  removed $d"; removed=1
    fi
  done

  if [ "$removed" = 0 ]; then say "  nothing obsolete found (already clean)"; fi
  return 0
}
cleanup_obsolete

# --- ctx-wire (transparent command-output compression + secret scrubbing) ----
if have ctx-wire && [ "$NO_UPDATE" = 1 ]; then
  say "ctx-wire present"
elif have ctx-wire; then
  say "Updating ctx-wire"; run "ctx-wire update || true"
else
  say "Installing latest ctx-wire"
  if have curl; then run "curl -fsSL https://ctx-wire.dev/install.sh | sh || true"
  else warn "need curl to install ctx-wire — see https://ctx-wire.dev"; fi
fi
# Wire it into the command path TRANSPARENTLY via PATH shims in ~/.local/bin.
if have ctx-wire; then run "ctx-wire shims install || true"; fi

# --- Multilingual ctx-wire filters (EN+FR) -----------------------------------
PACK_DIR="$HERE/ctx-wire/filters.d"
CTXW_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ctx-wire"
CTXW_FILTERS="$CTXW_DIR/filters.toml"
BLOCK_BEGIN="# >>> token-diet multilingual filters (managed) >>>"
BLOCK_END="# <<< token-diet multilingual filters (managed) <<<"
if [ -d "$PACK_DIR" ]; then
  say "Installing multilingual ctx-wire filters (EN+FR: git-status + dotnet build/test/restore/run/tool)"
  mkdir -p "$CTXW_DIR"
  blk="$(mktemp)"; tmp="$(mktemp)"
  printf '%s\n' "$BLOCK_BEGIN" > "$blk"
  for f in "$PACK_DIR"/*.toml; do awk '/^schema_version[[:space:]]*=/{next} {print}' "$f" >> "$blk"; printf '\n' >> "$blk"; done
  printf '%s\n' "$BLOCK_END" >> "$blk"
  if [ -f "$CTXW_FILTERS" ]; then
    awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" 'index($0,b){skip=1;next} index($0,e){skip=0;next} !skip{print}' "$CTXW_FILTERS" > "$tmp"
  fi
  if ! grep -q '^schema_version' "$tmp" 2>/dev/null; then printf 'schema_version = 1\n' | cat - "$tmp" > "$tmp.h" && mv "$tmp.h" "$tmp"; fi
  printf '\n' >> "$tmp"; cat "$blk" >> "$tmp"
  mv "$tmp" "$CTXW_FILTERS"; rm -f "$blk"
  if have ctx-wire; then run "ctx-wire verify || true"
  elif have python3; then run "python3 '$HERE/ctx-wire/scripts/verify-filters.py' '$PACK_DIR' || true"; fi
fi

# --- Patch helpers (idempotent; re-applied after each context-mode / OMP update) ---

# Fix: OMP plugin onLoad interceptor forces the 'js' loader on ALL deps including
# .json files, which Bun's JS parser rejects (7 parse errors). Proxy the JSON
# catalog as a valid ESM module and patch the import in pricing.js.
patch_context_mode() {
  local CM_DIR="${OMP_HOME:-$HOME/.omp}/plugins/node_modules/context-mode"
  local PRICING="$CM_DIR/build/session/pricing.js"
  local JSON_SRC="$CM_DIR/build/session/model-prices.json"
  local JS_PROXY="$CM_DIR/build/session/model-prices-catalog.js"
  [ -f "$PRICING" ] && [ -f "$JSON_SRC" ] || return 0
  grep -q 'model-prices-catalog' "$PRICING" 2>/dev/null && return 0   # already patched
  if have python3; then
    python3 - "$JSON_SRC" "$JS_PROXY" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
open(sys.argv[2], 'w').write(
  '// OMP plugin onLoad forces js loader on all deps — proxy JSON as valid ESM.\n'
  'export default ' + json.dumps(data, indent=2) + ';\n')
PYEOF
  elif have node; then
    node -e "const fs=require('fs');const d=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));
fs.writeFileSync(process.argv[2],'// OMP plugin onLoad forces js loader on all deps — proxy JSON as valid ESM.\nexport default '+JSON.stringify(d,null,2)+';\n');" \
      "$JSON_SRC" "$JS_PROXY"
  else warn "context-mode patch: need python3 or node — skip"; return 0; fi
  sed -i 's|import catalog from "./model-prices.json" with { type: "json" };|import catalog from "./model-prices-catalog.js";|' "$PRICING"
  say "context-mode: patched JSON loader compatibility (model-prices-catalog.js)"
}

# Fix: OMP renders hook statuses (ctx.ui.setStatus) as a separate line below the
# status bar. Patch StatusLineComponent to include them inline in the top border.
patch_omp_status_line() {
  local OMP_PKG="$HOME/.bun/install/global/node_modules/@oh-my-pi/pi-coding-agent"
  local COMPONENT="$OMP_PKG/src/modes/components/status-line/component.ts"
  [ -f "$COMPONENT" ] || { warn "OMP status-line patch: component.ts not found — skip"; return 0; }
  grep -q 'hookText' "$COMPONENT" 2>/dev/null && return 0   # already patched
  python3 - "$COMPONENT" <<'PYEOF'
import sys, re
src = open(sys.argv[1]).read()
# 1. Inject hook statuses into rightParts right after the subagentBadge block.
ANCHOR = '\t\tif (subagentBadge) {\n\t\t\trightParts.unshift(subagentBadge);\n\t\t}'
INJECT = (
  '\n\t\tconst showHooks = this.#settings.showHookStatus ?? true;\n'
  '\t\tif (showHooks && this.#hookStatuses.size > 0) {\n'
  '\t\t\tconst hookText = Array.from(this.#hookStatuses.entries())\n'
  '\t\t\t\t.sort(([a], [b]) => a.localeCompare(b))\n'
  '\t\t\t\t.map(([, text]) => sanitizeStatusText(text))\n'
  '\t\t\t\t.join(" ")\n'
  '\t\t\t\t.trim();\n'
  '\t\t\tif (hookText) rightParts.push(theme.fg("muted", hookText));\n'
  '\t\t}'
)
if ANCHOR not in src:
  print('ERROR: anchor not found in component.ts', file=sys.stderr); sys.exit(1)
src = src.replace(ANCHOR, ANCHOR + INJECT, 1)
# 2. Replace render() body — drop the separate hook line.
OLD_RENDER = (
  '\trender(width: number): readonly string[] {\n'
  '\t\t// Only render hook statuses - main status is in editor\'s top border\n'
  '\t\tconst showHooks = this.#settings.showHookStatus ?? true;\n'
  '\t\tif (!showHooks || this.#hookStatuses.size === 0) {\n'
  '\t\t\treturn [];\n'
  '\t\t}\n\n'
  '\t\tconst sortedStatuses = Array.from(this.#hookStatuses.entries())\n'
  '\t\t\t.sort(([a], [b]) => a.localeCompare(b))\n'
  '\t\t\t.map(([, text]) => sanitizeStatusText(text));\n'
  '\t\tconst hookLine = sortedStatuses.join(" ");\n'
  '\t\treturn [truncateToWidth(hookLine, width)];\n'
  '\t}'
)
NEW_RENDER = (
  '\trender(_width: number): readonly string[] {\n'
  '\t\t// Hook statuses are rendered inline in the top-border status line.\n'
  '\t\treturn [];\n'
  '\t}'
)
if OLD_RENDER not in src:
  print('ERROR: render() original body not found in component.ts', file=sys.stderr); sys.exit(1)
src = src.replace(OLD_RENDER, NEW_RENDER, 1)
open(sys.argv[1], 'w').write(src)
print('patched')
PYEOF
  [ $? -ne 0 ] && { warn "OMP status-line patch: python script failed — skip rebuild"; return 0; }
  # Rebuild dist/cli.js with the same flags used by bundle-dist.ts
  say "OMP status-line: rebuilding dist/cli.js…"
  (cd "$OMP_PKG" && bun build \
    --target=bun --outdir dist --minify --keep-names \
    --external mupdf --external @oh-my-pi/pi-natives \
    --external "@huggingface/transformers" --external fastembed \
    --external onnxruntime-node --external puppeteer-core \
    --external "@puppeteer/browsers" --external "@babel/parser" \
    --external "@xterm/headless" --external turndown \
    --external turndown-plugin-gfm --external "@mozilla/readability" \
    --external linkedom --external "@agentclientprotocol/sdk" \
    --define 'process.env.PI_BUNDLED="true"' \
    ./src/cli.ts 2>/dev/null) \
  && say "OMP status-line: hook statuses now inline in top-border (rebuilt dist/cli.js)" \
  || warn "OMP status-line: bun build failed — OMP may need a manual reinstall"
}

# --- context-mode (locale-agnostic output sandbox; complements ctx-wire) ------
if [ "$NO_CTXMODE" = 0 ]; then
  if have omp; then
    say "Installing context-mode OMP plugin (locale-agnostic output sandbox + session continuity)"
    if ! run "omp plugin install context-mode"; then
      warn "omp plugin install failed (not in registry yet?) — falling back to ~/.omp/plugins"
      OMP_PLUGINS="${OMP_HOME:-$HOME/.omp}/plugins"
      mkdir -p "$OMP_PLUGINS"
      [ -f "$OMP_PLUGINS/package.json" ] || printf '{\n  "dependencies": {}\n}\n' > "$OMP_PLUGINS/package.json"
      if have bun;   then run "(cd '$OMP_PLUGINS' && bun add context-mode) || true"
      elif have npm; then run "(cd '$OMP_PLUGINS' && npm install context-mode) || true"
      else warn "need bun or npm to install context-mode — see https://github.com/mksglu/context-mode"; fi
    fi
  else
    warn "omp CLI not found — skip context-mode (run later: omp plugin install context-mode)"
  fi
fi
patch_context_mode

# --- acli (official Atlassian CLI: Jira / Confluence / Bitbucket) -------------
# acli is our GO-TO for Atlassian — not an MCP. The URL serves the LATEST build,
# so re-running updates it. Installs to ~/.local/bin (no sudo). When interactive
# (and not already authenticated) it offers to run `acli jira auth login`.
if [ "$NO_ACLI" = 0 ]; then
  if have acli && [ "$NO_UPDATE" = 1 ]; then
    say "acli present"
  else
    say "Installing Atlassian CLI (acli)"
    if have curl; then
      ACLI_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"   # linux | darwin
      case "$(uname -m)" in x86_64|amd64) ACLI_ARCH=amd64 ;; arm64|aarch64) ACLI_ARCH=arm64 ;; *) ACLI_ARCH=amd64 ;; esac
      ACLI_URL="https://acli.atlassian.com/${ACLI_OS}/latest/acli_${ACLI_OS}_${ACLI_ARCH}/acli"
      run "mkdir -p \"$HOME/.local/bin\" && curl -fsSL -o \"$HOME/.local/bin/acli\" \"$ACLI_URL\" && chmod +x \"$HOME/.local/bin/acli\" || true"
    else warn "need curl to install acli — see https://developer.atlassian.com/cloud/acli/"; fi
  fi
  # Authenticate (Jira) when not already logged in — runs automatically (no
  # Y/n gate); non-interactive installs can supply ACLI_SITE/ACLI_EMAIL/ACLI_TOKEN.
  if have acli && ! acli jira auth status >/dev/null 2>&1; then
    if [ -n "${ACLI_SITE:-}" ] && [ -n "${ACLI_EMAIL:-}" ] && [ -n "${ACLI_TOKEN:-}" ]; then
      printf '%s' "$ACLI_TOKEN" | acli jira auth login --site "$ACLI_SITE" --email "$ACLI_EMAIL" --token >/dev/null 2>&1 \
        && echo "  acli authenticated ($ACLI_SITE)" || warn "acli auth failed — run 'acli jira auth login' manually."
    elif [ "$YES" = 0 ] && [ -r /dev/tty ]; then
      say "Authenticating acli (Jira/Confluence)"
      printf '    Atlassian site (e.g. mysite.atlassian.net): '; read -r ACLI_SITE </dev/tty || ACLI_SITE=""
      printf '    Email: '; read -r ACLI_EMAIL </dev/tty || ACLI_EMAIL=""
      printf '    API token (hidden; id.atlassian.com -> Security -> API tokens): '; read -r -s ACLI_TOKEN </dev/tty || ACLI_TOKEN=""; echo
      if [ -n "$ACLI_SITE" ] && [ -n "$ACLI_EMAIL" ] && [ -n "$ACLI_TOKEN" ]; then
        printf '%s' "$ACLI_TOKEN" | acli jira auth login --site "$ACLI_SITE" --email "$ACLI_EMAIL" --token >/dev/null 2>&1 \
          && echo "  acli authenticated ($ACLI_SITE)" || warn "acli auth failed — run 'acli jira auth login' manually."
      else warn "incomplete input — run 'acli jira auth login' manually."; fi
    else
      warn "acli not authenticated — set ACLI_SITE/ACLI_EMAIL/ACLI_TOKEN, or run 'acli jira auth login' manually."
    fi
  fi
fi

# --- ast-grep (structural search/rewrite) -----------------------------------
if have ast-grep && [ "$NO_UPDATE" = 1 ]; then
  say "ast-grep present"
elif have brew; then
  say "Installing ast-grep (brew)"; run "brew install ast-grep || brew upgrade ast-grep || true"
elif have npm; then
  say "Installing ast-grep (npm @ast-grep/cli)"; run "npm install -g @ast-grep/cli || true"
else
  warn "need npm or brew to install ast-grep — see https://ast-grep.github.io"
fi

# --- .NET SDK (official MS script) + csharp-ls (C# LSP) ----------------------
# Install the .NET SDK with Microsoft's official no-sudo script so the C# LSP
# works out of the box, then install csharp-ls as a global tool.
if ! have dotnet; then
  if have brew; then say "Installing .NET SDK (brew)"; run "brew install --cask dotnet-sdk || brew install dotnet || true"
  elif have curl; then
    say "Installing .NET SDK (LTS) via the official Microsoft script"
    run "curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && bash /tmp/dotnet-install.sh --channel LTS --install-dir \"$HOME/.dotnet\" || true"
    rm -f /tmp/dotnet-install.sh 2>/dev/null || true
  else warn "need curl or brew to install the .NET SDK — see https://dot.net"; fi
  export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"
  for p in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -e "$p" ] || continue
    grep -qsF 'DOTNET_ROOT' "$p" || printf '\n# omp-dev-team .NET\nexport DOTNET_ROOT="$HOME/.dotnet"\nexport PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"\n' >> "$p"
  done
  hash -r 2>/dev/null || true
fi
if have dotnet; then
  if have csharp-ls && [ "$NO_UPDATE" = 1 ]; then say "csharp-ls present"
  elif have csharp-ls; then say "Updating csharp-ls"; run "dotnet tool update -g csharp-ls || true"
  else say "Installing csharp-ls (.NET C# language server)"; run "dotnet tool install -g csharp-ls || true"; fi
  ensure_path "$HOME/.dotnet/tools"; hash -r 2>/dev/null || true
else
  warn "dotnet not found — skipping csharp-ls (C# LSP)"
fi

# --- ctx7 CLI (context7 library documentation) ------------------------------
if have npm; then
  if have ctx7 && [ "$NO_UPDATE" = 1 ]; then say "ctx7 CLI present"
  else say "Installing ctx7 CLI (context7 library documentation)"; run "npm install -g ctx7 || true"; fi
else
  warn "npm not found — ctx7 unavailable (install Node.js to enable library docs)"
fi

# --- OMP config: skills, provider isolation, csharp-ls LSP ------------------
CFG="$HOME/.omp/agent/config.yml"
if [ "$NO_CONFIG" = 0 ]; then
  mkdir -p "$(dirname "$CFG")"; touch "$CFG"
  if grep -q "token-diet config" "$CFG" 2>/dev/null; then say "token-diet config already in $CFG"
  else { echo ""; cat "$HERE/config.snippet.yml"; } >> "$CFG"; say "Applied token-diet config to $CFG"; fi
  if ! grep -q "disabledProviders" "$CFG" 2>/dev/null; then
    # Keep this list identical to install.sh's write_config (github intentionally
    # omitted) so the global and standalone install paths never disagree.
    printf '\ndisabledProviders:\n  - claude-plugins\n  - codex\n  - gemini\n  - cursor\n  - windsurf\n  - opencode\n  - cline\n' >> "$CFG"
  fi
fi

# --- csharp-ls LSP config ---------------------------------------------------
LSP="$HOME/.omp/agent/lsp.json"
if have csharp-ls && [ "$NO_CONFIG" = 0 ] && [ ! -f "$LSP" ]; then
  say "Writing csharp-ls LSP config to $LSP"
  mkdir -p "$(dirname "$LSP")"
  printf '{\n  "servers": {\n    "csharp-ls": {\n      "command": "csharp-ls",\n      "fileTypes": [".cs", ".csx"],\n      "rootMarkers": ["*.sln", "*.slnx", "*.csproj", ".git"]\n    }\n  }\n}\n' > "$LSP"
fi

# --- Load the context-transform extensions ----------------------------------
if [ -d "$HERE/extensions" ]; then
  DEST="$HOME/.omp/agent/extensions/token-diet"
  rm -rf "$DEST"; mkdir -p "$DEST"; cp -R "$HERE/extensions" "$DEST/"
  [ -f "$HERE/package.json" ] && cp "$HERE/package.json" "$DEST/"
  say "read-dedup + context-dedup + context-compress (safe) loaded"
fi

# --- Load the always-on OMP-native rule (ctx-wire token-tool routing) ---
# NOTE: OMP's omp-plugins rule provider only discovers rules/*.md inside
# *configured* extension package roots (extensions:/-e/npm-linked) — a bare
# marketplace install of this plugin is NOT one, so rules/token-tools.md would
# silently never load (same gap the extensions/ mirror above works around).
# Copy it into ~/.omp/agent/rules, which the native provider (priority 100)
# always scans, namespaced so it never collides with another plugin's rule.
if [ -d "$HERE/rules" ]; then
  RULES_DEST="$HOME/.omp/agent/rules"
  mkdir -p "$RULES_DEST"
  for f in "$HERE"/rules/*.md; do
    [ -e "$f" ] || continue
    cp "$f" "$RULES_DEST/token-diet-$(basename "$f")"
  done
  say "token-tools rule installed to $RULES_DEST (native, always-on)"
fi

# --- Heads-up: OMP context-file precedence -----------------------------------
# OMP reads ONE context file at user scope: native ~/.omp/agent/AGENTS.md
# (priority 100) if present, else ~/.claude/CLAUDE.md (priority 80, verbatim).
# A CLAUDE.md may carry Claude-Code-only advice (e.g. its own ctx-wire block
# telling the agent to prefer raw shell over built-in tools — correct for
# Claude Code, wrong for OMP, which already routes through read/grep/glob and
# this plugin's own token-tools rule). OMP inherits that by accident, not
# design, whenever no native AGENTS.md exists yet.
if [ "$NO_CONFIG" = 0 ] && [ -f "$HOME/.claude/CLAUDE.md" ] && [ ! -f "$HOME/.omp/agent/AGENTS.md" ]; then
  warn "no ~/.omp/agent/AGENTS.md — OMP falls back to reading ~/.claude/CLAUDE.md verbatim, including any Claude-Code-only guidance (e.g. 'prefer shell over built-in tools'). Consider a native AGENTS.md with just the conventions that apply to OMP."
fi

patch_omp_status_line
# OMP's bash tool caches a shell session's PATH for the life of the OMP
# process (the failure mode that broke the old RTK integration): a
# ~/.local/bin / ~/.dotnet/tools binary is only as good as the PATH the
# consuming process was started with. Detect staleness now, for every tool
# this installer can newly land, from a FRESH login shell (bash -l) — the
# same invocation OMP's bash tool uses — rather than trusting this script's
# own already-exported PATH.
STALE_TOOLS=""
for t in ctx-wire acli ast-grep csharp-ls dotnet ctx7; do
  have "$t" && ! bash -lc "command -v $t" >/dev/null 2>&1 && STALE_TOOLS="$STALE_TOOLS $t"
done
if [ -n "$STALE_TOOLS" ]; then
  warn "installed but NOT visible in a fresh shell yet:$STALE_TOOLS. An already-running OMP process keeps missing them until you RESTART OMP — re-running this script again will not fix it."
fi
say "token-diet active: ctx-wire shims, EN+FR filters, context-mode, ast-grep, .NET/csharp-ls LSP, ctx7, acli, provider isolation, /caveman + /yagni. Restart omp."
