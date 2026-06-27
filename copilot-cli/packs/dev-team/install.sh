#!/usr/bin/env bash
# dev-team component installer (Copilot CLI, Linux/macOS).
# Installs the agents into ~/.copilot/agents, the hook scripts + dt CLI into
# ~/.copilot/dev-team, and a `dt` shim into ~/.local/bin. Guards are armed PER REPO
# with `dt init` (Copilot CLI loads hooks from the project's .github/hooks).
# Flags: -y/--yes, --no-update, --no-config, --insecure-tls, --ca-file=PATH
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPILOT_HOME="${COPILOT_HOME:-$HOME/.copilot}"
YES=0; NO_CONFIG=0
for a in "$@"; do case "$a" in
  -y|--yes) YES=1 ;; --no-config) NO_CONFIG=1 ;; --no-update) : ;; --insecure-tls) : ;; --ca-file=*) : ;;
  -h|--help) sed -n '2,8p' "$0"; exit 0 ;; *) : ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

have node || { warn "node not found — Copilot CLI + the dev-team hooks need Node >= 22. Install Node, then re-run."; }

# --- agents -> ~/.copilot/agents -------------------------------------------
if [ "$NO_CONFIG" = 0 ]; then
  say "Installing dev-team agents into $COPILOT_HOME/agents"
  mkdir -p "$COPILOT_HOME/agents"
  cp -f "$HERE"/agents/*.agent.md "$COPILOT_HOME/agents/"
  ok "$(ls "$HERE"/agents/*.agent.md | wc -l | tr -d ' ') agents installed"
fi

# --- runtime (dt CLI + hook scripts + instructions) -> ~/.copilot/dev-team ---
say "Installing dev-team runtime into $COPILOT_HOME/dev-team"
DEST="$COPILOT_HOME/dev-team"
rm -rf "$DEST"; mkdir -p "$DEST/hooks/scripts" "$DEST/instructions"
cp -f "$HERE/dt.mjs" "$DEST/dt.mjs"
cp -f "$HERE"/hooks/scripts/*.mjs "$DEST/hooks/scripts/"
cp -f "$HERE"/instructions/*.md "$DEST/instructions/"
ok "dt CLI + preToolUse guard + operating manual installed"

# --- dt shim -> ~/.local/bin/dt --------------------------------------------
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/dt" <<EOF
#!/usr/bin/env bash
exec node "$DEST/dt.mjs" "\$@"
EOF
chmod +x "$HOME/.local/bin/dt"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
ok "dt -> ~/.local/bin/dt"

say "dev-team ready. Arm a repo: cd into it and run 'dt init' (writes .github/hooks + copilot-instructions)."
echo "    Flow: dt scope -> /agent plan -> dt plan-approve -> /agent build -> /agent review -> dt review-approve -> /agent pr"
