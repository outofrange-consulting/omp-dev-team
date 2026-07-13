#!/usr/bin/env bash
# omp-dev-team for GitHub Copilot CLI — global installer (Linux/macOS).
#
# Installs the GitHub Copilot CLI, then interactively offers each component of the
# chain — you check the ones you want:
#
#   * dev-team   — orchestrator + workflow/critic agents, blocking guard hooks
#                  (plan-gate, path/freeze/spec/destructive/review-gate), the `dt`
#                  gate CLI, and the operating-manual copilot-instructions.
#   * token-diet — ctx-wire (shell-output compression + secret scrub), the
#                  codebase-memory-mcp MCP server, and a postToolUse output
#                  compressor; caveman/yagni discipline.
#   * datadog    — the Datadog `pup` CLI + a `datadog` agent.
#
# Everything is brought UP TO DATE by default. Your Copilot config (mcp-config.json,
# agents) is MERGED, never clobbered — anything you've set is preserved.
#
# Flags:
#   -y, --yes        non-interactive: install all components (skips secret prompts
#                    unless env vars are set)
#   --no-update      keep tools already installed (don't refresh them)
#   --no-runtimes    skip installing Node (assume Node >= 22 is present)
#   --no-arm         don't offer to arm the dev-team guards in the current repo
#   --insecure-tls   disable TLS cert verification (corporate Zscaler/Trend MITM);
#                    also via OMP_INSECURE_TLS=1 — propagates to component installers
#   --ca-file=PATH   trust a corporate root CA for node/npm/git/curl (the proper
#                    fix, keeps verification on); also OMP_CA_FILE. Persisted.
#   --ca-from-windows  on WSL, export the Windows trust store and trust it
#   --no-config      don't write/merge ~/.copilot config (agents/mcp/instructions)
#   -h, --help       this help
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPILOT_HOME="${COPILOT_HOME:-$HOME/.copilot}"
YES=0; RUNTIMES=1; NO_UPDATE=0; INSECURE_TLS=0; CA_FROM_WIN=0; NO_CONFIG=0; NO_ARM=0; CA_FILE="${OMP_CA_FILE:-}"
for a in "$@"; do case "$a" in
  -y|--yes) YES=1 ;; --no-runtimes) RUNTIMES=0 ;; --no-update) NO_UPDATE=1 ;; --insecure-tls) INSECURE_TLS=1 ;;
  --ca-file=*) CA_FILE="${a#*=}" ;; --ca-from-windows) CA_FROM_WIN=1 ;; --no-config) NO_CONFIG=1 ;; --no-arm) NO_ARM=1 ;;
  -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { eval "$@"; }

PROFILES=("$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc")

# --- TLS / corporate CA (mirrors the OMP installer) -------------------------
enable_insecure_tls() {
  warn "Insecure TLS: certificate verification DISABLED for this run (corporate MITM proxy)."
  export GIT_SSL_NO_VERIFY=true NODE_TLS_REJECT_UNAUTHORIZED=0 NPM_CONFIG_STRICT_SSL=false OMP_INSECURE_TLS=1
  local d; d="$(mktemp -d 2>/dev/null || echo "/tmp/omp-tls.$$")"; mkdir -p "$d"
  printf 'insecure\n' > "$d/.curlrc"; printf 'check_certificate = off\n' > "$d/.wgetrc"
  export CURL_HOME="$d" WGETRC="$d/.wgetrc"
}
trust_ca() {
  local f="$1" abs v p
  [ -f "$f" ] || { warn "CA file not found: $f (skipping)"; return 0; }
  abs="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
  say "Trusting corporate CA: $abs"
  for v in OMP_CA_FILE NODE_EXTRA_CA_CERTS SSL_CERT_FILE CURL_CA_BUNDLE GIT_SSL_CAINFO REQUESTS_CA_BUNDLE; do export "$v=$abs"; done
  [ -e "$HOME/.profile" ] || : > "$HOME/.profile"
  for p in "${PROFILES[@]}"; do
    [ -e "$p" ] || continue
    grep -qsF "OMP_CA_FILE=" "$p" && continue
    { echo ""; echo "# omp-dev-team-copilot corporate CA"; for v in OMP_CA_FILE NODE_EXTRA_CA_CERTS SSL_CERT_FILE CURL_CA_BUNDLE GIT_SSL_CAINFO REQUESTS_CA_BUNDLE; do printf 'export %s=%q\n' "$v" "$abs"; done; } >> "$p"
  done
}
is_wsl() { grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; }
ca_from_windows() {
  local ps out bundle sys c
  ps="$(command -v powershell.exe 2>/dev/null || true)"
  [ -n "$ps" ] || { [ -x "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" ] && ps="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"; }
  [ -n "$ps" ] || { warn "powershell.exe not found — are you in WSL? Use --ca-file=PATH instead."; return 1; }
  say "Exporting Windows root CAs via PowerShell…"
  out="$("$ps" -NoProfile -Command 'Get-ChildItem Cert:\LocalMachine\Root, Cert:\CurrentUser\Root | %{ "-----BEGIN CERTIFICATE-----"; [Convert]::ToBase64String($_.RawData,"InsertLineBreaks"); "-----END CERTIFICATE-----" }' 2>/dev/null | tr -d '\r')"
  printf '%s' "$out" | grep -q 'BEGIN CERTIFICATE' || { warn "could not read the Windows certificate store"; return 1; }
  bundle="$COPILOT_HOME/windows-ca-bundle.pem"; mkdir -p "$(dirname "$bundle")"
  sys=""; for c in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/cert.pem; do [ -f "$c" ] && { sys="$c"; break; }; done
  { [ -n "$sys" ] && cat "$sys"; printf '%s\n' "$out"; } > "$bundle"
  say "Wrote CA bundle: $bundle ($(grep -c 'BEGIN CERTIFICATE' "$bundle") certs)"
  CA_FILE="$bundle"
}

if [ "$INSECURE_TLS" = 1 ]; then enable_insecure_tls
elif [ -n "${OMP_INSECURE_TLS:-}" ]; then
  warn "OMP_INSECURE_TLS set — pass --insecure-tls to disable verification explicitly. Proceeding with verification ON."
fi

ask() {
  local q="$1" def="${2:-Y}" ans
  if [ "$YES" = 1 ]; then return 0; fi
  if [ ! -r /dev/tty ]; then case "$def" in [Yy]*) return 0 ;; *) return 1 ;; esac; fi
  if [ "$def" = "Y" ]; then q="$q [Y/n] "; else q="$q [y/N] "; fi
  read -r -p "$q" ans </dev/tty || ans=""
  ans="${ans:-$def}"
  case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

ensure_path() {  # add $1 to PATH in this session + persist (idempotent)
  local dir="$1" p
  [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || true
  case ":$PATH:" in *":$dir:"*) ;; *) PATH="$dir:$PATH"; export PATH ;; esac
  [ -e "$HOME/.profile" ] || : > "$HOME/.profile"
  for p in "${PROFILES[@]}"; do
    [ -e "$p" ] || continue
    grep -qsF "$dir" "$p" 2>/dev/null && continue
    printf '\n# omp-dev-team-copilot\nexport PATH="%s:$PATH"\n' "$dir" >> "$p"
  done
}

version_ge() { awk -v v1="$1" -v v2="$2" 'function cmp(a,b){n=split(a,A,".");m=split(b,B,".");k=(n>m?n:m);for(i=1;i<=k;i++){d=(A[i]+0)-(B[i]+0);if(d)return d}return 0} BEGIN{exit !(cmp(v1,v2)>=0)}'; }

MIN_NODE="22.0.0"
node_version() { node --version 2>/dev/null | sed 's/^v//'; }
ensure_node() {  # Copilot CLI needs Node >= 22
  if have node && version_ge "$(node_version || echo 0)" "$MIN_NODE" && [ "$NO_UPDATE" = 1 ]; then ok "node $(node --version)"; return; fi
  if have node && version_ge "$(node_version || echo 0)" "$MIN_NODE"; then ok "node $(node --version)"; return; fi
  say "Installing Node.js (LTS, >= $MIN_NODE)"
  if have brew; then run "brew install node || brew upgrade node || true"; hash -r 2>/dev/null || true; fi
  if have node && version_ge "$(node_version || echo 0)" "$MIN_NODE"; then ok "node $(node --version)"; return; fi
  have curl || { warn "need curl or brew to install Node >= $MIN_NODE — see https://nodejs.org"; return; }
  local os arch ver file url tmp dir b
  case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) warn "auto Node unsupported on $(uname -s)"; return ;; esac
  case "$(uname -m)" in x86_64|amd64) arch=x64 ;; aarch64|arm64) arch=arm64 ;; armv7l) arch=armv7l ;; *) warn "auto Node unsupported on $(uname -m)"; return ;; esac
  ver="$(curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null | tr '}' '\n' | grep -m1 '"lts":"' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  [ -n "$ver" ] || { warn "could not resolve a Node LTS version"; return; }
  file="node-${ver}-${os}-${arch}.tar.gz"; url="https://nodejs.org/dist/${ver}/${file}"
  tmp="$(mktemp -d)"; mkdir -p "$HOME/.local/bin"
  if curl -fsSL "$url" -o "$tmp/node.tgz" && tar -xzf "$tmp/node.tgz" -C "$HOME/.local"; then
    dir="$HOME/.local/${file%.tar.gz}"
    for b in node npm npx; do [ -e "$dir/bin/$b" ] && ln -sf "$dir/bin/$b" "$HOME/.local/bin/$b"; done
    ensure_path "$HOME/.local/bin"; hash -r 2>/dev/null || true
    have node && ok "node $(node --version)" || warn "Node installed to $dir but not on PATH"
  else
    warn "Node download/extract failed — install manually from https://nodejs.org"
  fi
  rm -rf "$tmp" 2>/dev/null || true
}

bold "omp-dev-team for GitHub Copilot CLI"
echo "Repo: $ROOT"
echo "Copilot home: $COPILOT_HOME"

# --- TLS / corporate CA -----------------------------------------------------
if [ "$CA_FROM_WIN" = 1 ]; then
  ca_from_windows || warn "Windows CA import failed — pass --ca-file=… or --insecure-tls"
elif [ -z "$CA_FILE" ] && [ "$INSECURE_TLS" = 0 ] && is_wsl && [ "$YES" = 0 ] && [ -r /dev/tty ]; then
  ask "WSL detected — import the Windows root CAs (covers corporate Zscaler/Trend)?" "Y" && { ca_from_windows || true; }
fi
[ -n "$CA_FILE" ] && trust_ca "$CA_FILE"

# --- 0) Runtimes (Node) -----------------------------------------------------
if [ "$RUNTIMES" = 1 ]; then say "Ensuring runtimes"; ensure_node
else say "Skipping runtime install (--no-runtimes)"; fi
ensure_path "$HOME/.local/bin"

# --- 1) GitHub Copilot CLI --------------------------------------------------
ensure_copilot() {
  if have copilot && [ "$NO_UPDATE" = 1 ]; then ok "copilot present ($(copilot --version 2>/dev/null | head -1))"; return; fi
  if have copilot; then say "Updating GitHub Copilot CLI"; else say "Installing GitHub Copilot CLI"; fi
  if have npm; then
    run "npm install -g @github/copilot@latest || true"; hash -r 2>/dev/null || true
  fi
  if ! have copilot; then
    if have brew; then run "brew install --cask copilot-cli || brew upgrade --cask copilot-cli || true"
    elif have curl; then run "curl -fsSL https://gh.io/copilot-install | bash || true"
    else warn "need npm, brew, or curl to install Copilot CLI — see https://docs.github.com/copilot/how-tos/set-up/install-copilot-cli"; fi
  fi
  hash -r 2>/dev/null || true
  have copilot && ok "copilot $(copilot --version 2>/dev/null | head -1)" || warn "copilot not on PATH yet — open a new shell after this"
}
ensure_copilot

# Component installers inherit the TLS/CA + update decisions.
COMMON_FLAGS=""
[ "$INSECURE_TLS" = 1 ] && COMMON_FLAGS="$COMMON_FLAGS --insecure-tls"
[ "$NO_UPDATE" = 1 ] && COMMON_FLAGS="$COMMON_FLAGS --no-update"
[ "$NO_CONFIG" = 1 ] && COMMON_FLAGS="$COMMON_FLAGS --no-config"
[ "$YES" = 1 ] && COMMON_FLAGS="$COMMON_FLAGS -y"
export COPILOT_HOME OMP_CA_FILE="${CA_FILE:-${OMP_CA_FILE:-}}"

pack() {  # pack <name> <dir>
  local name="$1" dir="$2"
  [ -f "$dir/install.sh" ] || { warn "$name: no install.sh"; return 0; }
  say "Installing component: $name"
  run "bash \"$dir/install.sh\" $COMMON_FLAGS || true"
}

# --- 2) Per-component checkboxes --------------------------------------------
bold "Components — check the ones you want"
SEL_DEVTEAM=0; SEL_TOKENDIET=0; SEL_DATADOG=0

if ask "Install dev-team (agentic pipeline: agents + blocking guard hooks + the dt gate CLI)?"; then
  pack dev-team "$ROOT/packs/dev-team"; SEL_DEVTEAM=1
fi
if ask "Install token-diet (ctx-wire + codebase-memory-mcp + output-compression hook)?"; then
  pack token-diet "$ROOT/packs/token-diet"; SEL_TOKENDIET=1
fi
if ask "Install datadog (pup CLI + datadog agent)?" "N"; then
  pack datadog "$ROOT/packs/datadog"; SEL_DATADOG=1
fi

# --- 3) Offer to arm the dev-team guards in the current repo -----------------
# Copilot CLI loads hooks from the project (.github/hooks), so the blocking guards
# are armed per-repo. dt init writes them (and the token-diet postToolUse hook if
# installed) plus the operating-manual copilot-instructions.
if [ "$SEL_DEVTEAM" = 1 ] && [ "$NO_ARM" = 0 ] && have node; then
  if [ -d ".git" ] && ask "Arm the dev-team guards in the CURRENT repo ($(pwd))? (writes .github/hooks + .github/copilot-instructions.md)" "N"; then
    run "node \"$COPILOT_HOME/dev-team/dt.mjs\" init . || true"
  else
    echo "  Skipped. Arm any repo later with: dt init  (run from inside that repo)"
  fi
fi

# --- 4) Doctor --------------------------------------------------------------
bold "Doctor"
ensure_path "$HOME/.local/bin"; hash -r 2>/dev/null || true
fail=0
check() {
  local t="$1" req="$2" vc="${3:-}"
  if have "$t"; then
    local v=""; [ -n "$vc" ] && v="$(eval "$vc" 2>/dev/null | head -1)"
    ok "$t ${v:+($v)} -> $(command -v "$t")"
  elif [ "$req" = required ]; then warn "$t MISSING (required)"; fail=1
  else warn "$t not found (optional)"; fi
}
check git     required    "git --version"
check node    required    "node --version"
check copilot required    "copilot --version"
[ "$SEL_DEVTEAM" = 1 ]  && check dt  optional "dt help >/dev/null 2>&1 && echo ok"
[ "$SEL_TOKENDIET" = 1 ] && { check ctx-wire optional "ctx-wire --version"; check codebase-memory-mcp optional "codebase-memory-mcp --version"; }
[ "$SEL_DATADOG" = 1 ]  && check pup optional "pup --version"

if [ "$NO_CONFIG" = 0 ]; then
  echo "  agents installed:"; ls "$COPILOT_HOME/agents"/*.agent.md 2>/dev/null | sed 's#.*/#    #' || echo "    (none)"
  [ -f "$COPILOT_HOME/mcp-config.json" ] && ok "mcp-config.json present ($COPILOT_HOME/mcp-config.json)"
fi

echo
[ "$fail" = 0 ] && bold "All set ✓" || bold "Finished with warnings — see above"
echo "Open a NEW shell (or 'source ~/.profile'), then run: copilot"
echo "First run: /login (GitHub Copilot). Pick a model with /model. Use agents with /agent <name>."
[ "$SEL_DEVTEAM" = 1 ] && echo "Dev-team flow: dt scope -> /agent plan -> dt plan-approve -> /agent build -> /agent review -> dt review-approve -> /agent pr"
[ "$fail" = 0 ] || exit 1
