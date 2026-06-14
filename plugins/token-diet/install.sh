#!/usr/bin/env bash
# token-diet installer (Linux/macOS) — installs the LATEST RTK + CodeGraph and
# indexes EVERY git repo under a sources root. caveman ships as an OMP skill.
# Flags:
#   --sources-root=PATH  parent dir of your repos; every git repo under it is
#                        indexed (default: cwd; asked if interactive). --project= is an alias.
#   --depth=N            how deep to look for repos under the root (default 3)
#   --update             refresh rtk/codegraph if already installed
#   --dry-run            print only
#   -y, --yes            non-interactive (don't prompt for the sources root)
set -euo pipefail

DRY=0; UPDATE=0; YES=0; SROOT=""; DEPTH=3; INSECURE_TLS=0
for a in "$@"; do case "$a" in
  --dry-run) DRY=1 ;; --update) UPDATE=1 ;; -y|--yes) YES=1 ;; --insecure-tls) INSECURE_TLS=1 ;;
  --sources-root=*|--project=*) SROOT="${a#*=}" ;;
  --depth=*) DEPTH="${a#*=}" ;;
  -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
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

# --- RTK (Rust Token Killer) -------------------------------------------------
if have rtk && [ "$UPDATE" = 0 ]; then
  say "RTK present ($(rtk --version 2>/dev/null || echo '?')) — use --update to refresh"
else
  say "Installing latest RTK (Rust Token Killer)"
  # curl installer is the official cross-platform path (linux + macOS); brew/cargo
  # are fallbacks (brew has no guaranteed formula on all taps).
  if have curl;  then run "curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh"
  elif have brew; then run "brew install rtk"
  elif have cargo; then run "cargo install --git https://github.com/rtk-ai/rtk"
  else warn "need curl, brew, or cargo to install rtk — skipping"; fi
fi

# --- CodeGraph (MCP) ---------------------------------------------------------
if have codegraph && [ "$UPDATE" = 0 ]; then
  say "CodeGraph present — use --update to refresh"
else
  say "Installing latest CodeGraph"
  if have curl;  then run "curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh"
  elif have npm; then run "npm i -g @colbymchenry/codegraph@latest"
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

cat <<'EOF'

==> token-diet tools ready. Final manual step: enable the CodeGraph MCP server.
    In your merged ~/.omp/agent .mcp.json set:  "codegraph": { ..., "enabled": true }
    (ships disabled so it never starts before the project is indexed).

    - Shell output auto-routes through `rtk` (always-on rule) when present.
    - `skill://codegraph` for symbol/caller/architecture queries.
    - `/caveman` for terse output to save output tokens.
EOF
