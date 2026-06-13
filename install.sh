#!/usr/bin/env bash
# omp-dev-team — global installer (Linux/macOS).
# Installs OMP, registers this marketplace, then interactively offers each plugin
# and its config. Updates PATH so everything works in new shells.
#
# Flags:
#   -y, --yes      non-interactive: install all plugins + apply default configs
#                  (skips the Azure PAT prompt unless env vars are already set)
#   --dry-run      print actions without executing (passed to plugin installers)
#   -h, --help     this help
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKET="omp-dev-team"
DRY=0; YES=0
for a in "$@"; do case "$a" in
  -y|--yes) YES=1 ;; --dry-run) DRY=1 ;;
  -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else eval "$@"; fi; }
# ask "Question?" default(Y/n) -> returns 0 for yes
ask() {
  local q="$1" def="${2:-Y}" ans
  if [ "$YES" = 1 ]; then return 0; fi
  if [ ! -r /dev/tty ]; then  # non-interactive: take the default silently
    case "$def" in [Yy]*) return 0 ;; *) return 1 ;; esac
  fi
  if [ "$def" = "Y" ]; then q="$q [Y/n] "; else q="$q [y/N] "; fi
  read -r -p "$q" ans </dev/tty || ans=""
  ans="${ans:-$def}"
  case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

PROFILES=("$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc")
ensure_path() {  # add $1 to PATH in this session + persist to profiles (idempotent)
  local dir="$1" p
  [ -d "$dir" ] || return 0
  case ":$PATH:" in *":$dir:"*) ;; *) PATH="$dir:$PATH"; export PATH ;; esac
  [ "$DRY" = 1 ] && { printf '  [dry-run] persist PATH += %s\n' "$dir"; return 0; }
  for p in "${PROFILES[@]}"; do
    [ -e "$p" ] || continue
    grep -qsF "$dir" "$p" 2>/dev/null && continue
    printf '\n# omp-dev-team\nexport PATH="%s:$PATH"\n' "$dir" >> "$p"
  done
}

bold "omp-dev-team installer"
echo "Repo: $ROOT"

# --- 1) OMP ----------------------------------------------------------------
if have omp; then ok "omp present ($(omp --version 2>/dev/null | head -1))"
else say "Installing OMP (latest)"; run "curl -fsSL https://omp.sh/install | sh"; fi
# Make omp + tool dirs available now and in future shells.
for d in "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.bun/bin"; do ensure_path "$d"; done
have omp || warn "omp not on PATH yet — open a new shell or 'source ~/.profile' after this"

# --- 2) Register the marketplace -------------------------------------------
if have omp; then
  say "Registering marketplace ($MARKET) from local checkout"
  run "omp plugin marketplace add \"$ROOT\" || true"
fi

# helper: install a plugin + run its tool installer
plug() {  # plug <name> <dir>
  local name="$1" dir="$2" flags=""
  [ "$DRY" = 1 ] && flags="--dry-run"
  if have omp; then run "omp plugin install ${name}@${MARKET} || true"; fi
  if [ -x "$dir/install.sh" ] || [ -f "$dir/install.sh" ]; then
    run "bash \"$dir/install.sh\" $flags ${YES:+-y}"
  fi
}

# --- 3) Per-plugin prompts --------------------------------------------------
bold "Plugins"

if ask "Install dev-team (agentic dev team: /specs -> /plan -> /build -> /pr)?"; then
  plug dev-team "$ROOT/plugins/dev-team"
  if ask "  Apply dev-team config to ~/.omp/agent/config.yml?"; then
    run "bash \"$ROOT/plugins/dev-team/install.sh\" --apply-config ${DRY:+--dry-run}"
  fi
fi

if ask "Install copilot-preset (route models through GitHub Copilot)?" "N"; then
  plug copilot-preset "$ROOT/plugins/copilot-preset"
  if ask "  Apply copilot-preset config to ~/.omp/agent/config.yml?" "N"; then
    run "bash \"$ROOT/plugins/copilot-preset/install.sh\" --apply-config ${DRY:+--dry-run}"
  fi
  echo "  Reminder: run 'omp' then /login -> GitHub Copilot."
fi

if ask "Install token-diet (RTK + CodeGraph + caveman; token reduction)?" "N"; then
  plug token-diet "$ROOT/plugins/token-diet"
  echo "  Reminder: enable the 'codegraph' MCP server (enabled:true) once indexed."
fi

if ask "Install azure-devops-fs (Azure DevOps as a filesystem)?" "N"; then
  plug azure-devops-fs "$ROOT/plugins/azure-devops-fs"
  if ask "  Configure Azure DevOps env vars now?" "N"; then
    SECRETS="$HOME/.omp/secrets.env"
    read -r -p "    AZURE_DEVOPS_ORG: " ado_org </dev/tty || ado_org=""
    read -r -p "    AZURE_DEVOPS_PROJECT (optional): " ado_proj </dev/tty || ado_proj=""
    read -r -s -p "    AZURE_DEVOPS_PAT (hidden): " ado_pat </dev/tty || ado_pat=""; echo
    if [ "$DRY" = 1 ]; then
      echo "  [dry-run] write org/project to profiles, PAT to $SECRETS (chmod 600)"
    else
      [ -n "$ado_org" ]  && for p in "${PROFILES[@]}"; do [ -e "$p" ] && { grep -qsF AZURE_DEVOPS_ORG "$p" || printf '\nexport AZURE_DEVOPS_ORG=%q\n' "$ado_org" >> "$p"; }; done
      [ -n "$ado_proj" ] && for p in "${PROFILES[@]}"; do [ -e "$p" ] && { grep -qsF AZURE_DEVOPS_PROJECT "$p" || printf 'export AZURE_DEVOPS_PROJECT=%q\n' "$ado_proj" >> "$p"; }; done
      if [ -n "$ado_pat" ]; then
        mkdir -p "$(dirname "$SECRETS")"; touch "$SECRETS"; chmod 600 "$SECRETS"
        grep -qsF AZURE_DEVOPS_PAT "$SECRETS" || printf 'export AZURE_DEVOPS_PAT=%q\n' "$ado_pat" >> "$SECRETS"
        for p in "${PROFILES[@]}"; do [ -e "$p" ] && { grep -qsF "secrets.env" "$p" || printf '\n[ -f "%s" ] && . "%s"\n' "$SECRETS" "$SECRETS" >> "$p"; }; done
        echo "  PAT stored in $SECRETS (chmod 600), sourced from your profile."
      fi
    fi
  fi
  echo "  Reminder: enable the 'azure-devops' MCP server (enabled:true) in your .mcp.json."
fi

bold "Done"
say "Installed tools:"
for t in omp rtk codegraph node; do
  if have "$t"; then ok "$t -> $(command -v "$t")"; fi
done
echo
echo "Open a NEW shell (or 'source ~/.profile') so PATH changes take effect, then run: omp"
