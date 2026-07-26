#!/usr/bin/env bash
# dev-team installer (Linux/macOS) — prerequisite checker + optional config apply.
# The agentic dev team is all-cloud: no local model backend to install. It needs
# OMP + git; a few skills optionally use gh / semgrep / docker / python3. The
# bundled serena-forge integration additionally needs .NET 10+ (installed below
# if missing) and uvx (checked only, never auto-installed) for its C# backend.
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
for t in gh semgrep docker python3; do
  if have "$t"; then ok "$t (optional)"; else warn "$t not found (optional — used by some skills)"; fi
done

# --- .NET SDK (bundled serena-forge integration's C# backend needs .NET 10+) -
# serena-forge (Serena's Roslyn-based Microsoft.CodeAnalysis.LanguageServer)
# requires .NET 10+ on the host; Serena itself launches via uvx (checked below,
# never auto-installed here) and downloads the Roslyn LS from NuGet on first
# C# use. Skip harmlessly if you never touch .cs files.
dotnet_major() {
  if have dotnet; then dotnet --version 2>/dev/null | cut -d. -f1; else echo 0; fi
}
if [ "$(dotnet_major)" -lt 10 ]; then
  if have brew; then
    say "Installing .NET SDK (serena-forge's C# backend needs .NET 10+)"
    run "brew install --cask dotnet-sdk || brew install dotnet || true"
  elif have curl; then
    say "Installing .NET SDK (LTS) via the official Microsoft script (serena-forge needs .NET 10+)"
    run "curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && bash /tmp/dotnet-install.sh --channel LTS --install-dir \"$HOME/.dotnet\" || true"
    rm -f /tmp/dotnet-install.sh 2>/dev/null || true
  else
    warn "need curl or brew to install the .NET SDK — see https://dot.net (needed for serena-forge's C# backend; harmless to skip if you never work in C#)"
  fi
  export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"
  for p in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -e "$p" ] || continue
    grep -qsF 'DOTNET_ROOT' "$p" || printf '\n# omp-dev-team .NET (serena-forge)\nexport DOTNET_ROOT="$HOME/.dotnet"\nexport PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"\n' >> "$p"
  done
  hash -r 2>/dev/null || true
fi
if [ "$(dotnet_major)" -ge 10 ]; then ok "dotnet $(dotnet --version) (serena-forge C# backend)"
elif have dotnet; then warn "dotnet $(dotnet --version) found but serena-forge's C# backend needs .NET 10+ (see https://dot.net)"
else warn "dotnet not found — serena-forge's C# backend needs .NET 10+ (see https://dot.net; harmless to skip if you never work in C#)"; fi

# --- uvx (from uv) — launches the bundled Serena MCP server -----------------
# Never auto-installed here (a package manager should own it, and Serena's
# setup skills explicitly tell users to install uv themselves, not the agent).
if have uvx; then ok "uvx ($(uvx --version 2>/dev/null))"
else warn "uvx not found — serena-forge's Serena MCP server can't launch (install uv: https://github.com/astral-sh/uv)"; fi

# --- Optionally apply the config snippet ------------------------------------
CFG="$HOME/.omp/agent/config.yml"
if [ "$APPLY" = 1 ]; then
  say "Merging config.snippet.yml into $CFG"
  . "$HERE/../../scripts/lib/cfg.sh"
  cfg_add_snippet "$HERE/config.snippet.yml" dev-team
fi

# --- Load the guard extensions ----------------------------------------------
# OMP does NOT load extension modules (package.json `omp.extensions`) from
# marketplace cache installs, so the blocking guards would
# otherwise never run. Mirror them into OMP's native user-extension dir.
if [ -d "$HERE/extensions" ]; then
  DEST="$HOME/.omp/agent/extensions/dev-team"
  rm -rf "$DEST"; mkdir -p "$DEST"; cp -R "$HERE/extensions" "$DEST/"
  [ -f "$HERE/package.json" ] && cp "$HERE/package.json" "$DEST/"
  say "guards loaded into $DEST"
fi

say "dev-team ready. Restart omp, then drive the workflow: /specs -> /plan -> /build -> /pr."
