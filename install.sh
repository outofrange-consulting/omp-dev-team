#!/usr/bin/env bash
# omp-dev-team — global installer (Linux/macOS).
# Installs OMP, registers this marketplace, then interactively offers each plugin
# and its config. Updates PATH so everything works in new shells.
#
# Flags:
#   -y, --yes      non-interactive: install all plugins + apply default configs
#                  (skips the Azure PAT prompt unless env vars are already set)
#   --update       refresh things that are already installed (otherwise: skip them)
#   --no-runtimes  skip installing node/bun/cargo (assume they're present)
#   --dry-run      print actions without executing (passed to plugin installers)
#   -h, --help     this help
#
# Default policy for things already present: SKIP (idempotent, never asks, never
# overwrites). Pass --update to refresh to the latest. Exception: bun is always
# upgraded if it's below the version OMP requires.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKET="omp-dev-team"
DRY=0; YES=0; RUNTIMES=1; UPDATE=0
for a in "$@"; do case "$a" in
  -y|--yes) YES=1 ;; --dry-run) DRY=1 ;; --no-runtimes) RUNTIMES=0 ;; --update) UPDATE=1 ;;
  -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
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
  # Guarantee a login-shell profile exists so a fresh account picks up PATH.
  [ -e "$HOME/.profile" ] || : > "$HOME/.profile"
  for p in "${PROFILES[@]}"; do
    [ -e "$p" ] || continue
    grep -qsF "$dir" "$p" 2>/dev/null && continue
    printf '\n# omp-dev-team\nexport PATH="%s:$PATH"\n' "$dir" >> "$p"
  done
}

# true if installed $1 version is >= $2 (dotted)
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

MIN_BUN="1.3.14"
ensure_bun() {  # OMP requires bun >= MIN_BUN
  if have bun && version_ge "$(bun --version 2>/dev/null || echo 0)" "$MIN_BUN" && [ "$UPDATE" = 0 ]; then
    ok "bun $(bun --version) (skip; --update to refresh)"
  else
    say "Installing bun (>= $MIN_BUN; OMP requires it)"
    run "curl -fsSL https://bun.sh/install | bash"
  fi
  ensure_path "$HOME/.bun/bin"
}
ensure_node() {  # needed by azure-devops-fs (npx) and handy generally
  if have node && [ "$UPDATE" = 0 ]; then ok "node $(node --version) (skip; --update to refresh)"; return; fi
  say "Installing Node.js (LTS)"
  if have brew; then run "brew install node"
  elif have curl; then
    run "curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell"
    ensure_path "$HOME/.local/share/fnm"; hash -r 2>/dev/null || true
    if have fnm; then
      run 'eval "$(fnm env --shell bash)"; fnm install --lts && fnm use lts-latest'
      # fnm's multishell bin is per-process/ephemeral — symlink the REAL node/npm/npx
      # into ~/.local/bin so they persist to new shells.
      mkdir -p "$HOME/.local/bin"
      if have node; then
        local rn bd b
        rn="$(readlink -f "$(command -v node)" 2>/dev/null || true)"
        if [ -n "$rn" ]; then bd="$(dirname "$rn")"; for b in node npm npx; do [ -e "$bd/$b" ] && ln -sf "$bd/$b" "$HOME/.local/bin/$b"; done; fi
        ensure_path "$HOME/.local/bin"; hash -r 2>/dev/null || true
      fi
    fi
  else warn "could not install Node.js automatically — see https://nodejs.org"; fi
}
ensure_cargo() {  # Rust toolchain (rtk fallback build; generally useful)
  if have cargo && [ "$UPDATE" = 0 ]; then ok "cargo $(cargo --version 2>/dev/null | awk '{print $2}') (skip; --update to refresh)"; return; fi
  if have rustup && [ "$UPDATE" = 1 ]; then say "Updating Rust"; run "rustup update"; return; fi
  if have cargo; then ok "cargo present"; return; fi
  say "Installing Rust (rustup)"
  run "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path"
  ensure_path "$HOME/.cargo/bin"
}

bold "omp-dev-team installer"
echo "Repo: $ROOT"

# --- 0) Runtimes (node, bun, cargo) ----------------------------------------
if [ "$RUNTIMES" = 1 ]; then
  say "Ensuring runtimes"
  ensure_bun
  ensure_node
  ensure_cargo
else
  say "Skipping runtime install (--no-runtimes)"
fi

# --- 1) OMP ----------------------------------------------------------------
if have omp && [ "$UPDATE" = 0 ]; then ok "omp present ($(omp --version 2>/dev/null | head -1)) (skip; --update to refresh)"
elif have omp; then say "Updating OMP"; run "bun add -g @oh-my-pi/pi-coding-agent@latest || curl -fsSL https://omp.sh/install | sh"
else say "Installing OMP (latest)"; run "curl -fsSL https://omp.sh/install | sh"; fi
# Make omp + tool dirs available now and in future shells. Create them first so
# ensure_path adds them even before later steps drop binaries in (e.g. rtk).
for d in "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.bun/bin"; do mkdir -p "$d" 2>/dev/null || true; ensure_path "$d"; done
have omp || warn "omp not on PATH yet — open a new shell or 'source ~/.profile' after this"

# --- 2) Register the marketplace -------------------------------------------
if have omp; then
  say "Registering marketplace ($MARKET) from local checkout"
  run "omp plugin marketplace add \"$ROOT\" || true"
fi

# helper: install a plugin + run its tool installer.
# Already-installed policy: SKIP by default; with --update, reinstall (--force).
plug() {  # plug <name> <dir>
  local name="$1" dir="$2" flags=""
  [ "$DRY" = 1 ] && flags="--dry-run"
  [ "$UPDATE" = 1 ] && [ "$name" = token-diet ] && flags="$flags --update"
  if have omp; then
    if omp plugin list 2>/dev/null | grep -q "${name}@${MARKET}"; then
      if [ "$UPDATE" = 1 ]; then run "omp plugin install --force ${name}@${MARKET} || true"
      else ok "plugin ${name} already installed (skip; --update to refresh)"; fi
    else run "omp plugin install ${name}@${MARKET} || true"; fi
  fi
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

# --- 4) Doctor (verify everything is present) ------------------------------
bold "Doctor"
[ "$DRY" = 1 ] && { echo "(dry-run — skipping verification)"; exit 0; }
# Refresh PATH for dirs that may have been created during plugin installs.
for d in "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.bun/bin"; do ensure_path "$d"; done
hash -r 2>/dev/null || true
fail=0
check() {  # check <tool> <required|optional> <version-cmd>
  local t="$1" req="$2" vc="${3:-}"
  if have "$t"; then
    local v=""; [ -n "$vc" ] && v="$(eval "$vc" 2>/dev/null | head -1)"
    ok "$t ${v:+($v)} -> $(command -v "$t")"
  elif [ "$req" = required ]; then warn "$t MISSING (required)"; fail=1
  else warn "$t not found (optional)"; fi
}
check git      required "git --version"
check bun      required "bun --version"
check node     recommended "node --version"
check cargo    recommended "cargo --version"
check omp      required "omp --version"
check rtk      optional "rtk --version"
check codegraph optional "codegraph --version"

bold "OMP launch check"
if have omp && omp --version >/dev/null 2>&1; then
  ok "omp launches: $(omp --version 2>/dev/null | head -1)"
  echo "  plugins installed:"; omp plugin list 2>/dev/null | grep -E "@${MARKET}" | sed 's/^/    /' || true
else
  warn "omp did not launch — ensure \$HOME/.bun/bin is on PATH"; fail=1
fi

echo
if [ "$fail" = 0 ]; then
  bold "All set ✓"
else
  bold "Finished with warnings — see above"
fi
echo "Open a NEW shell (or 'source ~/.profile') so PATH changes persist, then run: omp"
[ "$fail" = 0 ] || exit 1
