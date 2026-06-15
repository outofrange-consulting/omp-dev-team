#!/usr/bin/env bash
# omp-dev-team — global installer (Linux/macOS).
# Installs OMP, registers this marketplace, then interactively offers each plugin
# and its config. Updates PATH so everything works in new shells.
#
# Flags:
#   -y, --yes      non-interactive: install all plugins + apply default configs
#                  (skips the Azure PAT prompt unless env vars are already set)
#   --update       refresh things that are already installed (otherwise: skip them)
#   --no-runtimes  skip installing bun/node (assume they're present)
#   --insecure-tls disable TLS cert verification (corporate Zscaler/Trend MITM under
#                  WSL); also via OMP_INSECURE_TLS=1 — propagates to plugin installers
#   --ca-file=PATH trust a corporate root CA (Zscaler/Trend) for node/bun/git/curl/Go
#                  (Ollama) — the PROPER fix, keeps verification on; also OMP_CA_FILE.
#                  Persisted to your shell profile. Prefer this over --insecure-tls.
#   --dry-run      print actions without executing (passed to plugin installers)
#   -h, --help     this help
#
# Default policy for things already present: SKIP (idempotent, never asks, never
# overwrites). Pass --update to refresh to the latest. Exception: bun is always
# upgraded if it's below the version OMP requires.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKET="omp-dev-team"
DRY=0; YES=0; RUNTIMES=1; UPDATE=0; INSECURE_TLS=0; CA_FILE="${OMP_CA_FILE:-}"
for a in "$@"; do case "$a" in
  -y|--yes) YES=1 ;; --dry-run) DRY=1 ;; --no-runtimes) RUNTIMES=0 ;; --update) UPDATE=1 ;; --insecure-tls) INSECURE_TLS=1 ;;
  --ca-file=*) CA_FILE="${a#*=}" ;;
  -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else eval "$@"; fi; }

# Corporate TLS-intercepting proxies (Zscaler / Trend Micro under WSL) break cert
# verification. When enabled, disable it for everything this run touches: our
# curl/wget (incl. the piped upstream installers, via CURL_HOME/WGETRC), git,
# node/bun/npm, and rustup. Opt-in only (--insecure-tls or OMP_INSECURE_TLS=1).
enable_insecure_tls() {
  warn "Insecure TLS: certificate verification DISABLED for this run (corporate MITM proxy)."
  export GIT_SSL_NO_VERIFY=true NODE_TLS_REJECT_UNAUTHORIZED=0 NPM_CONFIG_STRICT_SSL=false \
         RUSTUP_USE_CURL=1 CARGO_HTTP_CHECK_REVOKE=false OMP_INSECURE_TLS=1
  local d; d="$(mktemp -d 2>/dev/null || echo "/tmp/omp-tls.$$")"; mkdir -p "$d"
  printf 'insecure\n' > "$d/.curlrc"; printf 'check_certificate = off\n' > "$d/.wgetrc"
  export CURL_HOME="$d" WGETRC="$d/.wgetrc"
}
{ [ "$INSECURE_TLS" = 1 ] || [ -n "${OMP_INSECURE_TLS:-}" ]; } && enable_insecure_tls

# Corporate root CA (optional, PREFERRED over --insecure-tls): trust a custom CA
# for everything — node/bun (NODE_EXTRA_CA_CERTS), Go/Ollama + curl + python
# (SSL_CERT_FILE/CURL_CA_BUNDLE/REQUESTS_CA_BUNDLE), git (GIT_SSL_CAINFO) — and
# persist it to the shell profile so `omp` and `ollama pull` trust it later too.
PROFILES=("$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc")
trust_ca() {
  local f="$1" abs v p
  [ -f "$f" ] || { warn "CA file not found: $f (skipping)"; return 0; }
  abs="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
  say "Trusting corporate CA: $abs"
  for v in OMP_CA_FILE NODE_EXTRA_CA_CERTS SSL_CERT_FILE CURL_CA_BUNDLE GIT_SSL_CAINFO REQUESTS_CA_BUNDLE; do export "$v=$abs"; done
  [ "$DRY" = 1 ] && { echo "  [dry-run] persist CA env vars to your shell profile"; return 0; }
  [ -e "$HOME/.profile" ] || : > "$HOME/.profile"
  for p in "${PROFILES[@]}"; do
    [ -e "$p" ] || continue
    grep -qsF "OMP_CA_FILE=" "$p" && continue
    { echo ""; echo "# omp-dev-team corporate CA"; for v in OMP_CA_FILE NODE_EXTRA_CA_CERTS SSL_CERT_FILE CURL_CA_BUNDLE GIT_SSL_CAINFO REQUESTS_CA_BUNDLE; do printf 'export %s=%q\n' "$v" "$abs"; done; } >> "$p"
  done
}
[ -n "$CA_FILE" ] && trust_ca "$CA_FILE"

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

# true if installed $1 version is >= $2 (dotted). awk-based for portability
# (macOS `sort` has no -V).
version_ge() {
  awk -v v1="$1" -v v2="$2" 'function cmp(a,b){n=split(a,A,".");m=split(b,B,".");k=(n>m?n:m);for(i=1;i<=k;i++){d=(A[i]+0)-(B[i]+0);if(d)return d}return 0} BEGIN{exit !(cmp(v1,v2)>=0)}'
}

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
  if have brew; then run "brew install node"; return; fi
  # Official prebuilt LTS tarball -> ~/.local, symlinked into ~/.local/bin. No
  # version manager (fnm/nvm) — deterministic and persists to new shells.
  have curl || { warn "need curl or brew to install Node — see https://nodejs.org"; return; }
  local os arch ver file url tmp dir b
  case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) warn "auto Node unsupported on $(uname -s)"; return ;; esac
  case "$(uname -m)" in x86_64|amd64) arch=x64 ;; aarch64|arm64) arch=arm64 ;; armv7l) arch=armv7l ;; *) warn "auto Node unsupported on $(uname -m)"; return ;; esac
  # Resolve the latest LTS version from the dist index (newest-first; first entry
  # whose "lts" is a name, not false). No jq/node/python needed.
  ver="$(curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null | tr '}' '\n' | grep -m1 '"lts":"' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  [ -n "$ver" ] || { warn "could not resolve a Node LTS version (nodejs.org/dist)"; return; }
  file="node-${ver}-${os}-${arch}.tar.gz"
  url="https://nodejs.org/dist/${ver}/${file}"
  if [ "$DRY" = 1 ]; then echo "  [dry-run] curl $url | tar -xz -> ~/.local; symlink node/npm/npx into ~/.local/bin"; ensure_path "$HOME/.local/bin"; return; fi
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

bold "omp-dev-team installer"
echo "Repo: $ROOT"

# --- 0) Runtimes (bun, node) -----------------------------------------------
if [ "$RUNTIMES" = 1 ]; then
  say "Ensuring runtimes"
  ensure_bun
  ensure_node
else
  say "Skipping runtime install (--no-runtimes)"
fi

# --- 1) OMP ----------------------------------------------------------------
if have omp && [ "$UPDATE" = 0 ]; then ok "omp present ($(omp --version 2>/dev/null | head -1)) (skip; --update to refresh)"
elif have omp; then say "Updating OMP"; run "bun add -g @oh-my-pi/pi-coding-agent@latest || curl -fsSL https://omp.sh/install | sh"
else say "Installing OMP (latest)"; run "curl -fsSL https://omp.sh/install | sh"; fi
# Make omp + tool dirs available now and in future shells. Create them first so
# ensure_path adds them even before later steps drop binaries in (e.g. rtk).
for d in "$HOME/.local/bin" "$HOME/.bun/bin"; do mkdir -p "$d" 2>/dev/null || true; ensure_path "$d"; done
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
  [ "$INSECURE_TLS" = 1 ] && flags="$flags --insecure-tls"
  [ "$UPDATE" = 1 ] && [ "$name" = token-diet ] && flags="$flags --update"
  if have omp; then
    if omp plugin list 2>/dev/null | grep -q "${name}@${MARKET}"; then
      if [ "$UPDATE" = 1 ]; then run "omp plugin install --force ${name}@${MARKET} || true"
      else ok "plugin ${name} already installed (skip; --update to refresh)"; fi
    else run "omp plugin install ${name}@${MARKET} || true"; fi
  fi
  # A plugin's optional tooling failing must not abort the whole run; the doctor
  # reports the real end state.
  if [ -f "$dir/install.sh" ]; then
    run "bash \"$dir/install.sh\" $flags ${YES:+-y} || true"
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

if ask "Install local-llm (run roles on local GPU models; needs >=8GB VRAM)?" "N"; then
  plug local-llm "$ROOT/plugins/local-llm"
fi

if ask "Install azure-devops-fs (Azure DevOps as a filesystem)?" "N"; then
  # The plugin installer ensures Node, pre-warms the MCP server, and (when
  # interactive) prompts for the org/project/PAT and persists them.
  plug azure-devops-fs "$ROOT/plugins/azure-devops-fs"
  echo "  Reminder: enable the 'azure-devops' MCP server (enabled:true) in your .mcp.json."
fi

# --- 4) Doctor (verify everything is present) ------------------------------
bold "Doctor"
[ "$DRY" = 1 ] && { echo "(dry-run — skipping verification)"; exit 0; }
# Refresh PATH for dirs that may have been created during plugin installs.
for d in "$HOME/.local/bin" "$HOME/.bun/bin"; do ensure_path "$d"; done
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
check omp      required "omp --version"
check ctx-wire optional "ctx-wire --version"
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
