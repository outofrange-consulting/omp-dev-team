#!/usr/bin/env bash
# copilot-preset installer (Linux/macOS) — config-only. Ensures OMP is present,
# guides Copilot login, and (optionally) appends config.snippet.yml to your OMP
# config. No external tools to install.
# Flags: --dry-run, --apply-config (append snippet), -y.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0; APPLY=0
for a in "$@"; do case "$a" in
  --dry-run) DRY=1 ;; --apply-config) APPLY=1 ;; -y|--yes) ;;
  -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else eval "$@"; fi; }

# --- OMP (the only requirement) ---------------------------------------------
if have omp; then
  say "OMP present ($(omp --version 2>/dev/null | head -1))"
else
  say "Installing latest OMP"
  run "curl -fsSL https://omp.sh/install | sh"
fi

# --- Optionally apply the config snippet ------------------------------------
CFG="$HOME/.omp/agent/config.yml"
if [ "$APPLY" = 1 ]; then
  say "Appending config.snippet.yml to $CFG"
  if [ "$DRY" = 0 ]; then
    mkdir -p "$(dirname "$CFG")"; touch "$CFG"
    if grep -q "copilot-preset" "$CFG" 2>/dev/null; then
      echo "  (already present — skipping)"
    else
      { echo ""; echo "# --- copilot-preset (appended $(date -u +%FT%TZ)) ---"; cat "$HERE/config.snippet.yml"; } >> "$CFG"
      echo "  appended. Review $CFG and adjust model ids to your plan."
    fi
  fi
fi

cat <<'EOF'

==> copilot-preset ready. Final steps:
    1) Authenticate Copilot:  run `omp`, then /login -> GitHub Copilot
       (or: export COPILOT_GITHUB_TOKEN=...  /  GH_TOKEN  /  GITHUB_TOKEN)
    2) Confirm models on your plan:  omp --list-models | grep github-copilot
    3) If you didn't pass --apply-config, paste config.snippet.yml into
       ~/.omp/agent/config.yml. See pricing.md for the cheap-token mapping.
EOF
