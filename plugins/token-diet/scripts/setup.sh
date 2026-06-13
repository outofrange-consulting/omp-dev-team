#!/usr/bin/env bash
# token-diet setup: install RTK + CodeGraph and index the current project.
# caveman ships as an OMP skill in this plugin — no install needed.
# Safe to re-run (idempotent). Run from your project root.
set -euo pipefail

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- RTK (Rust Token Killer) -------------------------------------------------
if have rtk; then
  say "RTK already installed ($(rtk --version 2>/dev/null || echo '?'))"
else
  say "Installing RTK (Rust Token Killer)"
  if have brew; then
    brew install rtk
  elif have curl; then
    curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
  elif have cargo; then
    cargo install --git https://github.com/rtk-ai/rtk
  else
    echo "  ! Need brew, curl, or cargo to install rtk — skipping." >&2
  fi
fi
# OMP routes commands through rtk via this plugin's always-on rule
# (rules/token-tools.md), so no 'rtk init' is required for OMP. Run
# 'rtk init -g' only if you also use Claude Code / Copilot / Cursor.

# --- CodeGraph (MCP) ---------------------------------------------------------
if have codegraph; then
  say "CodeGraph already installed"
else
  say "Installing CodeGraph"
  if have curl; then
    curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh
  elif have npm; then
    npm i -g @colbymchenry/codegraph
  else
    echo "  ! Need curl or npm to install codegraph — skipping." >&2
  fi
fi

if have codegraph; then
  say "Indexing this project with CodeGraph (cwd: $(pwd))"
  codegraph init . || true
  codegraph index . || true
  codegraph status . || true
fi

cat <<'EOF'

==> Done. Final step (manual): enable the CodeGraph MCP server.
    In your merged ~/.omp/agent .mcp.json (or project .omp), set:
        "mcpServers": { "codegraph": { ..., "enabled": true } }
    It ships disabled so it never starts before the project is indexed.

    - Shell output now auto-routes through `rtk` (always-on rule) when present.
    - Use `skill://codegraph` for symbol/caller/architecture queries.
    - Use `/caveman` for terse output when you want to save output tokens.
EOF
