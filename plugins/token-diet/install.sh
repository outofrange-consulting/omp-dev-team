#!/usr/bin/env bash
# token-diet installer (Linux/macOS) — installs the LATEST ctx-wire + CodeGraph and
# indexes every git repo under a sources root. caveman/yagni ship as OMP skills.
# Also sets up the acli (Atlassian CLI), ast-grep, the .NET SDK + csharp-ls LSP,
# and the ctx7 docs CLI. Everything is refreshed to latest by default.
# Flags:
#   --sources-root=PATH  parent dir of your repos; every git repo under it is
#                        indexed (default: cwd; asked if interactive). --project= is an alias.
#   --depth=N            how deep to look for repos under the root (default 3)
#   --no-update          keep tools already installed (don't refresh them)
#   --no-config          don't enable the bundled skills in ~/.omp/agent/config.yml
#   --no-context-mode    don't install the context-mode OMP plugin
#   --no-acli            don't install / authenticate the Atlassian CLI (acli)
#   -y, --yes            non-interactive (don't prompt for the sources root / auth)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YES=0; SROOT=""; DEPTH=3; INSECURE_TLS=0; NO_CONFIG=0; NO_CTXMODE=0; NO_ACLI=0; NO_UPDATE=0
for a in "$@"; do case "$a" in
  --no-update) NO_UPDATE=1 ;; -y|--yes) YES=1 ;; --insecure-tls) INSECURE_TLS=1 ;; --ca-file=*) CA_FILE="${a#*=}" ;;
  --sources-root=*|--project=*) SROOT="${a#*=}" ;;
  --depth=*) DEPTH="${a#*=}" ;;
  --no-config) NO_CONFIG=1 ;;
  --no-context-mode) NO_CTXMODE=1 ;;
  --no-acli) NO_ACLI=1 ;;
  -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { eval "$@"; }
PROFILES=("$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc")
ensure_path() {  # add $1 to PATH in this session + persist to shell profiles (idempotent)
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
# Corporate TLS-intercepting proxy (Zscaler / Trend Micro under WSL): opt-in bypass.
enable_insecure_tls() {
  warn "Insecure TLS: certificate verification DISABLED for this run (corporate MITM proxy)."
  export GIT_SSL_NO_VERIFY=true NODE_TLS_REJECT_UNAUTHORIZED=0 NPM_CONFIG_STRICT_SSL=false \
         RUSTUP_USE_CURL=1 CARGO_HTTP_CHECK_REVOKE=false OMP_INSECURE_TLS=1
  local d; d="$(mktemp -d 2>/dev/null || echo "/tmp/omp-tls.$$")"; mkdir -p "$d"
  printf 'insecure\n' > "$d/.curlrc"; printf 'check_certificate = off\n' > "$d/.wgetrc"
  export CURL_HOME="$d" WGETRC="$d/.wgetrc"
}
{ [ "${INSECURE_TLS:-0}" = 1 ] || [ -n "${OMP_INSECURE_TLS:-}" ]; } && enable_insecure_tls
CA_FILE="${CA_FILE:-${OMP_CA_FILE:-}}"
if [ -n "$CA_FILE" ] && [ -f "$CA_FILE" ]; then
  export OMP_CA_FILE="$CA_FILE" NODE_EXTRA_CA_CERTS="$CA_FILE" SSL_CERT_FILE="$CA_FILE" CURL_CA_BUNDLE="$CA_FILE" GIT_SSL_CAINFO="$CA_FILE" REQUESTS_CA_BUNDLE="$CA_FILE"
fi

case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

# --- ctx-wire (transparent command-output compression + secret scrubbing) ----
if have ctx-wire && [ "$NO_UPDATE" = 1 ]; then
  say "ctx-wire present"
elif have ctx-wire; then
  say "Updating ctx-wire"; run "ctx-wire update || true"
else
  say "Installing latest ctx-wire"
  if have curl; then run "curl -fsSL https://ctx-wire.dev/install.sh | sh || true"
  else warn "need curl to install ctx-wire — see https://ctx-wire.dev"; fi
fi
# Wire it into the command path TRANSPARENTLY via PATH shims in ~/.local/bin.
if have ctx-wire; then run "ctx-wire shims install || true"; fi

# --- Multilingual ctx-wire filters (EN+FR) -----------------------------------
PACK_DIR="$HERE/ctx-wire/filters.d"
CTXW_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ctx-wire"
CTXW_FILTERS="$CTXW_DIR/filters.toml"
BLOCK_BEGIN="# >>> token-diet multilingual filters (managed) >>>"
BLOCK_END="# <<< token-diet multilingual filters (managed) <<<"
if [ -d "$PACK_DIR" ]; then
  say "Installing multilingual ctx-wire filters (EN+FR: git-status + dotnet build/test/restore/run/tool)"
  mkdir -p "$CTXW_DIR"
  blk="$(mktemp)"; tmp="$(mktemp)"
  printf '%s\n' "$BLOCK_BEGIN" > "$blk"
  for f in "$PACK_DIR"/*.toml; do awk '/^schema_version[[:space:]]*=/{next} {print}' "$f" >> "$blk"; printf '\n' >> "$blk"; done
  printf '%s\n' "$BLOCK_END" >> "$blk"
  if [ -f "$CTXW_FILTERS" ]; then
    awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" 'index($0,b){skip=1;next} index($0,e){skip=0;next} !skip{print}' "$CTXW_FILTERS" > "$tmp"
  fi
  if ! grep -q '^schema_version' "$tmp" 2>/dev/null; then printf 'schema_version = 1\n' | cat - "$tmp" > "$tmp.h" && mv "$tmp.h" "$tmp"; fi
  printf '\n' >> "$tmp"; cat "$blk" >> "$tmp"
  mv "$tmp" "$CTXW_FILTERS"; rm -f "$blk"
  if have ctx-wire; then run "ctx-wire verify || true"
  elif have python3; then run "python3 '$HERE/ctx-wire/scripts/verify-filters.py' '$PACK_DIR' || true"; fi
fi

# --- context-mode (locale-agnostic output sandbox; complements ctx-wire) ------
if [ "$NO_CTXMODE" = 0 ]; then
  if have omp; then
    say "Installing context-mode OMP plugin (locale-agnostic output sandbox + session continuity)"
    if ! run "omp plugin install context-mode"; then
      warn "omp plugin install failed (not in registry yet?) — falling back to ~/.omp/plugins"
      OMP_PLUGINS="${OMP_HOME:-$HOME/.omp}/plugins"
      mkdir -p "$OMP_PLUGINS"
      [ -f "$OMP_PLUGINS/package.json" ] || printf '{\n  "dependencies": {}\n}\n' > "$OMP_PLUGINS/package.json"
      if have bun;   then run "(cd '$OMP_PLUGINS' && bun add context-mode) || true"
      elif have npm; then run "(cd '$OMP_PLUGINS' && npm install context-mode) || true"
      else warn "need bun or npm to install context-mode — see https://github.com/mksglu/context-mode"; fi
    fi
  else
    warn "omp CLI not found — skip context-mode (run later: omp plugin install context-mode)"
  fi
fi

# --- acli (official Atlassian CLI: Jira / Confluence / Bitbucket) -------------
# acli is our GO-TO for Atlassian — not an MCP. The URL serves the LATEST build,
# so re-running updates it. Installs to ~/.local/bin (no sudo). When interactive
# (and not already authenticated) it offers to run `acli jira auth login`.
if [ "$NO_ACLI" = 0 ]; then
  if have acli && [ "$NO_UPDATE" = 1 ]; then
    say "acli present"
  else
    say "Installing Atlassian CLI (acli)"
    if have curl; then
      ACLI_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"   # linux | darwin
      case "$(uname -m)" in x86_64|amd64) ACLI_ARCH=amd64 ;; arm64|aarch64) ACLI_ARCH=arm64 ;; *) ACLI_ARCH=amd64 ;; esac
      ACLI_URL="https://acli.atlassian.com/${ACLI_OS}/latest/acli_${ACLI_OS}_${ACLI_ARCH}/acli"
      run "mkdir -p \"$HOME/.local/bin\" && curl -fsSL -o \"$HOME/.local/bin/acli\" \"$ACLI_URL\" && chmod +x \"$HOME/.local/bin/acli\" || true"
    else warn "need curl to install acli — see https://developer.atlassian.com/cloud/acli/"; fi
  fi
  # Authenticate (Jira) when interactive and not already logged in.
  if have acli && [ "$YES" = 0 ] && [ -r /dev/tty ] && ! acli jira auth status >/dev/null 2>&1; then
    printf '    Authenticate acli now (Jira/Confluence)? [Y/n] '; read -r ans </dev/tty || ans=""
    case "${ans:-Y}" in [Yy]*)
      printf '    Atlassian site (e.g. mysite.atlassian.net): '; read -r ACLI_SITE </dev/tty || ACLI_SITE=""
      printf '    Email: '; read -r ACLI_EMAIL </dev/tty || ACLI_EMAIL=""
      printf '    API token (hidden; id.atlassian.com -> Security -> API tokens): '; read -r -s ACLI_TOKEN </dev/tty || ACLI_TOKEN=""; echo
      if [ -n "$ACLI_SITE" ] && [ -n "$ACLI_EMAIL" ] && [ -n "$ACLI_TOKEN" ]; then
        printf '%s' "$ACLI_TOKEN" | acli jira auth login --site "$ACLI_SITE" --email "$ACLI_EMAIL" --token >/dev/null 2>&1 \
          && echo "  acli authenticated ($ACLI_SITE)" || warn "acli auth failed — run 'acli jira auth login' manually."
      else warn "incomplete input — run 'acli jira auth login' manually."; fi
      ;;
    esac
  fi
fi

# --- CodeGraph (MCP) ---------------------------------------------------------
if have codegraph && [ "$NO_UPDATE" = 1 ]; then
  say "CodeGraph present"
else
  say "Installing latest CodeGraph"
  if have curl;  then run "curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh || true"
  elif have npm; then run "npm i -g @colbymchenry/codegraph@latest || true"
  else warn "need curl or npm to install codegraph — skipping"; fi
fi
ensure_path "$HOME/.local/bin"; hash -r 2>/dev/null || true

# --- Scan/index source repos with CodeGraph ---------------------------------
if [ -z "$SROOT" ]; then
  if [ "$YES" = 0 ] && [ -r /dev/tty ]; then
    printf 'Sources ROOT to scan (every git repo under it is indexed)? [default: %s] ' "$PWD"
    read -r SROOT </dev/tty || SROOT=""
  fi
  SROOT="${SROOT:-$PWD}"
fi
index_one() { say "  CodeGraph: $1"; run "codegraph init \"$1\""  || true; run "codegraph index \"$1\"" || true; }
if have codegraph; then
  if [ -d "$SROOT/.git" ]; then say "Scanning single repo: $SROOT"; index_one "$SROOT"
  else
    say "Scanning every git repo under: $SROOT (depth $DEPTH)"
    found=0
    while IFS= read -r gitdir; do [ -n "$gitdir" ] || continue; found=$((found + 1)); index_one "$(dirname "$gitdir")"; done <<EOF
$(find "$SROOT" -maxdepth "$DEPTH" -type d -name .git 2>/dev/null)
EOF
    if [ "$found" = 0 ]; then warn "no git repos under $SROOT — indexing it as a single project"; index_one "$SROOT"
    else say "Indexed $found repo(s) under $SROOT."; fi
  fi
fi

# --- ast-grep (structural search/rewrite) -----------------------------------
if have ast-grep && [ "$NO_UPDATE" = 1 ]; then
  say "ast-grep present"
elif have brew; then
  say "Installing ast-grep (brew)"; run "brew install ast-grep || brew upgrade ast-grep || true"
elif have npm; then
  say "Installing ast-grep (npm @ast-grep/cli)"; run "npm install -g @ast-grep/cli || true"
else
  warn "need npm or brew to install ast-grep — see https://ast-grep.github.io"
fi

# --- .NET SDK (official MS script) + csharp-ls (C# LSP) ----------------------
# Install the .NET SDK with Microsoft's official no-sudo script so the C# LSP
# works out of the box, then install csharp-ls as a global tool.
if ! have dotnet; then
  if have brew; then say "Installing .NET SDK (brew)"; run "brew install --cask dotnet-sdk || brew install dotnet || true"
  elif have curl; then
    say "Installing .NET SDK (LTS) via the official Microsoft script"
    run "curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && bash /tmp/dotnet-install.sh --channel LTS --install-dir \"$HOME/.dotnet\" || true"
    rm -f /tmp/dotnet-install.sh 2>/dev/null || true
  else warn "need curl or brew to install the .NET SDK — see https://dot.net"; fi
  export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"
  for p in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -e "$p" ] || continue
    grep -qsF 'DOTNET_ROOT' "$p" || printf '\n# omp-dev-team .NET\nexport DOTNET_ROOT="$HOME/.dotnet"\nexport PATH="$HOME/.dotnet:$HOME/.dotnet/tools:$PATH"\n' >> "$p"
  done
  hash -r 2>/dev/null || true
fi
if have dotnet; then
  if have csharp-ls && [ "$NO_UPDATE" = 1 ]; then say "csharp-ls present"
  elif have csharp-ls; then say "Updating csharp-ls"; run "dotnet tool update -g csharp-ls || true"
  else say "Installing csharp-ls (.NET C# language server)"; run "dotnet tool install -g csharp-ls || true"; fi
  ensure_path "$HOME/.dotnet/tools"; hash -r 2>/dev/null || true
else
  warn "dotnet not found — skipping csharp-ls (C# LSP)"
fi

# --- ctx7 CLI (context7 library documentation) ------------------------------
if have npm; then
  if have ctx7 && [ "$NO_UPDATE" = 1 ]; then say "ctx7 CLI present"
  else say "Installing ctx7 CLI (context7 library documentation)"; run "npm install -g ctx7 || true"; fi
else
  warn "npm not found — ctx7 unavailable (install Node.js to enable library docs)"
fi

# --- OMP config: skills, provider isolation, csharp-ls LSP ------------------
CFG="$HOME/.omp/agent/config.yml"
if [ "$NO_CONFIG" = 0 ]; then
  mkdir -p "$(dirname "$CFG")"; touch "$CFG"
  if grep -q "token-diet config" "$CFG" 2>/dev/null; then say "token-diet config already in $CFG"
  else { echo ""; cat "$HERE/config.snippet.yml"; } >> "$CFG"; say "Applied token-diet config to $CFG"; fi
  if ! grep -q "disabledProviders" "$CFG" 2>/dev/null; then
    # Keep this list identical to install.sh's write_config (github intentionally
    # omitted) so the global and standalone install paths never disagree.
    printf '\ndisabledProviders:\n  - claude-plugins\n  - codex\n  - gemini\n  - cursor\n  - windsurf\n  - opencode\n  - cline\n' >> "$CFG"
  fi
fi

# --- csharp-ls LSP config ---------------------------------------------------
LSP="$HOME/.omp/agent/lsp.json"
if have csharp-ls && [ "$NO_CONFIG" = 0 ] && [ ! -f "$LSP" ]; then
  say "Writing csharp-ls LSP config to $LSP"
  mkdir -p "$(dirname "$LSP")"
  printf '{\n  "servers": {\n    "csharp-ls": {\n      "command": "csharp-ls",\n      "fileTypes": [".cs", ".csx"],\n      "rootMarkers": ["*.sln", "*.slnx", "*.csproj", ".git"]\n    }\n  }\n}\n' > "$LSP"
fi

# --- Load the context-transform extensions ----------------------------------
if [ -d "$HERE/extensions" ]; then
  DEST="$HOME/.omp/agent/extensions/token-diet"
  rm -rf "$DEST"; mkdir -p "$DEST"; cp -R "$HERE/extensions" "$DEST/"
  [ -f "$HERE/package.json" ] && cp "$HERE/package.json" "$DEST/"
  say "read-dedup + context-dedup + context-compress (safe) loaded"
fi

say "token-diet active: ctx-wire shims, EN+FR filters, context-mode, CodeGraph (MCP), ast-grep, .NET/csharp-ls LSP, ctx7, acli, provider isolation, /caveman + /yagni. Restart omp."
