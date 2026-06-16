#!/usr/bin/env bash
# azure-devops-fs installer (Linux/macOS) — ensures Node.js (for the
# `npx @azure-devops/mcp` server), pre-warms the LATEST MCP package, and (when
# interactive) prompts for the Azure DevOps org/project/PAT and persists them.
# Flags:
#   --configure   force the org/project/PAT prompt
#   --no-config   never prompt for credentials
#   --dry-run     print only
#   -y, --yes     non-interactive (skip the credential prompt)
set -euo pipefail

DRY=0; YES=0; CONFIG=auto; INSECURE_TLS=0
for a in "$@"; do case "$a" in
  --dry-run) DRY=1 ;; -y|--yes) YES=1 ;; --insecure-tls) INSECURE_TLS=1 ;; --ca-file=*) CA_FILE="${a#*=}" ;;
  --configure) CONFIG=force ;; --no-config) CONFIG=skip ;;
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
# Corporate root CA (optional): trust a custom CA this run (node/bun/git/curl/Go).
CA_FILE="${CA_FILE:-${OMP_CA_FILE:-}}"
if [ -n "$CA_FILE" ] && [ -f "$CA_FILE" ]; then
  export OMP_CA_FILE="$CA_FILE" NODE_EXTRA_CA_CERTS="$CA_FILE" SSL_CERT_FILE="$CA_FILE" CURL_CA_BUNDLE="$CA_FILE" GIT_SSL_CAINFO="$CA_FILE" REQUESTS_CA_BUNDLE="$CA_FILE"
  warn "Trusting corporate CA: $CA_FILE"
fi

# --- Node.js (provides npx) -------------------------------------------------
NEED_NODE=20
if have node && [ "$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)" -ge "$NEED_NODE" ]; then
  say "Node.js present ($(node --version))"
elif have brew; then
  say "Installing Node.js (brew)"; run "brew install node"
else
  # Official prebuilt LTS tarball -> ~/.local + symlinks in ~/.local/bin (no fnm/nvm).
  say "Installing Node.js (LTS, official tarball)"
  if have curl; then
    case "$(uname -s)" in Linux) NOS=linux ;; Darwin) NOS=darwin ;; *) NOS="" ;; esac
    case "$(uname -m)" in x86_64|amd64) NARCH=x64 ;; aarch64|arm64) NARCH=arm64 ;; armv7l) NARCH=armv7l ;; *) NARCH="" ;; esac
    NVER=""; [ -n "$NOS" ] && [ -n "$NARCH" ] && NVER="$(curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null | tr '}' '\n' | grep -m1 '"lts":"' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    NFILE=""; [ -n "$NVER" ] && NFILE="node-${NVER}-${NOS}-${NARCH}.tar.gz"
    if [ -z "$NFILE" ]; then warn "could not resolve a Node LTS tarball for ${NOS:-?}-${NARCH:-?} — see https://nodejs.org"
    elif [ "$DRY" = 1 ]; then echo "  [dry-run] curl nodejs.org/dist/${NVER}/$NFILE | tar -xz -> ~/.local; symlink node/npm/npx into ~/.local/bin"
    else
      NTMP="$(mktemp -d)"; mkdir -p "$HOME/.local/bin"
      if curl -fsSL "https://nodejs.org/dist/${NVER}/${NFILE}" -o "$NTMP/node.tgz" && tar -xzf "$NTMP/node.tgz" -C "$HOME/.local"; then
        NDIR="$HOME/.local/${NFILE%.tar.gz}"
        for b in node npm npx; do [ -e "$NDIR/bin/$b" ] && ln -sf "$NDIR/bin/$b" "$HOME/.local/bin/$b"; done
        case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
        hash -r 2>/dev/null || true
        have node && say "Node.js $(node --version) installed" || warn "Node in $NDIR — add ~/.local/bin to PATH"
      else warn "Node download/extract failed — install from https://nodejs.org"; fi
      rm -rf "$NTMP" 2>/dev/null || true
    fi
  else warn "install Node.js >= ${NEED_NODE} from https://nodejs.org (need curl or brew)"; fi
fi

# --- Pre-warm the Azure DevOps MCP server (latest) --------------------------
if have npx || [ "$DRY" = 1 ]; then
  say "Caching latest @azure-devops/mcp"
  run "npx -y @azure-devops/mcp@latest --help >/dev/null 2>&1 || true"
fi

# --- Configure org / project / PAT ------------------------------------------
configure_ado() {
  local org proj pat secrets="$HOME/.omp/secrets.env" p
  local profiles=("$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc")
  printf '    AZURE_DEVOPS_ORG (e.g. https://dev.azure.com/<org>): '; read -r org </dev/tty || org=""
  [ -z "$org" ] && { warn "no org entered — skipping ADO credential write"; return; }
  printf '    AZURE_DEVOPS_PROJECT (optional default): '; read -r proj </dev/tty || proj=""
  printf '    AZURE_DEVOPS_PAT (hidden; Code R/W, PR R/W, +Build R): '; read -r -s pat </dev/tty || pat=""; echo
  if [ "$DRY" = 1 ]; then echo "  [dry-run] write ORG/PROJECT to ~/.profile, PAT to $secrets (chmod 600)"; return; fi
  [ -e "$HOME/.profile" ] || : > "$HOME/.profile"
  for p in "${profiles[@]}"; do [ -e "$p" ] || continue
    grep -qsF AZURE_DEVOPS_ORG "$p" || printf '\nexport AZURE_DEVOPS_ORG=%q\n' "$org" >> "$p"
    [ -n "$proj" ] && { grep -qsF AZURE_DEVOPS_PROJECT "$p" || printf 'export AZURE_DEVOPS_PROJECT=%q\n' "$proj" >> "$p"; }
  done
  if [ -n "$pat" ]; then
    mkdir -p "$(dirname "$secrets")"; touch "$secrets"; chmod 600 "$secrets"
    grep -qsF AZURE_DEVOPS_PAT "$secrets" || printf 'export AZURE_DEVOPS_PAT=%q\n' "$pat" >> "$secrets"
    for p in "${profiles[@]}"; do [ -e "$p" ] || continue; grep -qsF secrets.env "$p" || printf '\n[ -f "%s" ] && . "%s"\n' "$secrets" "$secrets" >> "$p"; done
    echo "  PAT stored in $secrets (chmod 600), sourced from your profile."
  fi
  echo "  org/project written to your shell profile."
}

if [ -n "${AZURE_DEVOPS_ORG:-}" ] && [ -n "${AZURE_DEVOPS_PAT:-}" ]; then
  say "Azure DevOps already configured via environment — skipping prompt"
elif [ "$CONFIG" = skip ] || { [ "$CONFIG" = auto ] && { [ "$YES" = 1 ] || [ ! -r /dev/tty ]; }; }; then
  say "Skipping ADO credential prompt (non-interactive)"
  echo "    Set later:  AZURE_DEVOPS_ORG / AZURE_DEVOPS_PROJECT / AZURE_DEVOPS_PAT"
else
  say "Configure Azure DevOps credentials"
  configure_ado
fi

# --- Load the `ado` tool ----------------------------------------------------
# OMP does NOT load extension modules (package.json `omp.extensions`) from
# marketplace cache installs, so the `ado` tool would otherwise never appear.
# Mirror it into OMP's native user-extension dir, which is always discovered.
HERE_EXT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$HERE_EXT/extensions" ]; then
  DEST="$HOME/.omp/agent/extensions/azure-devops-fs"
  if [ "$DRY" = 1 ]; then echo "  [dry-run] mirror ado extension -> $DEST (OMP native ext dir)"
  else
    rm -rf "$DEST"; mkdir -p "$DEST"; cp -R "$HERE_EXT/extensions" "$DEST/"
    [ -f "$HERE_EXT/package.json" ] && cp "$HERE_EXT/package.json" "$DEST/"
    say "ado tool loaded into $DEST"
  fi
fi

cat <<'EOF'

==> azure-devops-fs ready. The `ado` tool is now loaded by OMP.
    Set AZURE_DEVOPS_ORG / AZURE_DEVOPS_PAT (above) and use it, e.g.:
      ado op=pr_view  uri=adopr://myrepo/4213
      ado op=pr_checks repo=myrepo id=4213
    Note: Azure DevOps PRs are NOT pr:// (that's GitHub). Use the `ado` tool
    with adopr:// URIs or repo/id fields.
    Optional: the Microsoft `azure-devops` MCP server (enabled:false) in the
    merged .mcp.json is an alternative backend; the PAT is injected per-request.
EOF
