#!/usr/bin/env bash
# copilot-preset installer (Linux/macOS) — config-only. Ensures OMP is present,
# guides Copilot login, and (optionally) appends config.snippet.yml to your OMP
# config. No external tools to install.
# Flags: --apply-config (append snippet), --no-update (no-op), -y.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY=0; INSECURE_TLS=0
for a in "$@"; do case "$a" in
  --apply-config) APPLY=1 ;; --no-update) ;; -y|--yes) ;; --insecure-tls) INSECURE_TLS=1 ;; --ca-file=*) CA_FILE="${a#*=}" ;;
  -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { eval "$@"; }
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
# Corporate root CA (optional): trust a custom CA this run (node/bun/git/curl/Go).
CA_FILE="${CA_FILE:-${OMP_CA_FILE:-}}"
if [ -n "$CA_FILE" ] && [ -f "$CA_FILE" ]; then
  export OMP_CA_FILE="$CA_FILE" NODE_EXTRA_CA_CERTS="$CA_FILE" SSL_CERT_FILE="$CA_FILE" CURL_CA_BUNDLE="$CA_FILE" GIT_SSL_CAINFO="$CA_FILE" REQUESTS_CA_BUNDLE="$CA_FILE"
  warn "Trusting corporate CA: $CA_FILE"
fi

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
  mkdir -p "$(dirname "$CFG")"; touch "$CFG"
  if grep -q "copilot-preset" "$CFG" 2>/dev/null; then
    echo "  (already present — skipping)"
  else
    { echo ""; echo "# --- copilot-preset (appended $(date -u +%FT%TZ)) ---"; cat "$HERE/config.snippet.yml"; } >> "$CFG"
    echo "  appended. Review $CFG and adjust model ids to your plan."
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
