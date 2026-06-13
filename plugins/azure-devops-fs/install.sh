#!/usr/bin/env bash
# azure-devops-fs installer (Linux/macOS) — ensures Node.js (for the
# `npx @azure-devops/mcp` server), pre-warms the LATEST MCP package, and (when
# interactive) prompts for the Azure DevOps org/project/PAT and persists them.
# Flags:
#   --configure   force the org/project/PAT prompt
#   --no-config   never prompt for credentials
#   --dry-run     print only
#   -y, --yes     non-interactive (skip the credential prompt)
set -euo pipefail

DRY=0; YES=0; CONFIG=auto
for a in "$@"; do case "$a" in
  --dry-run) DRY=1 ;; -y|--yes) YES=1 ;;
  --configure) CONFIG=force ;; --no-config) CONFIG=skip ;;
  -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
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
    run "curl -fsSL https://fnm.vercel.app/install | bash"
    run 'export PATH="$HOME/.local/share/fnm:$PATH"; eval "$(fnm env)"; fnm install --lts'
  else warn "install Node.js >= ${NEED_NODE} from https://nodejs.org"; fi
fi

# --- Pre-warm the Azure DevOps MCP server (latest) --------------------------
if have npx || [ "$DRY" = 1 ]; then
  say "Caching latest @azure-devops/mcp"
  run "npx -y @azure-devops/mcp@latest --help >/dev/null 2>&1 || true"
fi

# --- Configure org / project / PAT ------------------------------------------
configure_ado() {
  local org proj pat secrets="$HOME/.omp/secrets.env" p
  local profiles=("$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc")
  printf '    AZURE_DEVOPS_ORG (e.g. https://dev.azure.com/<org>): '; read -r org </dev/tty || org=""
  [ -z "$org" ] && { warn "no org entered — skipping ADO credential write"; return; }
  printf '    AZURE_DEVOPS_PROJECT (optional default): '; read -r proj </dev/tty || proj=""
  printf '    AZURE_DEVOPS_PAT (hidden; Code R/W, PR R/W, +Build R): '; read -r -s pat </dev/tty || pat=""; echo
  if [ "$DRY" = 1 ]; then echo "  [dry-run] write ORG/PROJECT to ~/.profile, PAT to $secrets (chmod 600)"; return; fi
  [ -e "$HOME/.profile" ] || : > "$HOME/.profile"
  for p in "${profiles[@]}"; do [ -e "$p" ] || continue
    grep -qsF AZURE_DEVOPS_ORG "$p" || printf '\nexport AZURE_DEVOPS_ORG=%q\n' "$org" >> "$p"
    [ -n "$proj" ] && { grep -qsF AZURE_DEVOPS_PROJECT "$p" || printf 'export AZURE_DEVOPS_PROJECT=%q\n' "$proj" >> "$p"; }
  done
  if [ -n "$pat" ]; then
    mkdir -p "$(dirname "$secrets")"; touch "$secrets"; chmod 600 "$secrets"
    grep -qsF AZURE_DEVOPS_PAT "$secrets" || printf 'export AZURE_DEVOPS_PAT=%q\n' "$pat" >> "$secrets"
    for p in "${profiles[@]}"; do [ -e "$p" ] || continue; grep -qsF secrets.env "$p" || printf '\n[ -f "%s" ] && . "%s"\n' "$secrets" "$secrets" >> "$p"; done
    echo "  PAT stored in $secrets (chmod 600), sourced from your profile."
  fi
  echo "  org/project written to your shell profile."
}

if [ -n "${AZURE_DEVOPS_ORG:-}" ] && [ -n "${AZURE_DEVOPS_PAT:-}" ]; then
  say "Azure DevOps already configured via environment — skipping prompt"
elif [ "$CONFIG" = skip ] || { [ "$CONFIG" = auto ] && { [ "$YES" = 1 ] || [ ! -r /dev/tty ]; }; }; then
  say "Skipping ADO credential prompt (non-interactive)"
  echo "    Set later:  AZURE_DEVOPS_ORG / AZURE_DEVOPS_PROJECT / AZURE_DEVOPS_PAT"
else
  say "Configure Azure DevOps credentials"
  configure_ado
fi

cat <<'EOF'

==> azure-devops-fs ready. Final step:
    Enable the `azure-devops` MCP server (enabled:true) in your merged .mcp.json.
    The PAT is injected per-request; it is never written to remotes.
EOF
