#!/usr/bin/env bash
# azure-devops-fs installer (Linux/macOS) — ensures Node.js (for the
# `npx @azure-devops/mcp` server) and pre-warms the LATEST MCP package. The `ado`
# tool itself is a TS extension loaded by OMP (no separate install).
# Idempotent. Flags: --dry-run, -y.
set -euo pipefail

DRY=0
for a in "$@"; do case "$a" in
  --dry-run) DRY=1 ;; -y|--yes) ;;
  -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else eval "$@"; fi; }

# --- Node.js (provides npx) -------------------------------------------------
NEED_NODE=20
if have node && [ "$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)" -ge "$NEED_NODE" ]; then
  say "Node.js present ($(node --version))"
else
  say "Installing latest LTS Node.js"
  if have brew; then run "brew install node"
  elif have fnm; then run "fnm install --lts && fnm use lts-latest"
  elif have nvm; then run "nvm install --lts"
  elif have curl; then
    # fnm is a self-contained, no-sudo Node manager
    run "curl -fsSL https://fnm.vercel.app/install | bash"
    run 'export PATH="$HOME/.local/share/fnm:$PATH"; eval "$(fnm env)"; fnm install --lts'
  else warn "install Node.js >= ${NEED_NODE} from https://nodejs.org"; fi
fi

# --- Pre-warm the Azure DevOps MCP server (latest) --------------------------
if have npx || [ "$DRY" = 1 ]; then
  say "Caching latest @azure-devops/mcp"
  run "npx -y @azure-devops/mcp@latest --help >/dev/null 2>&1 || true"
fi

cat <<'EOF'

==> azure-devops-fs deps ready. Config next-step (env vars):
    export AZURE_DEVOPS_ORG=your-org
    export AZURE_DEVOPS_PROJECT=your-project   # optional default
    export AZURE_DEVOPS_PAT=xxxxxxxx           # Code R/W, PR R/W (+ Build R)
    Then set the `azure-devops` MCP server enabled:true in your merged .mcp.json.
    The root install.sh can prompt for these and persist them securely.
EOF
