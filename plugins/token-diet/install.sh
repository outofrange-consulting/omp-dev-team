#!/usr/bin/env bash
# token-diet installer (Linux/macOS) — installs the LATEST RTK + CodeGraph and
# indexes the current project. caveman ships as an OMP skill (no install).
# Idempotent. Flags: --dry-run (print only), --update (refresh existing), -y.
set -euo pipefail

DRY=0; UPDATE=0; YES=0
for a in "$@"; do case "$a" in
  --dry-run) DRY=1 ;; --update) UPDATE=1 ;; -y|--yes) YES=1 ;;
  -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else eval "$@"; fi; }

# --- RTK (Rust Token Killer) -------------------------------------------------
if have rtk && [ "$UPDATE" = 0 ]; then
  say "RTK present ($(rtk --version 2>/dev/null || echo '?')) — use --update to refresh"
else
  say "Installing latest RTK (Rust Token Killer)"
  if have brew;  then run "brew install rtk || brew upgrade rtk"
  elif have curl; then run "curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh"
  elif have cargo; then run "cargo install --git https://github.com/rtk-ai/rtk"
  else warn "need brew, curl, or cargo to install rtk — skipping"; fi
fi

# --- CodeGraph (MCP) ---------------------------------------------------------
if have codegraph && [ "$UPDATE" = 0 ]; then
  say "CodeGraph present — use --update to refresh"
else
  say "Installing latest CodeGraph"
  if have curl;  then run "curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh"
  elif have npm; then run "npm i -g @colbymchenry/codegraph@latest"
  else warn "need curl or npm to install codegraph — skipping"; fi
fi

# --- Index the current project ----------------------------------------------
if have codegraph || [ "$DRY" = 1 ]; then
  say "Indexing this project with CodeGraph (cwd: $(pwd))"
  run "codegraph init ."   || true
  run "codegraph index ."  || true
  run "codegraph status ." || true
fi

cat <<'EOF'

==> token-diet tools ready. Final manual step: enable the CodeGraph MCP server.
    In your merged ~/.omp/agent .mcp.json set:  "codegraph": { ..., "enabled": true }
    (ships disabled so it never starts before the project is indexed).

    - Shell output auto-routes through `rtk` (always-on rule) when present.
    - `skill://codegraph` for symbol/caller/architecture queries.
    - `/caveman` for terse output to save output tokens.
EOF
