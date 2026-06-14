#!/usr/bin/env bash
# dev-team installer (Linux/macOS) — prerequisite checker + optional config apply.
# The agentic dev team is all-cloud: no local model backend to install. It needs
# OMP + git; a few skills optionally use gh / semgrep / docker / python3.
# Flags: --dry-run, --apply-config (append config.snippet.yml), -y.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0; APPLY=0; INSECURE_TLS=0
for a in "$@"; do case "$a" in
  --dry-run) DRY=1 ;; --apply-config) APPLY=1 ;; -y|--yes) ;; --insecure-tls) INSECURE_TLS=1 ;;
  -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else eval "$@"; fi; }
# Corporate TLS-intercepting proxy (Zscaler / Trend Micro under WSL): opt-in
# bypass of cert verification for curl/wget (incl. piped installers), git, node/bun.
enable_insecure_tls() {
  warn "Insecure TLS: certificate verification DISABLED for this run (corporate MITM proxy)."
  export GIT_SSL_NO_VERIFY=true NODE_TLS_REJECT_UNAUTHORIZED=0 NPM_CONFIG_STRICT_SSL=false \
         RUSTUP_USE_CURL=1 CARGO_HTTP_CHECK_REVOKE=false OMP_INSECURE_TLS=1
  local d; d="$(mktemp -d 2>/dev/null || echo "/tmp/omp-tls.$$")"; mkdir -p "$d"
  printf 'insecure\n' > "$d/.curlrc"; printf 'check_certificate = off\n' > "$d/.wgetrc"
  export CURL_HOME="$d" WGETRC="$d/.wgetrc"
}
{ [ "${INSECURE_TLS:-0}" = 1 ] || [ -n "${OMP_INSECURE_TLS:-}" ]; } && enable_insecure_tls

# --- Required: OMP ----------------------------------------------------------
if have omp; then ok "omp ($(omp --version 2>/dev/null | head -1))"
else
  say "Installing latest OMP"
  run "curl -fsSL https://omp.sh/install | sh"
fi

# --- Required: git ----------------------------------------------------------
say "Checking prerequisites"
if have git; then ok "git ($(git --version | awk '{print $3}'))"; else warn "git missing — required for branch-workflow / /pr"; fi

# --- Optional tools used by some skills -------------------------------------
for t in gh semgrep docker python3; do
  if have "$t"; then ok "$t (optional)"; else warn "$t not found (optional — used by some skills)"; fi
done

# --- Optionally apply the config snippet ------------------------------------
CFG="$HOME/.omp/agent/config.yml"
if [ "$APPLY" = 1 ]; then
  say "Appending config.snippet.yml to $CFG"
  if [ "$DRY" = 0 ]; then
    mkdir -p "$(dirname "$CFG")"; touch "$CFG"
    if grep -q "dev-team —" "$CFG" 2>/dev/null; then echo "  (already present — skipping)"
    else { echo ""; cat "$HERE/config.snippet.yml"; } >> "$CFG"; echo "  appended."; fi
  fi
fi

cat <<'EOF'

==> dev-team ready. Next:
    1) If you didn't pass --apply-config, paste config.snippet.yml into
       ~/.omp/agent/config.yml.
    2) Run `omp`, then drive the workflow: /specs -> /plan -> /build -> /pr.
    Keep the small tier cheap: modelRoles.smol (default claude-haiku-4-5; or a
    github-copilot model via the copilot-preset plugin).
EOF
