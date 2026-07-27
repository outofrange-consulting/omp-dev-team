#!/usr/bin/env bash
# dev-team installer (Linux/macOS) — prerequisite checker + optional config apply.
# The agentic dev team is all-cloud: no local model backend to install. It needs
# OMP + git + PYTHON 3 (hard requirement: the plugin is a verbatim port of
# upstream agentic-dev-team, whose entire hook and script layer is Python, run
# unmodified through extensions/hook-bridge.ts). A few skills optionally use
# gh / semgrep / docker.
# Flags: --apply-config (append config.snippet.yml), --no-update (no-op), -y.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY=0; INSECURE_TLS=0
for a in "$@"; do case "$a" in
  --apply-config) APPLY=1 ;; --no-update) ;; -y|--yes) ;; --insecure-tls) INSECURE_TLS=1 ;; --ca-file=*) CA_FILE="${a#*=}" ;;
  -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
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
# python3 is NOT optional here — without it every guard, gate and telemetry hook
# is inert. Fail loudly at install time rather than silently at runtime.
if sh "$HERE/hooks/py.sh" -c '' >/dev/null 2>&1; then
  ok "python3 ($(sh "$HERE/hooks/py.sh" -c 'import sys;print(sys.version.split()[0])' 2>/dev/null))"
else
  warn "NO PYTHON 3 FOUND. dev-team's hook layer (guards, gates, telemetry) will be INERT."
  warn "Install Python 3.8+, or set DEV_TEAM_PYTHON to a working interpreter."
  MISSING_PY=1
fi

for t in gh semgrep docker; do
  if have "$t"; then ok "$t (optional)"; else warn "$t not found (optional — used by some skills)"; fi
done

# --- Optionally apply the config snippet ------------------------------------
CFG="$HOME/.omp/agent/config.yml"
if [ "$APPLY" = 1 ]; then
  say "Merging config.snippet.yml into $CFG"
  . "$HERE/../../scripts/lib/cfg.sh"
  cfg_add_snippet "$HERE/config.snippet.yml" dev-team
fi

# --- Load the extensions + the runtime they drive ----------------------------
# OMP does NOT load extension modules (package.json `omp.extensions`) from a
# marketplace cache install, so they are mirrored into OMP's native user
# extension dir.
#
# hooks/ AND scripts/ MUST travel with them. extensions/hook-bridge.ts resolves
# its plugin root from its own location (extensions/ -> ..), so after mirroring
# that root IS this dest dir — mirroring extensions/ alone would leave the bridge
# looking for hooks/py.sh in a directory that does not contain it, and the entire
# guard/gate/telemetry layer would be silently inert. $DEV_TEAM_ROOT (exported by
# plugin-root.ts) resolves the same way, which is what ported skill bodies use to
# find scripts/.
if [ -d "$HERE/extensions" ]; then
  DEST="$HOME/.omp/agent/extensions/dev-team"
  rm -rf "$DEST"; mkdir -p "$DEST"
  cp -R "$HERE/extensions" "$DEST/"
  cp -R "$HERE/hooks" "$DEST/"
  cp -R "$HERE/scripts" "$DEST/"
  [ -f "$HERE/package.json" ] && cp "$HERE/package.json" "$DEST/"
  chmod +x "$DEST/hooks/py.sh" 2>/dev/null || true
  say "extensions + hooks + scripts loaded into $DEST"
fi

if [ "${MISSING_PY:-0}" = 1 ]; then
  warn "dev-team installed, but WITHOUT Python 3 its hook layer does nothing."
  warn "Install Python 3.8+ (or set DEV_TEAM_PYTHON) and restart omp."
fi
say "dev-team ready. Restart omp, then drive the workflow: /skill:specs -> /skill:plan -> /skill:build -> /skill:pr (or /skill:ship for all of it)."
