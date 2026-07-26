#!/usr/bin/env bash
# token-diet installer (Linux/macOS) — v2.0.0, refocused.
# Installs the LATEST ctx-wire + the EN/FR filter pack for the four `dotnet`
# commands OMP's native shellMinimizer does NOT cover (publish, pack, run,
# tool), mirrors the extensions and the always-on rule into ~/.omp/agent, and
# merges config.snippet.yml. caveman ships as an OMP skill.
# NOT installed any more (OMP does it, or it moved):
#   acli / the atlassian skill  -> official remote MCP server, wired by the
#                                  repo-root install.sh
#   ctx7 / the context7 skill   -> official remote MCP server, ditto
#   context-mode                -> OMP's shellMinimizer + artifact spill
#   the OMP status-line fork    -> native statusLine.preset + cost/cache_* segments
# Flags:
#   --no-update          keep tools already installed (don't refresh them)
#   --no-config          don't merge config.snippet.yml into ~/.omp/agent/config.yml
#   --no-cleanup         don't remove obsolete predecessors (codebase-memory-mcp,
#                        CodeGraph, RTK, csharp-ls) from this machine on install
#   --insecure-tls       disable TLS verification for this run (corporate MITM proxy)
#   --ca-file=<path>     use this CA bundle for this run
#   -y, --yes            non-interactive (accepted for parity; nothing prompts)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSECURE_TLS=0; NO_CONFIG=0; NO_UPDATE=0; NO_CLEANUP=0
for a in "$@"; do case "$a" in
  --no-update) NO_UPDATE=1 ;; --insecure-tls) INSECURE_TLS=1 ;; --ca-file=*) CA_FILE="${a#*=}" ;;
  --no-config) NO_CONFIG=1 ;;
  --no-cleanup) NO_CLEANUP=1 ;;
  # Accepted for parity with the other per-plugin installers (the repo-root
  # install.sh passes it through) — nothing in here prompts any more, so it is
  # deliberately a no-op rather than a variable nobody reads.
  -y|--yes) ;;
  -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
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
# then codebase-memory-mcp), before ctx-wire, RTK, and a csharp-ls LSP for C#
# semantics. Those are gone now — C# navigation and semantics (definition,
# references, hover, symbols, rename, code actions) go through OMP's native
# `lsp` tool, which ships `omnisharp` as a built-in default for `.cs`/`.csx`
# (omp packages/coding-agent/src/lsp/defaults.json), and ctx-wire
# replaced RTK. But an upgrade/uninstall does NOT remove what a past install
# left on the machine (an OMP mcp.json entry + a leftover binary that keeps a
# dead MCP server wired, or a global csharp-ls dotnet tool + lsp.json entry).
# This step reverses that: it unregisters the obsolete MCP servers from OMP's
# mcp.json, uninstalls the obsolete csharp-ls dotnet tool + its lsp.json entry,
# and removes the leftover binaries/caches. Idempotent, existence-guarded,
# fail-open, and it only ever touches these exact obsolete names. Skip with
# --no-cleanup.
cleanup_obsolete() {
  [ "${NO_CLEANUP:-0}" = 1 ] && return 0
  say "Cleaning up obsolete tools (codebase-memory-mcp, CodeGraph, RTK, csharp-ls)"
  local removed=0 mcp="$HOME/.omp/agent/mcp.json" lsp b d

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

  # 4) Uninstall the obsolete csharp-ls dotnet tool + its lsp.json entry —
  # C# semantics now come from OMP's native `lsp` tool + omnisharp, so a stale
  # csharp-ls entry in lsp.json only competes with it.
  if have dotnet && dotnet tool list -g 2>/dev/null | grep -qi '^csharp-ls\b'; then
    run "dotnet tool uninstall -g csharp-ls || true"
    say "  uninstalled csharp-ls (dotnet tool)"; removed=1
  fi
  lsp="$HOME/.omp/agent/lsp.json"
  if [ -f "$lsp" ]; then
    if have python3; then
      python3 - "$lsp" <<'PY' || true
import json,os,sys
p=sys.argv[1]
try:
    cfg=json.load(open(p))
except Exception:
    sys.exit(0)
srv=cfg.get("servers") or {}
if "csharp-ls" in srv:
    srv.pop("csharp-ls",None)
    if srv:
        cfg["servers"]=srv
        json.dump(cfg,open(p,"w"),indent=2); open(p,"a").write("\n")
    else:
        os.remove(p)
    print("  removed csharp-ls from lsp.json")
PY
    else
      warn "  python3 not found — remove any csharp-ls entry from $lsp by hand"
    fi
  fi

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
  # Four filters only. git status / dotnet build / test / restore are covered by
  # OMP's own Rust shellMinimizer (crates/pi-shell/src/minimizer/filters/git.rs
  # and dotnet.rs, on by default), so shipping our own would be duplicate work
  # on the same bytes. publish / pack / run / tool are NOT in dotnet.rs's
  # `supports()` list — those are the ones left to us.
  say "Installing ctx-wire filters (EN+FR: dotnet publish/pack/run/tool)"
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

# --- OMP config: skills, provider isolation ---------------------------------
CFG="$HOME/.omp/agent/config.yml"
if [ "$NO_CONFIG" = 0 ]; then
  mkdir -p "$(dirname "$CFG")"; touch "$CFG"
  . "$HERE/../../scripts/lib/cfg.sh"
  cfg_add_snippet "$HERE/config.snippet.yml" token-diet
fi

# --- Load the context-transform extensions ----------------------------------
if [ -d "$HERE/extensions" ]; then
  DEST="$HOME/.omp/agent/extensions/token-diet"
  rm -rf "$DEST"; mkdir -p "$DEST"; cp -R "$HERE/extensions" "$DEST/"
  [ -f "$HERE/package.json" ] && cp "$HERE/package.json" "$DEST/"
  say "extensions loaded: path-inject (always on) + context-compress (OFF unless TOKEN_DIET_CONTEXT_COMPRESS=safe|lite|full)"
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

# --- Cost / cache visibility: use OMP's own statusline, not a harness fork ----
# v1.x patched OMP's own status-line component.ts and re-ran `bun build` on
# dist/cli.js to inline a cost/cache footer. That fork is gone: its render()
# anchor stopped matching current OMP, the embedded python then exited 1, and
# under `set -euo pipefail` that aborted this whole installer. OMP ships the
# same numbers as first-class statusline segments — verified in
# omp packages/coding-agent/src/modes/components/status-line/segments.ts
# (`cost` :433, `context_pct` :454, `cache_read` :541, `cache_write` :553,
# `cache_hit` :565, `usage` :635) — so this is config, not a patch.
say "Cost + prompt-cache visibility is native. In ~/.omp/agent/config.yml:"
cat <<'HINT'
    statusLine:
      preset: custom
      rightSegments: [cost, cache_hit, cache_write, context_pct, usage]
HINT

# OMP's bash tool caches a shell session's PATH for the life of the OMP
# process (the failure mode that broke the old RTK integration): a
# ~/.local/bin binary is only as good as the PATH the
# consuming process was started with. Detect staleness now, for every tool
# this installer can newly land, from a FRESH login shell (bash -l) — the
# same invocation OMP's bash tool uses — rather than trusting this script's
# own already-exported PATH. (extensions/path-inject.ts closes the same gap
# from inside the OMP process; this probe is the user-facing warning.)
STALE_TOOLS=""
for t in ctx-wire ast-grep; do
  have "$t" && ! bash -lc "command -v $t" >/dev/null 2>&1 && STALE_TOOLS="$STALE_TOOLS $t"
done
if [ -n "$STALE_TOOLS" ]; then
  warn "installed but NOT visible in a fresh shell yet:$STALE_TOOLS. An already-running OMP process keeps missing them until you RESTART OMP — re-running this script again will not fix it."
fi
say "token-diet active: ctx-wire shims, dotnet publish/pack/run/tool filters (EN+FR), ast-grep, provider isolation, /caveman. Restart omp."
