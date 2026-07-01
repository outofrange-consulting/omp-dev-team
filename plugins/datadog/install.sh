#!/usr/bin/env bash
# datadog installer (Linux/macOS) — install the Datadog "pup" CLI
# (https://github.com/DataDog/pup) and set up authentication. The single OMP
# `datadog` skill drives pup (which embeds Datadog's domain skills/subagents), so
# we DON'T install ~30 separate skills into OMP by default — pass --with-skills
# to also run `pup skills install pi`.
# Flags:
#   --with-skills   also run `pup skills install pi` (adds the dd-* skills to OMP)
#   --no-config     don't prompt for / persist Datadog credentials
#   --no-update     keep pup if already installed (don't refresh)
#   -y, --yes       non-interactive (skip prompts)
set -euo pipefail

YES=0; WITH_SKILLS=0; NO_CONFIG=0; NO_UPDATE=0; INSECURE_TLS=0
for a in "$@"; do case "$a" in
  -y|--yes) YES=1 ;; --with-skills) WITH_SKILLS=1 ;; --no-config) NO_CONFIG=1 ;; --no-update) NO_UPDATE=1 ;;
  --insecure-tls) INSECURE_TLS=1 ;; --ca-file=*) CA_FILE="${a#*=}" ;;
  -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
{ [ "${INSECURE_TLS:-0}" = 1 ] || [ -n "${OMP_INSECURE_TLS:-}" ]; } && export GIT_SSL_NO_VERIFY=true
CA_FILE="${CA_FILE:-${OMP_CA_FILE:-}}"
[ -n "$CA_FILE" ] && [ -f "$CA_FILE" ] && export CURL_CA_BUNDLE="$CA_FILE" GIT_SSL_CAINFO="$CA_FILE"

# Persist ~/.local/bin on PATH for future shells too — pup's prebuilt-tarball
# fallback in install_pup() below lands it there (no sudo).
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
for p in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -e "$p" ] || continue
  grep -qsF "$HOME/.local/bin" "$p" 2>/dev/null && continue
  printf '\n# omp-dev-team\nexport PATH="%s:$PATH"\n' "$HOME/.local/bin" >> "$p"
done

# --- install the pup CLI ----------------------------------------------------
install_pup() {
  if have pup && [ "$NO_UPDATE" = 1 ]; then say "pup present ($(pup --version 2>/dev/null | head -1))"; return 0; fi
  if have brew; then
    say "Installing pup via Homebrew"
    brew tap datadog-labs/pack >/dev/null 2>&1 || true
    brew install datadog-labs/pack/pup 2>/dev/null || brew upgrade datadog-labs/pack/pup 2>/dev/null || true
    have pup && return 0
  fi
  # Prebuilt release tarball -> ~/.local/bin (no sudo). Asset:
  # pup_<ver>_<OS>_<arch>.tar.gz with OS in {Linux,Darwin}, arch in {x86_64,arm64}.
  have curl || { warn "need curl or brew to install pup — see https://github.com/DataDog/pup"; return 0; }
  local os arch ver url tmp
  case "$(uname -s)" in Linux) os=Linux ;; Darwin) os=Darwin ;; *) warn "unsupported OS for pup auto-install"; return 0 ;; esac
  case "$(uname -m)" in x86_64|amd64) arch=x86_64 ;; arm64|aarch64) arch=arm64 ;; *) warn "unsupported arch for pup auto-install"; return 0 ;; esac
  ver="$(curl -fsSL https://api.github.com/repos/DataDog/pup/releases/latest 2>/dev/null | grep -oE '"tag_name"[^,]*' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  [ -n "$ver" ] || { warn "could not resolve the latest pup release"; return 0; }
  url="https://github.com/DataDog/pup/releases/download/v${ver}/pup_${ver}_${os}_${arch}.tar.gz"
  say "Installing pup ${ver} (${os}/${arch}) to ~/.local/bin"
  tmp="$(mktemp -d)"; mkdir -p "$HOME/.local/bin"
  if curl -fsSL "$url" -o "$tmp/pup.tgz" && tar -xzf "$tmp/pup.tgz" -C "$tmp"; then
    if [ -f "$tmp/pup" ]; then install -m 0755 "$tmp/pup" "$HOME/.local/bin/pup"
    else find "$tmp" -type f -name pup -exec install -m 0755 {} "$HOME/.local/bin/pup" \; ; fi
    hash -r 2>/dev/null || true
    have pup && say "pup installed: $(pup --version 2>/dev/null | head -1)" || warn "pup not on PATH after install"
  else
    warn "pup download failed ($url) — install manually from https://github.com/DataDog/pup/releases"
  fi
  rm -rf "$tmp" 2>/dev/null || true
}
install_pup

# --- authentication ---------------------------------------------------------
# Prefer OAuth (`pup auth login`, opens a browser) when interactive; otherwise
# fall back to API/APP keys persisted to ~/.omp/secrets.env (chmod 600).
setup_auth() {
  [ "$NO_CONFIG" = 1 ] && return 0
  have pup || return 0
  if pup auth status >/dev/null 2>&1; then say "Datadog already authenticated (pup auth status OK)"; return 0; fi
  if [ -n "${DD_API_KEY:-}" ] || [ -n "${DD_ACCESS_TOKEN:-}" ]; then say "Datadog credentials present in environment"; return 0; fi
  if [ "$YES" = 1 ] || [ ! -r /dev/tty ]; then
    say "Skipping Datadog auth (non-interactive). Later: 'pup auth login' (OAuth) or set DD_API_KEY/DD_APP_KEY/DD_SITE."
    return 0
  fi
  printf '    Authenticate now via browser (pup auth login)? [Y/n] '; read -r ans </dev/tty || ans=""
  case "${ans:-Y}" in
    [Yy]*) pup auth login || warn "pup auth login failed — you can set DD_API_KEY/DD_APP_KEY instead." ;;
    *)
      local site key app secrets="$HOME/.omp/secrets.env" p
      printf '    DD_SITE (e.g. datadoghq.com / datadoghq.eu / us5.datadoghq.com) [datadoghq.com]: '; read -r site </dev/tty || site=""
      site="${site:-datadoghq.com}"
      printf '    DD_API_KEY (hidden): '; read -r -s key </dev/tty || key=""; echo
      printf '    DD_APP_KEY (hidden): '; read -r -s app </dev/tty || app=""; echo
      [ -z "$key$app" ] && { warn "no keys entered — skipping"; return 0; }
      mkdir -p "$(dirname "$secrets")"; touch "$secrets"; chmod 600 "$secrets"
      grep -qsF DD_SITE "$secrets"    || printf 'export DD_SITE=%q\n' "$site" >> "$secrets"
      [ -n "$key" ] && { grep -qsF DD_API_KEY "$secrets" || printf 'export DD_API_KEY=%q\n' "$key" >> "$secrets"; }
      [ -n "$app" ] && { grep -qsF DD_APP_KEY "$secrets" || printf 'export DD_APP_KEY=%q\n' "$app" >> "$secrets"; }
      for p in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do [ -e "$p" ] || continue; grep -qsF secrets.env "$p" || printf '\n[ -f "%s" ] && . "%s"\n' "$secrets" "$secrets" >> "$p"; done
      say "Datadog credentials stored in $secrets (chmod 600), sourced from your profile."
      ;;
  esac
}
setup_auth

# --- optional: install pup's embedded skills into OMP -----------------------
# Off by default: the single OMP `datadog` skill already routes everything
# through pup. --with-skills adds the dd-* skills (a lot of them) to OMP.
if [ "$WITH_SKILLS" = 1 ] && have pup; then
  say "Installing Datadog skills for OMP (pup skills install pi)"
  pup skills install pi || warn "pup skills install pi failed (newer pup may differ) — the datadog skill still works via the CLI."
fi

# --- Load the path-inject extension ------------------------------------------
# OMP does NOT load extension modules (package.json `omp.extensions`) from
# marketplace cache installs, so path-inject would otherwise never run and
# `pup` (landed in ~/.local/bin by install_pup's prebuilt-tarball fallback)
# would stay invisible to the bash tool forever, even across restarts.
# Mirror it into OMP's native user-extension dir, which is always discovered.
HERE_EXT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$HERE_EXT/extensions" ]; then
  DEST="$HOME/.omp/agent/extensions/datadog"
  rm -rf "$DEST"; mkdir -p "$DEST"; cp -R "$HERE_EXT/extensions" "$DEST/"
  [ -f "$HERE_EXT/package.json" ] && cp "$HERE_EXT/package.json" "$DEST/"
  say "path-inject loaded into $DEST — pup stays visible to OMP's bash tool after a restart"
fi

if have pup && ! bash -lc 'command -v pup' >/dev/null 2>&1; then
  warn "pup installed but NOT visible in a fresh shell yet. RESTART OMP to pick it up (path-inject now fixes this for OMP's own bash tool on restart; re-running this script again will not, since it's the already-running OMP process's env that's stale)."
fi
say "datadog ready. Restart omp and use the 'datadog' skill (it drives the pup CLI). Auth: 'pup auth login' or DD_API_KEY/DD_APP_KEY/DD_SITE."
