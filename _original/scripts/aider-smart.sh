#!/usr/bin/env bash
# Runner for Aider connected to local Ollama (gemma4:12b / qwen3-coder:30b)
# Hard context cap: 16384 tokens (num_ctx: 16384, max-chat-history-tokens: 12288)
# Usage: aider-smart [options]

MODEL=""
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
    if [[ "$M" == ollama/* || "$M" == openai/* || "$M" == deepseek/* || "$M" == openrouter/* ]]; then
      MODEL="$M"
    elif [[ "$M" == ollama-* ]]; then
      MODEL="ollama/${M#ollama-}"
    elif [[ "$M" == openai-* ]]; then
      MODEL="openai/${M#openai-}"
    elif [[ "$M" == deepseek-* ]]; then
      MODEL="deepseek/${M#deepseek-}"
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

export OLLAMA_API_BASE="${OLLAMA_API_BASE:-http://192.168.86.22:11434}"
if [[ "$MODEL" == ollama/* ]]; then
  export OPENAI_API_BASE="${OPENAI_API_BASE:-http://192.168.86.22:11434/v1}"
  export OPENAI_API_KEY="${OPENAI_API_KEY:-ollama}"
fi

# Locate model settings & metadata for context window (16384 tokens limit)
EXTRA_FLAGS=()
for s in "$(pwd)/.aider.model.settings.yml" "$HOME/ensemble/.aider.model.settings.yml" "$HOME/.aider.model.settings.yml"; do
  if [ -f "$s" ]; then
    EXTRA_FLAGS+=("--model-settings-file" "$s")
    break
  fi
done

for m in "$(pwd)/.aider.model.metadata.json" "$HOME/ensemble/.aider.model.metadata.json" "$HOME/.aider.model.metadata.json"; do
  if [ -f "$m" ]; then
    EXTRA_FLAGS+=("--model-metadata-file" "$m")
    break
  fi
done

AIDER_BIN="$(command -v aider || echo "$HOME/.local/bin/aider")"

exec "$AIDER_BIN" \
  --model "$MODEL" \
  --max-chat-history-tokens 12288 \
  --no-check-model-accepts-settings \
  "${EXTRA_FLAGS[@]}" \
  --yes-always \
  --no-auto-commits \
  --no-analytics \
  --dark-mode \
  "${ARGS[@]}"
