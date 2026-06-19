#!/usr/bin/env bash
# token-diet installer (Linux/macOS) — installs the LATEST ctx-wire + CodeGraph and
# indexes EVERY git repo under a sources root. caveman/yagni ship as OMP skills.
# Flags:
#   --sources-root=PATH  parent dir of your repos; every git repo under it is
#                        indexed (default: cwd; asked if interactive). --project= is an alias.
#   --depth=N            how deep to look for repos under the root (default 3)
#   --update             refresh ctx-wire/codegraph if already installed
#   --no-config          don't enable the bundled skills in ~/.omp/agent/config.yml
#   --no-context-mode    don't install the context-mode OMP plugin
#   --no-acli            don't install the Atlassian CLI (acli)
#   --dry-run            print only
#   -y, --yes            non-interactive (don't prompt for the sources root)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0; UPDATE=0; YES=0; SROOT=""; DEPTH=3; INSECURE_TLS=0; NO_CONFIG=0; NO_CTXMODE=0; NO_ACLI=0
for a in "$@"; do case "$a" in
  --dry-run) DRY=1 ;; --update) UPDATE=1 ;; -y|--yes) YES=1 ;; --insecure-tls) INSECURE_TLS=1 ;; --ca-file=*) CA_FILE="${a#*=}" ;;
  --sources-root=*|--project=*) SROOT="${a#*=}" ;;
  --depth=*) DEPTH="${a#*=}" ;;
  --no-config) NO_CONFIG=1 ;;
  --no-context-mode) NO_CTXMODE=1 ;;
  --no-acli) NO_ACLI=1 ;;
  -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
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
# Corporate root CA (optional): trust a custom CA this run (node/bun/git/curl/Go).
CA_FILE="${CA_FILE:-${OMP_CA_FILE:-}}"
if [ -n "$CA_FILE" ] && [ -f "$CA_FILE" ]; then
  export OMP_CA_FILE="$CA_FILE" NODE_EXTRA_CA_CERTS="$CA_FILE" SSL_CERT_FILE="$CA_FILE" CURL_CA_BUNDLE="$CA_FILE" GIT_SSL_CAINFO="$CA_FILE" REQUESTS_CA_BUNDLE="$CA_FILE"
  warn "Trusting corporate CA: $CA_FILE"
fi

# --- ctx-wire (transparent command-output compression + secret scrubbing) ----
if have ctx-wire && [ "$UPDATE" = 1 ]; then
  say "Updating ctx-wire"; run "ctx-wire update || true"
elif have ctx-wire; then
  say "ctx-wire present — use --update to refresh"
else
  say "Installing latest ctx-wire"
  # Non-fatal: a network/release failure here must not abort the rest of the
  # installer (local filter wiring + config still apply). `set -e` otherwise
  # exits on the piped installer's non-zero status.
  if have curl; then run "curl -fsSL https://ctx-wire.dev/install.sh | sh || true"
  else warn "need curl to install ctx-wire — see https://ctx-wire.dev"; fi
fi
# Wire it into the command path TRANSPARENTLY via PATH shims in ~/.local/bin (which
# is first on PATH, so OMP's bash tool inherits them — commands run normally, no
# prefix, output filtered). `init claude` only wires Claude Code, not OMP.
if have ctx-wire || [ "$DRY" = 1 ]; then
  say "Installing ctx-wire PATH shims (transparent; no command prefix)"
  run "ctx-wire shims install || true"
fi

# --- Multilingual ctx-wire filters (EN+FR) -----------------------------------
# ctx-wire's bundled filters key on English output; merge our EN+FR overrides
# (git-status, dotnet-build, dotnet-test) into the user filters file so the same
# compaction fires under fr_* locales. See plugins/token-diet/ctx-wire/README.md
# for why only git+dotnet (other tools emit English in any locale) and why no
# Romanian (git/.NET ship no ro translation — context-mode covers ro *data*).
PACK_DIR="$HERE/ctx-wire/filters.d"
CTXW_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ctx-wire"
CTXW_FILTERS="$CTXW_DIR/filters.toml"
BLOCK_BEGIN="# >>> token-diet multilingual filters (managed) >>>"
BLOCK_END="# <<< token-diet multilingual filters (managed) <<<"
if [ -d "$PACK_DIR" ]; then
  say "Installing multilingual ctx-wire filters (EN+FR: git-status + dotnet build/test[VSTest+MTP]/restore/run/tool)"
  if [ "$DRY" = 0 ]; then
    mkdir -p "$CTXW_DIR"
    blk="$(mktemp)"; tmp="$(mktemp)"
    printf '%s\n' "$BLOCK_BEGIN" > "$blk"
    # Concatenate pack tables, stripping per-file schema_version (declared once
    # at the top of the target instead — TOML allows top-level keys only before
    # the first table header).
    for f in "$PACK_DIR"/*.toml; do
      awk '/^schema_version[[:space:]]*=/{next} {print}' "$f" >> "$blk"
      printf '\n' >> "$blk"
    done
    printf '%s\n' "$BLOCK_END" >> "$blk"
    # Drop any prior managed block, keep the rest of the user's file verbatim.
    if [ -f "$CTXW_FILTERS" ]; then
      awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" \
        'index($0,b){skip=1;next} index($0,e){skip=0;next} !skip{print}' \
        "$CTXW_FILTERS" > "$tmp"
    fi
    # Guarantee a single schema_version header at the very top.
    if ! grep -q '^schema_version' "$tmp" 2>/dev/null; then
      printf 'schema_version = 1\n' | cat - "$tmp" > "$tmp.h" && mv "$tmp.h" "$tmp"
    fi
    printf '\n' >> "$tmp"; cat "$blk" >> "$tmp"
    mv "$tmp" "$CTXW_FILTERS"; rm -f "$blk"
  fi
  # Verify: ctx-wire's own runner if present, else the bundled offline checker.
  if have ctx-wire; then run "ctx-wire verify || true"
  elif have python3; then run "python3 '$HERE/ctx-wire/scripts/verify-filters.py' '$PACK_DIR' || true"
  fi
fi

# --- context-mode (locale-agnostic output sandbox; complements ctx-wire) ------
# Native OMP plugin (tool_call/tool_result/session_start/session_before_compact):
# sandboxes tool output and indexes it (FTS5/BM25, language-independent), so
# non-English output — including Romanian, which git/.NET never localize — is
# reduced without per-language regex, and survives compaction. Layers on top of
# ctx-wire's deterministic build/test/git collapses, not in place of them.
if [ "$NO_CTXMODE" = 0 ]; then
  if have omp; then
    say "Installing context-mode OMP plugin (locale-agnostic output sandbox + session continuity)"
    # Default registry first; context-mode is "recommended once published", so
    # fall back to a direct dependency install under ~/.omp/plugins (OMP loads
    # any dependency there whose package.json carries an `omp`/`pi` field). No
    # separate `omp marketplace add` step is required.
    if ! run "omp plugin install context-mode"; then
      warn "omp plugin install failed (not in registry yet?) — falling back to ~/.omp/plugins"
      OMP_PLUGINS="${OMP_HOME:-$HOME/.omp}/plugins"
      if [ "$DRY" = 0 ]; then
        mkdir -p "$OMP_PLUGINS"
        [ -f "$OMP_PLUGINS/package.json" ] || printf '{\n  "dependencies": {}\n}\n' > "$OMP_PLUGINS/package.json"
      fi
      if have bun;   then run "(cd '$OMP_PLUGINS' && bun add context-mode) || true"
      elif have npm; then run "(cd '$OMP_PLUGINS' && npm install context-mode) || true"
      else warn "need bun or npm to install context-mode manually — see https://github.com/mksglu/context-mode"; fi
    fi
  else
    warn "omp CLI not found — skip context-mode (run later: omp plugin install context-mode)"
  fi
fi

# --- acli (official Atlassian CLI: Jira / Confluence / Bitbucket) -------------
# Complements the Atlassian MCP (use MCP for structured reads; acli for bulk/
# scripted writes and what MCP doesn't expose). Output is English tables/JSON ->
# the bundled ctx-wire `acli.toml` is a structural filter (no localization) that
# also redacts bare ATATT tokens. The URL serves the LATEST build, so re-running
# updates it (acli versions are supported only ~6 months). Installs to
# ~/.local/bin (no sudo; already first on PATH via the ctx-wire shims).
if [ "$NO_ACLI" = 0 ]; then
  if have acli && [ "$UPDATE" = 0 ]; then
    say "acli present — use --update to refresh"
  else
    say "Installing Atlassian CLI (acli)"
    if have curl; then
      ACLI_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"   # linux | darwin
      case "$(uname -m)" in x86_64|amd64) ACLI_ARCH=amd64 ;; arm64|aarch64) ACLI_ARCH=arm64 ;; *) ACLI_ARCH=amd64 ;; esac
      ACLI_URL="https://acli.atlassian.com/${ACLI_OS}/latest/acli_${ACLI_OS}_${ACLI_ARCH}/acli"
      run "mkdir -p \"$HOME/.local/bin\" && curl -fsSL -o \"$HOME/.local/bin/acli\" \"$ACLI_URL\" && chmod +x \"$HOME/.local/bin/acli\" || true"
    else warn "need curl to install acli — see https://developer.atlassian.com/cloud/acli/"; fi
  fi
fi

# --- CodeGraph (MCP) ---------------------------------------------------------
if have codegraph && [ "$UPDATE" = 0 ]; then
  say "CodeGraph present — use --update to refresh"
else
  say "Installing latest CodeGraph"
  # Non-fatal (see ctx-wire note): keep the installer going if the network fails.
  if have curl;  then run "curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh || true"
  elif have npm; then run "npm i -g @colbymchenry/codegraph@latest || true"
  else warn "need curl or npm to install codegraph — skipping"; fi
fi

# --- Scan/index source repos with CodeGraph ---------------------------------
# Point CodeGraph at the ROOT of your sources (a dir containing many repos);
# every git repo under it gets indexed so any repo is ready when you open it.
# Asked when interactive so the global installer doesn't index the marketplace clone.
if [ -z "$SROOT" ]; then
  if [ "$YES" = 0 ] && [ "$DRY" = 0 ] && [ -r /dev/tty ]; then
    printf 'Sources ROOT to scan (every git repo under it is indexed)? [default: %s] ' "$PWD"
    read -r SROOT </dev/tty || SROOT=""
  fi
  SROOT="${SROOT:-$PWD}"
fi

index_one() {  # index_one <repo-dir>
  say "  CodeGraph: $1"
  run "codegraph init \"$1\""  || true
  run "codegraph index \"$1\"" || true
}

if have codegraph || [ "$DRY" = 1 ]; then
  if [ -d "$SROOT/.git" ]; then
    say "Scanning single repo: $SROOT"; index_one "$SROOT"
  else
    say "Scanning every git repo under: $SROOT (depth $DEPTH)"
    found=0
    while IFS= read -r gitdir; do
      [ -n "$gitdir" ] || continue
      found=$((found + 1)); index_one "$(dirname "$gitdir")"
    done <<EOF
$(find "$SROOT" -maxdepth "$DEPTH" -type d -name .git 2>/dev/null)
EOF
    if [ "$found" = 0 ]; then warn "no git repos under $SROOT — indexing it as a single project"; index_one "$SROOT"
    else say "Indexed $found repo(s) under $SROOT."; fi
  fi
fi

# --- csharp-ls (.NET C# language server) ------------------------------------
if have dotnet; then
  if have csharp-ls; then
    say "csharp-ls present$([ "$UPDATE" = 1 ] && echo " — updating" || echo "")"
    [ "$UPDATE" = 1 ] && run "dotnet tool update -g csharp-ls || true"
  else
    say "Installing csharp-ls (.NET C# language server)"
    run "dotnet tool install -g csharp-ls || true"
  fi
else
  warn "dotnet not found — skipping csharp-ls (install .NET SDK to enable C# LSP)"
fi

# --- ctx7 CLI (context7 library documentation) ------------------------------
# CLI mode — no MCP server; the bundled context7 skill guides the agent to run
# `ctx7 library` / `ctx7 docs` via bash. More token-efficient than MCP.
if have npm; then
  if have ctx7 && [ "$UPDATE" = 0 ]; then
    say "ctx7 CLI already installed"
  else
    say "Installing ctx7 CLI (context7 library documentation)"
    run "npm install -g ctx7 || true"
  fi
else
  warn "npm not found — ctx7 unavailable (install Node.js to enable library docs)"
fi

# --- OMP config: skills, provider isolation, csharp-ls LSP ------------------
# config.snippet.yml appended once (idempotent). Separate block below handles
# re-runs for users who already have an older snippet without the new settings.
CFG="$HOME/.omp/agent/config.yml"
if [ "$NO_CONFIG" = 0 ]; then
  if [ "$DRY" = 1 ]; then echo "  [dry-run] apply token-diet config to $CFG"
  else
    mkdir -p "$(dirname "$CFG")"; touch "$CFG"
    if grep -q "token-diet config" "$CFG" 2>/dev/null; then say "token-diet config already in $CFG"
    else { echo ""; cat "$HERE/config.snippet.yml"; } >> "$CFG"; say "Applied token-diet config to $CFG"; fi
  fi
fi

# Idempotent: add disabledProviders for users with a pre-existing older snippet.
if [ "$NO_CONFIG" = 0 ]; then
  if grep -q "disabledProviders" "$CFG" 2>/dev/null; then
    say "Provider isolation already set in $CFG"
  else
    if [ "$DRY" = 1 ]; then echo "  [dry-run] add disabledProviders to $CFG"
    else
      printf '\ndisabledProviders:\n  - claude-plugins\n  - codex\n  - gemini\n  - cursor\n  - windsurf\n  - opencode\n  - github\n  - cline\n' >> "$CFG"
      say "Added provider isolation to $CFG"
    fi
  fi
fi

# --- csharp-ls LSP config ---------------------------------------------------
LSP="$HOME/.omp/agent/lsp.json"
if have csharp-ls && [ "$NO_CONFIG" = 0 ]; then
  if [ -f "$LSP" ]; then
    say "OMP LSP config already at $LSP — skipping"
  else
    say "Writing csharp-ls LSP config to $LSP"
    if [ "$DRY" = 0 ]; then
      mkdir -p "$(dirname "$LSP")"
      printf '{\n  "servers": {\n    "csharp-ls": {\n      "command": "csharp-ls",\n      "fileTypes": [".cs", ".csx"],\n      "rootMarkers": ["*.sln", "*.slnx", "*.csproj", ".git"]\n    }\n  }\n}\n' > "$LSP"
    fi
  fi
elif ! have csharp-ls; then
  warn "csharp-ls not found — skipping LSP config (dotnet tool install -g csharp-ls)"
fi

# --- Load the context-transform extensions ----------------------------------
# OMP does NOT load extension modules (package.json `omp.extensions`) from a
# marketplace cache install, so mirror them into OMP's native user-extension dir
# (same pattern as dev-team/local-llm). read-dedup + context-dedup are LOSSLESS
# and on by default; context-compress is LOSSY and OPT-IN
# (TOKEN_DIET_CONTEXT_COMPRESS=safe|lite|full). Disable a dedup with
# TOKEN_DIET_READ_DEDUP=0 / TOKEN_DIET_CONTEXT_DEDUP=0.
if [ -d "$HERE/extensions" ]; then
  DEST="$HOME/.omp/agent/extensions/token-diet"
  if [ "$DRY" = 1 ]; then echo "  [dry-run] mirror token-diet extensions -> $DEST (OMP native ext dir)"
  else
    rm -rf "$DEST"; mkdir -p "$DEST"; cp -R "$HERE/extensions" "$DEST/"
    [ -f "$HERE/package.json" ] && cp "$HERE/package.json" "$DEST/"
    say "read-dedup + context-dedup (+ opt-in context-compress) loaded into $DEST"
  fi
fi

cat <<'EOF'

==> token-diet is active:
    - ctx-wire transparently compresses command output (PATH shims). `ctx-wire gain`
      shows savings; `ctx-wire doctor` verifies. Re-run install after adding tools.
    - Multilingual filters (EN+FR) for git status + dotnet build/test (VSTest & MTP)/
      restore/run/tool are merged into ~/.config/ctx-wire/filters.toml so compaction
      fires in fr_* locales.
    - context-mode plugin: locale-agnostic output sandbox (handles ro/any-language
      output + survives compaction) — also compresses MCP tool output. Layers on top
      of ctx-wire; --no-context-mode to skip.
    - acli (Atlassian CLI) installed to ~/.local/bin — `acli jira auth login` to set up.
      Prefer the Atlassian MCP for reads; acli for bulk/scripted writes. --no-acli to skip.
    - CodeGraph MCP is enabled and repos above are indexed —
      `skill://codegraph` for symbol/caller/architecture queries.
    - context7 CLI enabled (`ctx7 library` / `ctx7 docs` via bash) — no MCP process.
      skill://context7 guides the agent to fetch current library docs automatically.
    - Provider isolation: ~/.claude, ~/.codex, ~/.gemini, ~/.cursor, ~/.codeium/windsurf,
      ~/.copilot, ~/.config/opencode and their plugin agents are excluded from OMP.
      OMP only loads its own plugins and project-level AGENTS.md/CLAUDE.md files.
    - C# LSP (csharp-ls): auto-configured for .sln/.csproj projects.
    - `/caveman` (terse output) and `/yagni` (write less code) are enabled.
    - Dedup extensions: re-reads of unchanged files and byte-identical repeated
      blocks are elided from context (LOSSLESS, on). Opt into prose compression
      of old context with TOKEN_DIET_CONTEXT_COMPRESS=safe|lite|full.
    Restart `omp` so skills + isolation + extensions take effect.
EOF
