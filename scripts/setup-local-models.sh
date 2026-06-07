#!/usr/bin/env bash
# setup-local-models.sh — pull the local models the dev-team small tier uses.
#
# Target: NVIDIA 5070 Ti 16GB. The small tier (model: pi/smol) routes here; the
# Sonnet/Opus tiers stay on cloud. Defaults to Ollama (auto-discovered by OMP).
#
# Usage:
#   scripts/setup-local-models.sh            # pull the default 14B coder
#   scripts/setup-local-models.sh --fast     # also pull the 7B (throughput)
#   scripts/setup-local-models.sh --ctx 32768

set -euo pipefail

PRIMARY="qwen2.5-coder:14b"     # ~9GB Q4_K_M — quality/perf sweet spot on 16GB
FAST="qwen2.5-coder:7b"         # faster, lighter, for high fan-out review
NUM_CTX="32768"
PULL_FAST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fast) PULL_FAST=1; shift ;;
    --ctx)  NUM_CTX="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if ! command -v ollama >/dev/null 2>&1; then
  cat >&2 <<'EOF'
ollama not found. Install it first:
  curl -fsSL https://ollama.com/install.sh | sh
Then re-run this script. (Alternatively use llama.cpp or LM Studio — see
models.yml.example.)
EOF
  exit 1
fi

echo "==> Pulling $PRIMARY (small tier default)…"
ollama pull "$PRIMARY"

if [[ "$PULL_FAST" == "1" ]]; then
  echo "==> Pulling $FAST (fast/throughput option)…"
  ollama pull "$FAST"
fi

# Bake a larger context window into a derived model so review of bigger diffs
# fits. OMP's OLLAMA_CONTEXT_LENGTH does not set num_ctx — Ollama does.
echo "==> Creating ${PRIMARY%%:*}:dev-team with num_ctx=${NUM_CTX}…"
TMP_MODELFILE="$(mktemp)"
printf 'FROM %s\nPARAMETER num_ctx %s\n' "$PRIMARY" "$NUM_CTX" > "$TMP_MODELFILE"
ollama create "${PRIMARY%%:*}:dev-team" -f "$TMP_MODELFILE" || true
rm -f "$TMP_MODELFILE"

cat <<EOF

Done. Verify OMP sees the model:
  omp --list-models | grep -i ollama

The small tier points at 'ollama/${PRIMARY}' in .omp/config.yml (modelRoles.smol).
To use the larger-context build instead, set:
  modelRoles:
    smol: ollama/${PRIMARY%%:*}:dev-team

Tiers Sonnet/Opus remain on Anthropic. To go fully cloud, set
  modelRoles.smol: claude-haiku-4-5
EOF
