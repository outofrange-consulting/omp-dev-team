#!/usr/bin/env bash
# setup-local-models.sh — pull the local model the dev-team small tier uses.
#
# Target: AMD 9950X + 64GB RAM + RTX 5070 Ti 16GB. The small tier (model:
# pi/smol) routes here; the Sonnet/Opus tiers stay on cloud. Default backend is
# Ollama (auto-discovered by OMP). The flags below expose stronger options.
#
# Usage:
#   scripts/setup-local-models.sh             # DEFAULT: Qwen3-Coder-30B-A3B (Ollama)
#   scripts/setup-local-models.sh --fast      # also pull 14B + 7B (throughput)
#   scripts/setup-local-models.sh --devstral  # also pull Devstral Small 2 (full-VRAM)
#   scripts/setup-local-models.sh --next       # print Qwen3-Coder-Next (llama.cpp) setup
#   scripts/setup-local-models.sh --flash      # print Qwen3-Coder-30B (llama.cpp) setup
#   scripts/setup-local-models.sh --ctx 49152  # bake a larger context window
#
# Quality ladder for 16GB VRAM + 64GB RAM:
#   * ollama/qwen3-coder:30b      30B-A3B MoE  ~18GB  — DEFAULT (offloads to RAM)
#   * llama.cpp/qwen3-coder-next  80B-A3B MoE  ~40GB  — best quality, fits 64GB
#   * ollama/devstral             24B dense    ~14GB  — full-VRAM, max throughput
#   * ollama/qwen2.5-coder:14b    14B dense    ~9GB   — full-VRAM, lighter

set -euo pipefail

PRIMARY="qwen3-coder:30b"        # 30B-A3B MoE (~3.3B active); offloads to 64GB RAM
FAST="qwen2.5-coder:14b"         # dense, fits fully in 16GB VRAM — max throughput
TINY="qwen2.5-coder:7b"          # smallest, highest tok/s
DEVSTRAL="devstral"              # Devstral Small 2 (Mistral, 24B dense, SWE-tuned)
NUM_CTX="32768"
PULL_FAST=0
PULL_DEVSTRAL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fast)     PULL_FAST=1; shift ;;
    --devstral) PULL_DEVSTRAL=1; shift ;;
    --ctx)      NUM_CTX="$2"; shift 2 ;;
    --next)     SHOW="next"; shift ;;
    --flash)    SHOW="flash"; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# ---- llama.cpp guidance modes (print-only) --------------------------------
if [[ "${SHOW:-}" == "next" ]]; then
  cat <<EOF
==> Qwen3-Coder-Next (80B-A3B MoE) via llama.cpp — best quality that fits 64GB

~40GB at Q4 (80B total / ~3B active, hybrid Gated DeltaNet + attention, 256K ctx).
Needs a RECENT llama.cpp build (DeltaNet support). Keep attention + KV on the
5070 Ti, push all experts to CPU/RAM:

  llama-server -hf unsloth/Qwen3-Coder-Next-GGUF:Q4_K_XL \\
    -ngl 99 -ot ".ffn_.*_exps.=CPU" -c ${NUM_CTX} --host 127.0.0.1 --port 8080

Notes:
  * ~40GB lives in RAM — fine on 64GB, but a very large -c eats into that.
  * Then point the small tier at it in .omp/config.yml:
        modelRoles:
          smol: llama.cpp/qwen3-coder-next
  * Uncomment the llama.cpp provider in models.yml.example -> ~/.omp/agent/models.yml
EOF
  exit 0
fi

if [[ "${SHOW:-}" == "flash" ]]; then
  cat <<EOF
==> Qwen3-Coder-30B-A3B via llama.cpp — max speed on the 30B

  llama-server -hf unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_XL \\
    -ngl 99 --n-cpu-moe 28 -c ${NUM_CTX} --host 127.0.0.1 --port 8080

Tuning: lower --n-cpu-moe until VRAM is ~full (more experts on GPU = faster),
or pin all experts to CPU with: -ot ".ffn_.*_exps.=CPU"
Then: modelRoles.smol: llama.cpp/qwen3-coder-30b-a3b
EOF
  exit 0
fi

# ---- Ollama pulls ---------------------------------------------------------
if ! command -v ollama >/dev/null 2>&1; then
  cat >&2 <<'EOF'
ollama not found. Install it first:
  curl -fsSL https://ollama.com/install.sh | sh
Then re-run. (For the llama.cpp paths use --next or --flash; for LM Studio see
models.yml.example.)
EOF
  exit 1
fi

echo "==> Pulling $PRIMARY (small tier default, MoE — offloads to your 64GB RAM)…"
ollama pull "$PRIMARY"

if [[ "$PULL_FAST" == "1" ]]; then
  echo "==> Pulling $FAST (full-VRAM throughput option)…"; ollama pull "$FAST"
  echo "==> Pulling $TINY (max throughput)…";              ollama pull "$TINY"
fi

if [[ "$PULL_DEVSTRAL" == "1" ]]; then
  echo "==> Pulling $DEVSTRAL (Devstral Small 2, 24B dense — full-VRAM, SWE-tuned)…"
  ollama pull "$DEVSTRAL"
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
Swap modelRoles.smol to pick another rung:
  ollama/${DERIVED}              larger-context build of the default
  llama.cpp/qwen3-coder-next     best quality (run: setup-local-models.sh --next)
  ollama/${DEVSTRAL}             Devstral Small 2, full-VRAM (needs --devstral)
  ollama/${FAST}                 14B dense, full-VRAM (needs --fast)
  claude-haiku-4-5               go fully cloud
EOF
