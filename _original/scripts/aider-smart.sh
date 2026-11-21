#!/usr/bin/env bash
# Runner for Aider connected to local Ollama (gemma4:12b)
# Usage: aider-smart [options]

export OLLAMA_API_BASE="${OLLAMA_API_BASE:-http://192.168.86.23:11434}"
export OPENAI_API_BASE="${OPENAI_API_BASE:-http://192.168.86.23:11434/v1}"
export OPENAI_API_KEY="${OPENAI_API_KEY:-ollama}"

MODEL="ollama/gemma4:12b"
ARGS=()
SKIP_NEXT=0

for ((i=1; i<=$#; i++)); do
  if [ $SKIP_NEXT -eq 1 ]; then
    SKIP_NEXT=0
    continue
  fi
  ARG="${!i}"
  if [ "$ARG" == "--model" ]; then
    next_i=$((i+1))
    M="${!next_i}"
    if [[ "$M" == "ollama-gemma" || "$M" == "gemma4:12b" ]]; then
      MODEL="ollama/gemma4:12b"
    elif [[ "$M" == "ollama-qwen" || "$M" == "qwen3-coder:30b" || "$M" == "qwen3-coder" ]]; then
      MODEL="ollama/qwen3-coder:30b"
    elif [[ "$M" != ollama/* && "$M" != openai/* ]]; then
      MODEL="ollama/$M"
    else
      MODEL="$M"
    fi
    SKIP_NEXT=1
  elif [ "$ARG" == "--effort" ]; then
    SKIP_NEXT=1
  elif [[ "$ARG" == --effort=* ]]; then
    continue
  else
    ARGS+=("$ARG")
  fi
done

AIDER_BIN="$(command -v aider || echo "$HOME/.local/bin/aider")"

exec "$AIDER_BIN" \
  --model "$MODEL" \
  --yes-always \
  --no-auto-commits \
  --no-analytics \
  --dark-mode \
  "${ARGS[@]}"
