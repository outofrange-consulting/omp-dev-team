#!/usr/bin/env bash
# azure-devops-fs installer (Linux/macOS) — installs the Azure CLI (`az`) + the
# `azure-devops` extension (the `ado` tool's backend), mirrors the extension into
# OMP's native dir, and (when interactive) prompts for the org/project/PAT,
# persists them, and runs `az devops login` (PAT mode).
# Flags:
#   --configure   force the org/project/PAT prompt
#   --no-config   never prompt for credentials
#   --no-update   no-op (kept for installer compatibility)
#   -y, --yes     non-interactive (skip the credential prompt)
set -euo pipefail

YES=0; CONFIG=auto; INSECURE_TLS=0
for a in "$@"; do case "$a" in
  --no-update) ;; -y|--yes) YES=1 ;; --insecure-tls) INSECURE_TLS=1 ;; --ca-file=*) CA_FILE="${a#*=}" ;;
  --configure) CONFIG=force ;; --no-config) CONFIG=skip ;;
  -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
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

# --- Azure CLI (az) + azure-devops extension --------------------------------
# The `ado` tool drives `az` so it inherits the OS cert store + proxy (works
# behind Zscaler/Trend under WSL). Everything is per-user (no sudo).
# Persist ~/.local/bin on PATH for future shells too — matters when `az` falls
# back to `pip install --user` below, landing it there instead of a system path.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
for p in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -e "$p" ] || continue
  grep -qsF "$HOME/.local/bin" "$p" 2>/dev/null && continue
  printf '\n# omp-dev-team\nexport PATH="%s:$PATH"\n' "$HOME/.local/bin" >> "$p"
done
if have az; then
  say "Azure CLI present ($(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo ok))"
else
  say "Installing Azure CLI (per-user, no sudo)"
  if have brew; then run "brew install azure-cli"
  elif have pipx; then run "pipx install azure-cli"
  elif have pip3; then run "pip3 install --user azure-cli"
  elif have python3 && python3 -m pip --version >/dev/null 2>&1; then run "python3 -m pip install --user azure-cli"
  else warn "could not install Azure CLI without sudo — install it from https://aka.ms/azcli (e.g. 'pip install --user azure-cli'), then re-run"; fi
  hash -r 2>/dev/null || true
fi
# azure-devops extension (per-user, lands in ~/.azure — no sudo)
if have az; then
  if az extension show --name azure-devops >/dev/null 2>&1; then say "azure-devops CLI extension present"
  else say "Adding the azure-devops CLI extension"; run "az extension add --name azure-devops --only-show-errors || true"; fi
fi
have git || warn "git not found — pr_checkout / pr_push need it (install git)"

# --- Configure org / project / PAT ------------------------------------------
# Persist org/project (profile) + PAT (secrets.env, chmod 600) for the `ado`
# tool, and run `az devops login` (PAT mode) for direct `az` use.
az_login() {  # az_login <org-name> <project> <pat>
  have az || return 0
  local orgurl="https://dev.azure.com/$1"
  az devops configure --defaults "organization=$orgurl" ${2:+"project=$2"} --only-show-errors >/dev/null 2>&1 || true
  if [ -n "$3" ]; then
    printf '%s' "$3" | az devops login --organization "$orgurl" --only-show-errors >/dev/null 2>&1 \
      && echo "  az devops login OK ($orgurl)" || warn "az devops login failed — the PAT env still works for the ado tool"
  fi
}
configure_ado() {
  local org proj pat secrets="$HOME/.omp/secrets.env" p
  local profiles=("$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc")
  printf '    AZURE_DEVOPS_ORG (org NAME only, e.g. contoso — not the URL): '; read -r org </dev/tty || org=""
  [ -z "$org" ] && { warn "no org entered — skipping ADO credential write"; return; }
  org="${org#https://dev.azure.com/}"; org="${org%/}"   # tolerate a pasted URL
  printf '    AZURE_DEVOPS_PROJECT (optional default): '; read -r proj </dev/tty || proj=""
  printf '    AZURE_DEVOPS_PAT (hidden; Code R/W, PR R/W, Build R, Policy R): '; read -r -s pat </dev/tty || pat=""; echo
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
  az_login "$org" "$proj" "$pat"
}

if [ -n "${AZURE_DEVOPS_ORG:-}" ] && [ -n "${AZURE_DEVOPS_PAT:-}" ]; then
  say "Azure DevOps already configured via environment — running az devops login"
  AZ_ORG="${AZURE_DEVOPS_ORG#https://dev.azure.com/}"; AZ_ORG="${AZ_ORG%/}"
  az_login "$AZ_ORG" "${AZURE_DEVOPS_PROJECT:-}" "$AZURE_DEVOPS_PAT"
elif [ "$CONFIG" = skip ] || { [ "$CONFIG" = auto ] && { [ "$YES" = 1 ] || [ ! -r /dev/tty ]; }; }; then
  say "Skipping ADO credential prompt (non-interactive)"
  echo "    Set later:  AZURE_DEVOPS_ORG (org name) / AZURE_DEVOPS_PROJECT / AZURE_DEVOPS_PAT,  then: az devops login"
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
  rm -rf "$DEST"; mkdir -p "$DEST"; cp -R "$HERE_EXT/extensions" "$DEST/"
  [ -f "$HERE_EXT/package.json" ] && cp "$HERE_EXT/package.json" "$DEST/"
  say "ado tool loaded into $DEST"
fi

# If az landed in ~/.local/bin (pip --user fallback), warn when it's not yet
# visible to a fresh shell — an already-running OMP process keeps its old
# PATH until restarted (re-running this script again will not fix it).
if have az; then
  case "$(command -v az)" in
    "$HOME/.local/bin/"*) bash -lc 'command -v az' >/dev/null 2>&1 || warn "az installed to ~/.local/bin but NOT visible in a fresh shell yet. An already-running OMP process keeps missing it until you RESTART OMP." ;;
  esac
fi

cat <<'EOF'

==> azure-devops-fs ready. The `ado` tool is loaded by OMP and backed by `az`.
    Restart omp, then use it, e.g.:
      ado op=pr_view  uri=adopr://myrepo/4213
      ado op=pr_checks repo=myrepo id=4213
    Note: Azure DevOps PRs are NOT pr:// (that's GitHub). Use the `ado` tool
    with adopr:// URIs or repo/id fields.
EOF
