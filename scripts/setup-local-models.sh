#!/usr/bin/env bash
# setup-local-models.sh — pull the local model the dev-team small tier uses.
#
# Target: AMD 9950X + 64GB RAM + RTX 5070 Ti 16GB. The small tier (model:
# pi/smol) routes here; the Sonnet/Opus tiers stay on cloud. Default backend is
# Ollama (auto-discovered by OMP); --flash prints the llama.cpp max-perf path.
#
# Usage:
#   scripts/setup-local-models.sh             # pull Qwen3-Coder-30B-A3B (default)
#   scripts/setup-local-models.sh --fast      # also pull 14B + 7B (throughput)
#   scripts/setup-local-models.sh --ctx 49152 # bake a larger context window
#   scripts/setup-local-models.sh --flash     # print the llama.cpp 30B setup

set -euo pipefail

PRIMARY="qwen3-coder:30b"        # 30B-A3B MoE (~3.3B active); offloads to 64GB RAM
FAST="qwen2.5-coder:14b"         # dense, fits fully in 16GB VRAM — max throughput
TINY="qwen2.5-coder:7b"          # smallest, highest tok/s
NUM_CTX="32768"
PULL_FAST=0
FLASH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fast)  PULL_FAST=1; shift ;;
    --ctx)   NUM_CTX="$2"; shift 2 ;;
    --flash) FLASH=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ "$FLASH" == "1" ]]; then
  cat <<EOF
==> llama.cpp (max performance on Qwen3-Coder-30B-A3B)

Install llama.cpp (with CUDA), then run a single-model server with MoE expert
offload to CPU/RAM — attention + KV stay on the 5070 Ti:

  llama-server -hf unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_XL \\
    -ngl 99 --n-cpu-moe 28 -c ${NUM_CTX} --host 127.0.0.1 --port 8080

Tuning:
  * Lower --n-cpu-moe until VRAM is ~full (more experts on GPU = faster).
  * Or pin all experts to CPU:  -ot ".ffn_.*_exps.=CPU"

Then point the small tier at it in .omp/config.yml:
  modelRoles:
    smol: llama.cpp/qwen3-coder-30b-a3b

(uncomment the llama.cpp provider in models.yml.example -> ~/.omp/agent/models.yml)
EOF
  exit 0
fi

if ! command -v ollama >/dev/null 2>&1; then
  cat >&2 <<'EOF'
ollama not found. Install it first:
  curl -fsSL https://ollama.com/install.sh | sh
Then re-run. (For max performance on the 30B, use --flash for the llama.cpp path,
or see models.yml.example for LM Studio.)
EOF
  exit 1
fi

echo "==> Pulling $PRIMARY (small tier default, MoE — offloads to your 64GB RAM)…"
ollama pull "$PRIMARY"

if [[ "$PULL_FAST" == "1" ]]; then
  echo "==> Pulling $FAST (full-VRAM throughput option)…"; ollama pull "$FAST"
  echo "==> Pulling $TINY (max throughput)…";              ollama pull "$TINY"
fi

# Bake a larger context window into a derived model so review of bigger diffs
# fits. (OMP's OLLAMA_CONTEXT_LENGTH does not set num_ctx — Ollama does.)
DERIVED="${PRIMARY%%:*}:dev-team"
echo "==> Creating ${DERIVED} with num_ctx=${NUM_CTX}…"
TMP_MODELFILE="$(mktemp)"
printf 'FROM %s\nPARAMETER num_ctx %s\n' "$PRIMARY" "$NUM_CTX" > "$TMP_MODELFILE"
ollama create "$DERIVED" -f "$TMP_MODELFILE" || true
rm -f "$TMP_MODELFILE"

cat <<EOF

Done. Verify OMP sees the model:
  omp --list-models | grep -i ollama

The small tier points at 'ollama/${PRIMARY}' in .omp/config.yml (modelRoles.smol).
For the larger-context build:        modelRoles.smol: ollama/${DERIVED}
For max throughput (full-VRAM):      modelRoles.smol: ollama/${FAST}    (needs --fast)
For max speed on the 30B:            scripts/setup-local-models.sh --flash
To go fully cloud:                   modelRoles.smol: claude-haiku-4-5
EOF
