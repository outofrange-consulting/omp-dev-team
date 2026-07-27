#!/usr/bin/env bash
# token-diet installer (Linux/macOS) — v3.0.0.
#
# Installs lean-ctx (https://github.com/yvgude/lean-ctx, MIT) and registers its
# Pi extension so OMP routes bash/read/grep/find/ls through it.
#
# WHY lean-ctx AND NOT ctx-wire ANY MORE
# ctx-wire compressed COMMAND OUTPUT only, and this plugin carried a hand-written
# TOML filter pack for the four `dotnet` commands OMP's native shellMinimizer does
# not cover. lean-ctx supersedes that whole approach: it compresses command output
# AND file reads, search results and project context, recognises 75+ tools out of
# the box, and keeps a persistent session cache so an unchanged re-read costs a
# handful of tokens. Maintaining our own filter pack alongside it would be the
# same "duplicate what the tool already does" mistake this repo keeps correcting.
#
# Flags: --no-update, --no-config, -y (all optional).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NO_UPDATE=0; NO_CONFIG=0
for a in "$@"; do case "$a" in
  --no-update) NO_UPDATE=1 ;; --no-config) NO_CONFIG=1 ;; -y|--yes) ;;
  --insecure-tls|--ca-file=*) ;;
  -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { eval "$@"; }

BIN_DIR="$HOME/.local/bin"; mkdir -p "$BIN_DIR"

# --- lean-ctx ---------------------------------------------------------------
# NON-FATAL by design. lean-ctx is an accelerator: the caveman skill and the
# path-inject extension work without it, so a transient fetch failure must never
# abort an install. Its installer resolves the latest release through the
# UNAUTHENTICATED GitHub API (60 req/hour PER IP), which any shared egress IP —
# CI runner pool, corporate NAT — exhausts. Forward a token when we have one.
if have lean-ctx && [ "$NO_UPDATE" = 1 ]; then
  ok "lean-ctx present ($(lean-ctx --version 2>/dev/null | head -1))"
else
  say "Installing/updating lean-ctx"
  tok="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  [ -n "$tok" ] && export GITHUB_TOKEN="$tok" GH_TOKEN="$tok"
  if have brew; then run "brew tap yvgude/lean-ctx >/dev/null 2>&1 && brew install lean-ctx || true"
  elif have curl;  then run "curl -fsSL https://leanctx.com/install.sh | sh || true"
  elif have npm;   then run "npm install -g lean-ctx-bin || true"
  else warn "no brew/curl/npm — install lean-ctx by hand: https://leanctx.com"; fi
  if have lean-ctx; then ok "lean-ctx ($(lean-ctx --version 2>/dev/null | head -1))"
  else
    warn "lean-ctx not installed (often GitHub's anonymous API limit: 60/hour per IP)."
    warn "Retry later:  curl -fsSL https://leanctx.com/install.sh | sh"
    warn "Continuing — the skill and the PATH extension do not depend on it."
  fi
fi

# --- the OMP extension that routes tools through lean-ctx --------------------
# pi-lean-ctx is published for the Pi coding agent and declares `pi.extensions`,
# which OMP still accepts in package manifests (omp docs/extension-loading.md:42,
# 142). It has ZERO dependencies and uses only APIs OMP implements (pi.exec,
# pi.on, pi.registerCommand, pi.getActiveTools, pi.setActiveTools), so it loads
# unchanged — we mirror the npm package into OMP's native extension dir rather
# than vendoring a copy that would rot.
if [ "$NO_CONFIG" = 0 ] && have npm; then
  DEST="$HOME/.omp/agent/extensions"
  say "Installing the pi-lean-ctx extension into $DEST"
  mkdir -p "$DEST"
  tmp="$(mktemp -d)"
  if (cd "$tmp" && npm pack pi-lean-ctx --silent >/dev/null 2>&1) && tar -xzf "$tmp"/pi-lean-ctx-*.tgz -C "$tmp" 2>/dev/null; then
    rm -rf "$DEST/pi-lean-ctx"; mv "$tmp/package" "$DEST/pi-lean-ctx"
    ok "pi-lean-ctx $(python3 -c "import json;print(json.load(open('$DEST/pi-lean-ctx/package.json'))['version'])" 2>/dev/null || echo installed)"
    # Its config resolver hardcodes ~/.pi (config.ts). OMP's home is ~/.omp, so
    # write the config where the extension will actually look for it.
    mkdir -p "$HOME/.pi/agent/extensions/pi-lean-ctx"
    [ -f "$HOME/.pi/agent/extensions/pi-lean-ctx/config.json" ] || \
      printf '{\n  "mode": "additive",\n  "enableMcp": true,\n  "toolProfile": "standard"\n}\n' \
        > "$HOME/.pi/agent/extensions/pi-lean-ctx/config.json"
    ok "config: ~/.pi/agent/extensions/pi-lean-ctx/config.json (the path that extension reads)"
  else
    warn "could not fetch pi-lean-ctx from npm — install by hand: npm pack pi-lean-ctx"
  fi
  rm -rf "$tmp"
fi

# --- token-diet's own extension ---------------------------------------------
if [ -d "$HERE/extensions" ]; then
  DEST="$HOME/.omp/agent/extensions/token-diet"
  rm -rf "$DEST"; mkdir -p "$DEST"; cp -R "$HERE/extensions" "$DEST/"
  [ -f "$HERE/package.json" ] && cp "$HERE/package.json" "$DEST/"
  ok "token-diet extension loaded (path-inject)"
fi

# --- always-on rule + config -------------------------------------------------
if [ -f "$HERE/rules/token-tools.md" ]; then
  mkdir -p "$HOME/.omp/agent/rules"
  cp "$HERE/rules/token-tools.md" "$HOME/.omp/agent/rules/token-tools.md"
  ok "token-tools rule installed"
fi
if [ "$NO_CONFIG" = 0 ]; then
  # shellcheck disable=SC2034  # consumed by scripts/lib/cfg.sh, sourced below
  CFG="$HOME/.omp/agent/config.yml"
  . "$HERE/../../scripts/lib/cfg.sh"
  cfg_add_snippet "$HERE/config.snippet.yml" token-diet
fi

say "token-diet ready. Restart omp so the extensions load."
