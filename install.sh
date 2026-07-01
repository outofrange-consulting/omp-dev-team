#!/usr/bin/env bash
# omp-dev-team — global installer (Linux/macOS).
# Installs OMP, registers this marketplace, then interactively offers each plugin
# and its config. Updates PATH so everything works in new shells.
#
# Everything is brought UP TO DATE by default — runtimes, OMP, plugins and their
# tooling are refreshed to the latest on every run. Your config is MERGED, never
# clobbered: anything you've already set is preserved.
#
# Flags:
#   -y, --yes      non-interactive: install all plugins + merge default configs
#                  (skips credential prompts unless env vars are already set)
#   --no-update    keep tools that are already installed (don't refresh them)
#   --no-runtimes  skip installing bun/node (assume they're present)
#   --insecure-tls disable TLS cert verification (corporate Zscaler/Trend MITM under
#                  WSL); also via OMP_INSECURE_TLS=1 — propagates to plugin installers
#   --ca-file=PATH trust a corporate root CA (Zscaler/Trend) for node/bun/git/curl/Go
#                  (Ollama) — the PROPER fix, keeps verification on; also OMP_CA_FILE.
#                  Persisted to your shell profile. Prefer this over --insecure-tls.
#   --ca-from-windows  on WSL, auto-export the Windows trust store (incl. corporate
#                  CAs) and trust it. (Offered automatically when WSL is detected.)
#                  To install the CA into WSL's system store instead, run
#                  scripts/wsl-trust-zscaler.ps1 from Windows PowerShell.
#   --no-config    don't write/merge ~/.omp/agent config (keep your config as-is)
#   -h, --help     this help
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKET="omp-dev-team"
YES=0; RUNTIMES=1; NO_UPDATE=0; INSECURE_TLS=0; CA_FROM_WIN=0; NO_CONFIG=0; CA_FILE="${OMP_CA_FILE:-}"
for a in "$@"; do case "$a" in
  -y|--yes) YES=1 ;; --no-runtimes) RUNTIMES=0 ;; --no-update) NO_UPDATE=1 ;; --insecure-tls) INSECURE_TLS=1 ;;
  --ca-file=*) CA_FILE="${a#*=}" ;; --ca-from-windows) CA_FROM_WIN=1 ;; --no-config) NO_CONFIG=1 ;;
  -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { eval "$@"; }
CFG="$HOME/.omp/agent/config.yml"

# Corporate TLS-intercepting proxies (Zscaler / Trend Micro under WSL) break cert
# verification. When enabled, disable it for everything this run touches.
enable_insecure_tls() {
  warn "Insecure TLS: certificate verification DISABLED for this run (corporate MITM proxy)."
  export GIT_SSL_NO_VERIFY=true NODE_TLS_REJECT_UNAUTHORIZED=0 NPM_CONFIG_STRICT_SSL=false \
         RUSTUP_USE_CURL=1 CARGO_HTTP_CHECK_REVOKE=false OMP_INSECURE_TLS=1
  local d; d="$(mktemp -d 2>/dev/null || echo "/tmp/omp-tls.$$")"; mkdir -p "$d"
  printf 'insecure\n' > "$d/.curlrc"; printf 'check_certificate = off\n' > "$d/.wgetrc"
  export CURL_HOME="$d" WGETRC="$d/.wgetrc"
}
# Enable insecure TLS only on an explicit opt-in. A bare OMP_INSECURE_TLS left in
# the environment must NOT silently disable certificate verification for the whole
# install: confirm it interactively, or skip it (verification stays ON) when
# unattended. The explicit --insecure-tls flag always wins. enable_insecure_tls
# re-exports OMP_INSECURE_TLS=1 so child installers still inherit the decision.
if [ "$INSECURE_TLS" = 1 ]; then
  enable_insecure_tls
elif [ -n "${OMP_INSECURE_TLS:-}" ]; then
  if [ "$YES" = 0 ] && [ -r /dev/tty ]; then
    ask "OMP_INSECURE_TLS is set in your environment — DISABLE TLS certificate verification for this install?" "N" \
      && enable_insecure_tls \
      || warn "Keeping TLS verification ON (pass --insecure-tls to disable it explicitly)."
  else
    warn "Ignoring stray OMP_INSECURE_TLS in non-interactive mode — pass --insecure-tls to disable TLS verification explicitly. Proceeding with verification ON."
  fi
fi

# Corporate root CA (PREFERRED over --insecure-tls): trust a custom CA for
# everything — node/bun, Go/Ollama, curl, python, git — and persist it.
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
    { echo ""; echo "# omp-dev-team corporate CA"; for v in OMP_CA_FILE NODE_EXTRA_CA_CERTS SSL_CERT_FILE CURL_CA_BUNDLE GIT_SSL_CAINFO REQUESTS_CA_BUNDLE; do printf 'export %s=%q\n' "$v" "$abs"; done; } >> "$p"
  done
}
is_wsl() { grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; }
# Export the Windows trust store (incl. corporate roots) as a PEM bundle combined
# with the Linux system roots, and point CA_FILE at it.
ca_from_windows() {
  local ps out bundle sys c
  ps="$(command -v powershell.exe 2>/dev/null || true)"
  [ -n "$ps" ] || { [ -x "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" ] && ps="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"; }
  [ -n "$ps" ] || { warn "powershell.exe not found — are you in WSL? Use --ca-file=PATH instead."; return 1; }
  say "Exporting Windows root CAs via PowerShell…"
  out="$("$ps" -NoProfile -Command 'Get-ChildItem Cert:\LocalMachine\Root, Cert:\CurrentUser\Root | %{ "-----BEGIN CERTIFICATE-----"; [Convert]::ToBase64String($_.RawData,"InsertLineBreaks"); "-----END CERTIFICATE-----" }' 2>/dev/null | tr -d '\r')"
  printf '%s' "$out" | grep -q 'BEGIN CERTIFICATE' || { warn "could not read the Windows certificate store"; return 1; }
  bundle="$HOME/.omp/windows-ca-bundle.pem"; mkdir -p "$(dirname "$bundle")"
  sys=""; for c in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/cert.pem; do [ -f "$c" ] && { sys="$c"; break; }; done
  { [ -n "$sys" ] && cat "$sys"; printf '%s\n' "$out"; } > "$bundle"
  say "Wrote CA bundle: $bundle ($(grep -c 'BEGIN CERTIFICATE' "$bundle") certs)"
  CA_FILE="$bundle"
}

# ask "Question?" default(Y/n) -> returns 0 for yes
ask() {
  local q="$1" def="${2:-Y}" ans
  if [ "$YES" = 1 ]; then return 0; fi
  if [ ! -r /dev/tty ]; then case "$def" in [Yy]*) return 0 ;; *) return 1 ;; esac; fi
  if [ "$def" = "Y" ]; then q="$q [Y/n] "; else q="$q [y/N] "; fi
  read -r -p "$q" ans </dev/tty || ans=""
  ans="${ans:-$def}"
  case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
}
# prompt "label" [hidden] -> echoes the typed value (empty if none / non-interactive)
# Pass "hidden" as the 2nd arg for secrets (PATs/keys): uses `read -s` so the
# input is NOT echoed to the terminal, and prints a trailing newline (since -s
# suppresses the echo of the Enter keypress). Matches the sibling installers.
prompt() {
  local label="$1" mode="${2:-}" ans=""
  { [ "$YES" = 1 ] || [ ! -r /dev/tty ]; } && { printf '%s' ""; return 0; }
  if [ "$mode" = hidden ]; then
    read -r -s -p "    $label: " ans </dev/tty || ans=""
    printf '\n' >/dev/tty
  else
    read -r -p "    $label: " ans </dev/tty || ans=""
  fi
  printf '%s' "$ans"
}

PROFILES=("$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc")
ensure_path() {  # add $1 to PATH in this session + persist to profiles (idempotent)
  local dir="$1" p
  [ -d "$dir" ] || return 0
  case ":$PATH:" in *":$dir:"*) ;; *) PATH="$dir:$PATH"; export PATH ;; esac
  [ -e "$HOME/.profile" ] || : > "$HOME/.profile"
  for p in "${PROFILES[@]}"; do
    [ -e "$p" ] || continue
    grep -qsF "$dir" "$p" 2>/dev/null && continue
    printf '\n# omp-dev-team\nexport PATH="%s:$PATH"\n' "$dir" >> "$p"
  done
}

# true if installed $1 version is >= $2 (dotted). awk-based for portability.
version_ge() {
  awk -v v1="$1" -v v2="$2" 'function cmp(a,b){n=split(a,A,".");m=split(b,B,".");k=(n>m?n:m);for(i=1;i<=k;i++){d=(A[i]+0)-(B[i]+0);if(d)return d}return 0} BEGIN{exit !(cmp(v1,v2)>=0)}'
}

MIN_BUN="1.3.14"
ensure_bun() {  # OMP requires bun >= MIN_BUN
  if have bun && version_ge "$(bun --version 2>/dev/null || echo 0)" "$MIN_BUN" && [ "$NO_UPDATE" = 1 ]; then
    ok "bun $(bun --version)"; ensure_path "$HOME/.bun/bin"; return
  fi
  say "Installing bun (>= $MIN_BUN)"
  if [ "$(uname -s)" = "Darwin" ] && have brew; then
    brew install bun || brew upgrade bun || true; hash -r 2>/dev/null || true
  fi
  if ! have bun || ! version_ge "$(bun --version 2>/dev/null || echo 0)" "$MIN_BUN"; then
    local i
    for i in 1 2 3; do curl -fsSL https://bun.sh/install | bash && break; warn "bun download failed ($i/3) — retrying…"; sleep $((i * 3)); done
  fi
  ensure_path "$HOME/.bun/bin"; hash -r 2>/dev/null || true
  have bun && ok "bun $(bun --version)" || warn "bun install failed — see https://bun.sh"
}
ensure_node() {  # needed by azure-devops-fs (npx), ast-grep, ctx7 and handy generally
  if have node && [ "$NO_UPDATE" = 1 ]; then ok "node $(node --version)"; return; fi
  say "Installing Node.js (LTS)"
  if have brew; then run "brew install node || brew upgrade node || true"; return; fi
  have curl || { warn "need curl or brew to install Node — see https://nodejs.org"; return; }
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

# Run a JS file with whatever runtime is available (bun preferred, node fallback).
js_run() { if have bun; then bun "$@"; elif have node; then node "$@"; else return 1; fi; }

bold "omp-dev-team installer"
echo "Repo: $ROOT"

# --- TLS / corporate CA -----------------------------------------------------
if [ "$CA_FROM_WIN" = 1 ]; then
  ca_from_windows || warn "Windows CA import failed — pass --ca-file=… or --insecure-tls"
elif [ -z "$CA_FILE" ] && [ "$INSECURE_TLS" = 0 ] && is_wsl && [ "$YES" = 0 ] && [ -r /dev/tty ]; then
  ask "WSL detected — import the Windows root CAs (covers corporate Zscaler/Trend)?" "Y" && { ca_from_windows || true; }
fi
[ -n "$CA_FILE" ] && trust_ca "$CA_FILE"

# --- 0) Runtimes (bun, node) -----------------------------------------------
if [ "$RUNTIMES" = 1 ]; then say "Ensuring runtimes"; ensure_bun; ensure_node
else say "Skipping runtime install (--no-runtimes)"; fi

# --- 1) OMP ----------------------------------------------------------------
if have omp && [ "$NO_UPDATE" = 1 ]; then ok "omp present ($(omp --version 2>/dev/null | head -1))"
elif have omp; then say "Updating OMP"; run "bun add -g @oh-my-pi/pi-coding-agent@latest || curl -fsSL https://omp.sh/install | sh"
else say "Installing OMP (latest)"; run "curl -fsSL https://omp.sh/install | sh"; fi
for d in "$HOME/.local/bin" "$HOME/.bun/bin"; do mkdir -p "$d" 2>/dev/null || true; ensure_path "$d"; done
have omp || warn "omp not on PATH yet — open a new shell or 'source ~/.profile' after this"

# --- 2) Register the marketplace -------------------------------------------
if have omp; then say "Registering marketplace ($MARKET)"; run "omp plugin marketplace add \"$ROOT\" || true"; run "omp plugin marketplace update \"$MARKET\" || true"; fi

# OMP does NOT load extension modules from marketplace cache installs — only from
# the native extension dirs. Mirror a plugin's extension modules into the user
# native dir (~/.omp/agent/extensions/<name>/), which OMP always discovers.
install_extensions() {  # install_extensions <name> <dir>
  local name="$1" dir="$2" dest="$HOME/.omp/agent/extensions/$name"
  [ -d "$dir/extensions" ] || return 0
  rm -rf "$dest"; mkdir -p "$dest"
  cp -R "$dir/extensions" "$dest/"
  [ -f "$dir/package.json" ] && cp "$dir/package.json" "$dest/"
  ok "$name extension loaded"
}

# (re)install a plugin to the latest + run its tool installer.
plug() {  # plug <name> <dir>
  local name="$1" dir="$2" flags=""
  [ "$INSECURE_TLS" = 1 ] && flags="$flags --insecure-tls"
  [ "$NO_UPDATE" = 1 ] && flags="$flags --no-update"
  [ "$name" = token-diet ] && flags="$flags --no-config"   # global config merge owns config.yml
  if have omp; then run "omp plugin install --force ${name}@${MARKET} || true"; fi
  install_extensions "$name" "$dir"
  if [ -f "$dir/install.sh" ]; then run "bash \"$dir/install.sh\" $flags ${YES:+-y} || true"; fi
}

# --- config merge helpers (preserve existing user values) -------------------
# cfg_has detects a TRUE top-level YAML key only: anchored at column 0
# (`^<key>:`), so an indented key or the key appearing inside a string/comment
# does NOT count as a match. This prevents cfg_add from appending a SECOND
# top-level block for a key that already exists (most YAML parsers then clobber
# one or error). The key is regex-escaped before anchoring.
cfg_has() {
  local k; k="$(printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g')"
  grep -qE "^${k}:([[:space:]]|\$)" "$CFG" 2>/dev/null
}
cfg_add() {  # cfg_add <topkey> ; YAML block on stdin ; append only if topkey absent
  local key="$1" block; block="$(cat)"
  cfg_has "$key" && return 0
  printf '\n%s\n' "$block" >> "$CFG"
}

# Merge the managed model-roles/skills/isolation defaults into the OMP config.
# Existing top-level keys are ALWAYS preserved — we only add what's missing.
write_config() {
  [ "$NO_CONFIG" = 1 ] && { say "Keeping your OMP config as-is (--no-config)"; return 0; }
  [ "${SEL_DEVTEAM:-0}${SEL_COPILOT:-0}${SEL_TOKENDIET:-0}${SEL_OAI_COMPAT:-0}" = "0000" ] && return 0
  mkdir -p "$(dirname "$CFG")"; touch "$CFG"
  bold "OMP config"; say "Merging defaults into $CFG (existing values preserved)"
  grep -q "omp-dev-team" "$CFG" 2>/dev/null || printf '# omp-dev-team — merged defaults (your existing values are preserved on re-run).\n' >> "$CFG"

  if [ "${SEL_COPILOT:-0}" = 1 ]; then
    cfg_add enabledModels       <<< "enabledModels: [github-copilot/*]"
    cfg_add modelProviderOrder  <<< "modelProviderOrder: [github-copilot]"
    cfg_add modelRoles <<'EOF'
# Models via GitHub Copilot. Run 'omp' -> /login -> GitHub Copilot first.
modelRoles:
  smol: github-copilot/gpt-5-mini
  task: github-copilot/mai-code-1-flash
  default: github-copilot/claude-sonnet-5
  plan: github-copilot/claude-sonnet-5
  slow: github-copilot/claude-opus-4.8
EOF
  elif [ "${SEL_DEVTEAM:-0}" = 1 ]; then
    cfg_add modelRoles <<'EOF'
modelRoles:
  smol: claude-haiku-4-5
  task: claude-haiku-4-5
  default: claude-sonnet-5
  plan: claude-sonnet-5
  slow: claude-opus-4-8
EOF
  fi

  if [ "${SEL_DEVTEAM:-0}" = 1 ] || [ "${SEL_TOKENDIET:-0}" = 1 ]; then
    cfg_add skills <<'EOF'
skills:
  enabled: true
  enableSkillCommands: true
  enableClaudeUser: false
  enableClaudeProject: false
EOF
  fi
  # dev-team drives everything through read/bash/edit/find/search/task + the
  # systematic-debugging skill — never the DAP debug tool or the py/js eval tool.
  if [ "${SEL_DEVTEAM:-0}" = 1 ]; then
    cfg_add debug <<'EOF'
debug:
  enabled: false
EOF
    cfg_add eval <<'EOF'
eval:
  py: false
  js: false
EOF
    cfg_add task <<'EOF'
task:
  maxRecursionDepth: 4
  simple: default
EOF
  fi
  # token-diet: hide non-essential tool schemas behind OMP's on-demand discovery.
  if [ "${SEL_TOKENDIET:-0}" = 1 ]; then
    cfg_add tools <<'EOF'
tools:
  discoveryMode: all
  essentialOverride: [read, bash, edit, write, find, search, task, todo]
EOF
  fi
  # Provider isolation: keep other tool ecosystems out of OMP (self-contained).
  cfg_add commands <<'EOF'
commands:
  enableClaudeUser: false
  enableClaudeProject: false
EOF
  # disabledProviders — the global installer and token-diet's standalone
  # installer now write an IDENTICAL list (github intentionally omitted, so the
  # Copilot/`.github` integration and copilot-preset keep working). The global
  # plug() also runs token-diet with --no-config so only one path writes here.
  # cfg_add is top-level-anchored, so a pre-existing block (e.g. from a prior
  # standalone token-diet run) is detected and we skip rather than append a
  # duplicate top-level key.
  cfg_add disabledProviders <<'EOF'
disabledProviders:
  - claude-plugins
  - codex
  - gemini
  - cursor
  - windsurf
  - opencode
  - cline
EOF
  ok "Config merged"
}

# Merge the team MCP servers into ~/.omp/agent/mcp.json (existing servers kept).
# Atlassian is intentionally NOT here — acli is our go-to for Jira/Confluence.
write_mcp() {
  [ "$NO_CONFIG" = 1 ] && return 0
  have node || have bun || { warn "no node/bun — skipping mcp.json (re-run after runtimes)"; return 0; }
  local mcp="$HOME/.omp/agent/mcp.json" patch gh ghblock=""
  gh="${GITHUB_TOKEN:-${GH_TOKEN:-${GITHUB_PERSONAL_ACCESS_TOKEN:-}}}"
  [ -z "$gh" ] && gh="$(prompt 'GitHub PAT for the GitHub MCP (optional, blank to skip)' hidden)"
  # Only GitHub is configured as an MCP, and only when a token is available.
  # Atlassian -> acli, Context7 -> ctx7 CLI, both as CLI+skill (not MCP). No Miro.
  if [ -n "$gh" ]; then
    ghblock="$(printf '"github": { "type": "http", "url": "https://api.githubcopilot.com/mcp/", "headers": { "Authorization": "Bearer %s" }, "enabled": true }' "$gh")"
  else
    ghblock='"github": { "type": "http", "url": "https://api.githubcopilot.com/mcp/", "enabled": false }'
  fi
  patch="$(mktemp)"
  cat > "$patch" <<EOF
{
  "mcpServers": {
    $ghblock
  }
}
EOF
  mkdir -p "$(dirname "$mcp")"
  run "js_run \"$ROOT/scripts/merge-json.mjs\" \"$mcp\" \"$patch\" >/dev/null || true"
  [ -n "$gh" ] && chmod 600 "$mcp" 2>/dev/null || true
  rm -f "$patch"
  ok "mcp.json merged ($([ -n "$gh" ] && echo 'github enabled' || echo 'github present (add a PAT to enable)'))"
}

# --- 3) Per-plugin prompts --------------------------------------------------
bold "Plugins"
SEL_DEVTEAM=0; SEL_COPILOT=0; SEL_TOKENDIET=0; SEL_OAI_COMPAT=0

if ask "Install dev-team (agentic dev team: /specs -> /plan -> /build -> /pr)?"; then
  plug dev-team "$ROOT/plugins/dev-team"; SEL_DEVTEAM=1
fi

if ask "Install copilot-preset (route models through GitHub Copilot)?"; then
  plug copilot-preset "$ROOT/plugins/copilot-preset"; SEL_COPILOT=1
fi

if ask "Install token-diet (ctx-wire + codebase-memory-mcp + caveman + yagni + acli + LSP)?"; then
  plug token-diet "$ROOT/plugins/token-diet"; SEL_TOKENDIET=1
fi

if ask "Install openai-compatible (register a LiteLLM/Ollama/vLLM endpoint as a model provider)?" "N"; then
  plug openai-compatible "$ROOT/plugins/openai-compatible"; SEL_OAI_COMPAT=1
fi

if ask "Install datadog (Pup CLI + Datadog observability skills)?" "N"; then
  plug datadog "$ROOT/plugins/datadog"
fi

if ask "Install azure-devops-fs (Azure DevOps as a filesystem)?" "N"; then
  plug azure-devops-fs "$ROOT/plugins/azure-devops-fs"
fi

# Merge the OMP config + team MCP servers so the selection works out of the box.
write_config
write_mcp

# --- 4) Doctor -------------------------------------------------------------
bold "Doctor"
for d in "$HOME/.local/bin" "$HOME/.bun/bin"; do ensure_path "$d"; done
hash -r 2>/dev/null || true
fail=0
check() {  # check <tool> <required|optional|recommended> <version-cmd>
  local t="$1" req="$2" vc="${3:-}"
  if have "$t"; then
    local v=""; [ -n "$vc" ] && v="$(eval "$vc" 2>/dev/null | head -1)"
    ok "$t ${v:+($v)} -> $(command -v "$t")"
  elif [ "$req" = required ]; then warn "$t MISSING (required)"; fail=1
  else warn "$t not found (optional)"; fi
}
check git      required    "git --version"
check bun      required    "bun --version"
check node     recommended "node --version"
check omp      required    "omp --version"
check codebase-memory-mcp optional "codebase-memory-mcp --version"

bold "OMP launch check"
if have omp && omp --version >/dev/null 2>&1; then
  ok "omp launches: $(omp --version 2>/dev/null | head -1)"
  echo "  plugins installed:"; omp plugin list 2>/dev/null | grep -E "@${MARKET}" | sed 's/^/    /' || true
else
  warn "omp did not launch — ensure \$HOME/.bun/bin is on PATH"; fail=1
fi

# OMP's own bash tool caches a shell session's PATH for the life of the OMP
# process: if this install ran while OMP was already open, or ~/.local/bin /
# ~/.bun/bin only just landed on PATH, that session stays stale until OMP
# restarts. Detect it from a FRESH login shell (bash -l) rather than trusting
# this script's own already-exported PATH.
STALE_TOOLS=""
for t in omp bun; do
  have "$t" && ! bash -lc "command -v $t" >/dev/null 2>&1 && STALE_TOOLS="$STALE_TOOLS $t"
done
if [ -n "$STALE_TOOLS" ]; then
  warn "installed but NOT visible in a fresh shell yet:$STALE_TOOLS. An already-running OMP process keeps missing them until you RESTART OMP — re-running this script again will not fix it."
fi

echo
[ "$fail" = 0 ] && bold "All set ✓" || bold "Finished with warnings — see above"
echo "Open a NEW shell (or 'source ~/.profile') so PATH changes persist. If OMP is already running, RESTART it — a new shell alone won't refresh an already-running process's PATH."
[ "$fail" = 0 ] || exit 1
