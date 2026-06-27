#!/usr/bin/env bash
# datadog component installer (Copilot CLI, Linux/macOS).
# Installs the Datadog `pup` CLI (https://github.com/DataDog/pup), sets up auth,
# and installs the `datadog` agent into ~/.copilot/agents.
# Flags: -y/--yes, --no-update, --no-config, --insecure-tls, --ca-file=PATH
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPILOT_HOME="${COPILOT_HOME:-$HOME/.copilot}"
YES=0; NO_CONFIG=0; NO_UPDATE=0; INSECURE_TLS=0
for a in "$@"; do case "$a" in
  -y|--yes) YES=1 ;; --no-config) NO_CONFIG=1 ;; --no-update) NO_UPDATE=1 ;;
  --insecure-tls) INSECURE_TLS=1 ;; --ca-file=*) CA_FILE="${a#*=}" ;;
  -h|--help) sed -n '2,6p' "$0"; exit 0 ;; *) : ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
{ [ "${INSECURE_TLS:-0}" = 1 ] || [ -n "${OMP_INSECURE_TLS:-}" ]; } && export GIT_SSL_NO_VERIFY=true
CA_FILE="${CA_FILE:-${OMP_CA_FILE:-}}"
[ -n "$CA_FILE" ] && [ -f "$CA_FILE" ] && export CURL_CA_BUNDLE="$CA_FILE" GIT_SSL_CAINFO="$CA_FILE"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

# --- install pup ------------------------------------------------------------
install_pup() {
  if have pup && [ "$NO_UPDATE" = 1 ]; then say "pup present ($(pup --version 2>/dev/null | head -1))"; return 0; fi
  if have brew; then
    say "Installing pup via Homebrew"
    brew tap datadog-labs/pack >/dev/null 2>&1 || true
    brew install datadog-labs/pack/pup 2>/dev/null || brew upgrade datadog-labs/pack/pup 2>/dev/null || true
    have pup && return 0
  fi
  have curl || { warn "need curl or brew to install pup — see https://github.com/DataDog/pup"; return 0; }
  local os arch ver url tmp
  case "$(uname -s)" in Linux) os=Linux ;; Darwin) os=Darwin ;; *) warn "unsupported OS for pup auto-install"; return 0 ;; esac
  case "$(uname -m)" in x86_64|amd64) arch=x86_64 ;; arm64|aarch64) arch=arm64 ;; *) warn "unsupported arch for pup"; return 0 ;; esac
  ver="$(curl -fsSL https://api.github.com/repos/DataDog/pup/releases/latest 2>/dev/null | grep -oE '"tag_name"[^,]*' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  [ -n "$ver" ] || { warn "could not resolve the latest pup release"; return 0; }
  url="https://github.com/DataDog/pup/releases/download/v${ver}/pup_${ver}_${os}_${arch}.tar.gz"
  say "Installing pup ${ver} (${os}/${arch}) to ~/.local/bin"
  tmp="$(mktemp -d)"; mkdir -p "$HOME/.local/bin"
  if curl -fsSL "$url" -o "$tmp/pup.tgz" && tar -xzf "$tmp/pup.tgz" -C "$tmp"; then
    if [ -f "$tmp/pup" ]; then install -m 0755 "$tmp/pup" "$HOME/.local/bin/pup"
    else find "$tmp" -type f -name pup -exec install -m 0755 {} "$HOME/.local/bin/pup" \; ; fi
    hash -r 2>/dev/null || true
    have pup && ok "pup installed: $(pup --version 2>/dev/null | head -1)" || warn "pup not on PATH after install"
  else warn "pup download failed ($url) — install manually from https://github.com/DataDog/pup/releases"; fi
  rm -rf "$tmp" 2>/dev/null || true
}
install_pup

# --- auth -------------------------------------------------------------------
if [ "$NO_CONFIG" = 0 ] && have pup; then
  if pup auth status >/dev/null 2>&1; then say "Datadog already authenticated"
  elif [ -n "${DD_API_KEY:-}" ] || [ -n "${DD_ACCESS_TOKEN:-}" ]; then say "Datadog credentials present in environment"
  elif [ "$YES" = 1 ] || [ ! -r /dev/tty ]; then say "Skipping auth (non-interactive). Later: 'pup auth login' or set DD_API_KEY/DD_APP_KEY/DD_SITE."
  else
    printf '    Authenticate now via browser (pup auth login)? [Y/n] '; read -r ans </dev/tty || ans=""
    case "${ans:-Y}" in [Yy]*) pup auth login || warn "pup auth login failed — set DD_API_KEY/DD_APP_KEY instead." ;; *) say "Skipped — 'pup auth login' or DD_API_KEY/DD_APP_KEY later." ;; esac
  fi
fi

# --- agent -> ~/.copilot/agents ---------------------------------------------
if [ "$NO_CONFIG" = 0 ]; then
  mkdir -p "$COPILOT_HOME/agents"
  cp -f "$HERE"/agents/*.agent.md "$COPILOT_HOME/agents/"
  ok "datadog agent installed -> $COPILOT_HOME/agents"
fi

say "datadog ready. In Copilot CLI: /agent datadog (drives the pup CLI). Auth: 'pup auth login' or DD_API_KEY/DD_APP_KEY/DD_SITE."
