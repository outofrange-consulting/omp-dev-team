#!/usr/bin/env bash
# local-llm installer (Linux/macOS) — set up local LLMs for OMP, sized to your
# hardware. Detects VRAM/RAM, asks (≥8GB VRAM recommended), installs the backend
# (Ollama auto, or llama.cpp guided), pulls the best-fit models, and wires roles.
# Flags:
#   --backend ollama|llama.cpp   (default: ask / ollama)
#   --vram N --ram N             override detection
#   --all                        pull every fitting model (default: role models only)
#   --apply-config               append the role wiring to ~/.omp/agent/config.yml
#   --dry-run / -y
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0; YES=0; BACKEND=""; VRAM=""; RAM=""; ALL=0; APPLY=0; LEVEL=""
for a in "$@"; do case "$a" in
  --dry-run) DRY=1 ;; -y|--yes) YES=1 ;; --all) ALL=1 ;; --apply-config) APPLY=1 ;;
  --backend=*) BACKEND="${a#*=}" ;; --vram=*) VRAM="${a#*=}" ;; --ram=*) RAM="${a#*=}" ;; --level=*) LEVEL="${a#*=}" ;;
  --backend|--vram|--ram|--level) echo "use $a=VALUE" >&2; exit 2 ;;
  -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 2 ;;
esac; done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m  ! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else eval "$@"; fi; }
ask() { # ask "Q" default(Y/n)
  local q="$1" def="${2:-Y}" ans
  [ "$YES" = 1 ] && return 0
  [ -r /dev/tty ] || { case "$def" in [Yy]*) return 0;; *) return 1;; esac; }
  read -r -p "$q [$([ "$def" = Y ] && echo Y/n || echo y/N)] " ans </dev/tty || ans=""
  case "${ans:-$def}" in [Yy]*) return 0;; *) return 1;; esac
}

# --- bun (runs the selector CLI) -------------------------------------------
BUN="$(command -v bun || echo "$HOME/.bun/bin/bun")"
[ -x "$BUN" ] || { warn "bun not found — install OMP first (bash install.sh at repo root)"; exit 1; }

# Run the selector CLI, passing --vram/--ram only when given so an externally
# exported OMP_LOCAL_VRAM_GB / OMP_LOCAL_RAM_GB is still respected.
compute_plan() { # compute_plan <backend>
  local ev=()
  [ -n "$VRAM" ] && ev+=("OMP_LOCAL_VRAM_GB=$VRAM")
  [ -n "$RAM" ] && ev+=("OMP_LOCAL_RAM_GB=$RAM")
  env ${ev[@]+"${ev[@]}"} "$BUN" "$HERE/extensions/local-llm.ts" --json --backend "$1" --level "${LEVEL:-smol}"
}

# --- compute the plan -------------------------------------------------------
say "Detecting hardware and computing the model plan"
PLAN="$(compute_plan "${BACKEND:-ollama}")"
field() { printf '%s' "$PLAN" | "$BUN" -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const j=JSON.parse(s);$1})"; }
VRAMGB="$(field "process.stdout.write(String(j.hardware.vramGB))")"
RAMGB="$(field "process.stdout.write(String(j.hardware.ramGB))")"
SOURCE="$(field "process.stdout.write(j.hardware.source||'?')")"
echo "  Detected: ${VRAMGB}GB VRAM / ${RAMGB}GB RAM (via ${SOURCE})"

# --- gate: ≥8GB VRAM recommended -------------------------------------------
if [ "${VRAMGB:-0}" -lt 8 ]; then
  warn "Only ${VRAMGB}GB VRAM detected. Local LLMs want ≥8GB; cloud (copilot-preset) is a better fit."
  # Hardware gate: never auto-proceed without a GPU (don't install a backend on a
  # GPU-less machine just because -y was passed / there's no TTY).
  if [ "$YES" = 1 ] || [ ! -r /dev/tty ]; then echo "Non-interactive with <8GB VRAM — skipping local-llm setup."; exit 0; fi
  ask "Set up local LLMs anyway?" "N" || { echo "Skipping local-llm setup."; exit 0; }
else
  ask "Set up local LLMs for OMP (sized to ${VRAMGB}GB VRAM)?" "Y" || { echo "Skipping."; exit 0; }
fi

# --- choose backend ---------------------------------------------------------
if [ -z "$BACKEND" ]; then
  if ask "Use Ollama? (recommended; 'n' = llama.cpp, advanced)" "Y"; then BACKEND="ollama"; else BACKEND="llama.cpp"; fi
fi

# --- how much to run locally (conservative by default) ----------------------
if [ -z "$LEVEL" ]; then
  if [ "$YES" = 1 ] || [ ! -r /dev/tty ]; then LEVEL="smol"
  else
    echo "  How much should run on LOCAL models?"
    echo "    1) smol      — only cheap/high-volume roles local; task/default stay cloud (recommended)"
    echo "    2) balanced  — also task/slow local IF a strong model fits"
    echo "    3) max       — also default local IF a top model fits fully on the GPU (big config)"
    echo "    4) local-only— everything local incl. default/plan (power users)"
    read -r -p "  Choice [1]: " lv </dev/tty || lv=1
    case "${lv:-1}" in 2) LEVEL=balanced;; 3) LEVEL=max;; 4) LEVEL=local-only;; *) LEVEL=smol;; esac
  fi
fi

# Recompute plan for the chosen backend + level (served ids / wiring differ).
PLAN="$(compute_plan "$BACKEND")"
ROLES_YAML="$(field "process.stdout.write(j.rolesYaml)")"
if [ "$ALL" = 1 ]; then
  PULLS="$(field "process.stdout.write((j.pullsAll||[]).join('\n'))")"
else
  PULLS="$(field "process.stdout.write((j.pulls||[]).join('\n'))")"
fi
echo "  Level: ${LEVEL}  ·  models to pull: $(printf '%s' "$PULLS" | tr '\n' ' ')"

# --- install backend --------------------------------------------------------
if [ "$BACKEND" = "ollama" ]; then
  if have ollama; then say "Ollama present ($(ollama --version 2>/dev/null | head -1))"
  else
    say "Installing Ollama"
    if [ "$(uname)" = Darwin ] && have brew; then run "brew install --cask ollama || brew install ollama"
    elif have curl; then run "curl -fsSL https://ollama.com/install.sh | sh"
    else warn "install Ollama from https://ollama.com/download"; fi
  fi
  if [ "$DRY" = 0 ] && have ollama && ! curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    say "Starting 'ollama serve' (background)"; (ollama serve >/dev/null 2>&1 &) ; sleep 3 || true
  fi
  say "Pulling role models (${BACKEND})"
  printf '%s\n' "$PULLS" | while IFS= read -r tag; do [ -n "$tag" ] && run "ollama pull \"$tag\""; done
else
  # llama.cpp — install the server; model GGUFs are fetched lazily by llama-server.
  if have llama-server; then say "llama.cpp present"
  else
    say "Installing llama.cpp"
    if have brew; then run "brew install llama.cpp"
    else warn "Install llama.cpp (llama-server) from https://github.com/ggml-org/llama.cpp/releases and put it on PATH."; fi
  fi
  TOP="$(field "process.stdout.write((j.roles.task||j.roles.default||''))")"
  cat <<EOF

  llama.cpp is single-model-per-server. Start your primary (${TOP}) e.g.:
    llama-server -hf <HF-GGUF-repo-for-${TOP}> -ngl 99 -ot ".ffn_.*_exps.=CPU" -c 32768 --port 8080
  (browse GGUFs on huggingface.co; prefer Q4_K_M / IQ3 quants for 16GB). Then
  OMP reaches it on :8080. For multi-model, consider 'llama-swap'.
EOF
  # Make the extension target llama.cpp.
  if [ "$DRY" = 0 ]; then
    for p in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
      [ -e "$p" ] || continue; grep -qsF OMP_LOCAL_BACKEND "$p" || printf '\nexport OMP_LOCAL_BACKEND=llama.cpp\n' >> "$p"
    done
  fi
fi

# --- wire roles into OMP config --------------------------------------------
CFG="$HOME/.omp/agent/config.yml"
if [ "$APPLY" = 1 ] || ask "Append the role wiring to $CFG?" "Y"; then
  if [ "$DRY" = 1 ]; then echo "  [dry-run] append modelRoles/enabledModels to $CFG"
  else
    mkdir -p "$(dirname "$CFG")"; touch "$CFG"
    if grep -q "local-llm (appended" "$CFG" 2>/dev/null; then echo "  (already present — skipping)"
    else { echo ""; echo "# --- local-llm (appended $(date -u +%FT%TZ)) ---"; printf '%s\n' "$ROLES_YAML"; } >> "$CFG"; echo "  appended to $CFG"; fi
  fi
fi

cat <<EOF

==> local-llm ready (backend: ${BACKEND}).
    - The plugin's extension auto-registers fitting local models each session as
      the 'local-llm' provider; run /local-llm to re-detect and reprint the plan.
    - Heavy planning stays on cloud (plan/default = Opus); execution/cheap roles
      run locally. Edit modelRoles in $CFG to taste.
    - Re-run with --all to pull every fitting model, or --vram=N --ram=N to test
      a different machine.
EOF
