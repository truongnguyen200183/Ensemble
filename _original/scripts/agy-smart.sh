#!/usr/bin/env bash
# Smart Fallback Wrapper for Google Antigravity CLI (agy)
STATE_FILE="${HOME}/.ensemble/exhausted-models.txt"
mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"

TIER_MODELS=(
  "gemini-4-argon-high"
  "gemini-4-argon-medium"
  "gemini-4-argon-low"
  "gemini-4-hydrogen-xhigh"
  "gemini-4-hydrogen-high"
  "gemini-4-hydrogen-medium"
  "gemini-4-hydrogen-low"
  "gemini-pro-orchestrator-g1-pro"
  "claude-opus-5-5-high"
  "claude-opus-5-5-medium"
  "claude-opus-5-5-low"
  "claude-sonnet-5-5-high"
  "claude-sonnet-5-5-medium"
  "claude-sonnet-5-5-low"
  "gemini-3.8-flash-high"
  "gemini-3.8-flash-medium"
  "gemini-3.8-flash-low"
  "gpt-oss-120b-medium"
)

REQUESTED_MODEL=""
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
    REQUESTED_MODEL="${!next_i}"
    SKIP_NEXT=1
  elif [ "$ARG" == "--effort" ]; then
    SKIP_NEXT=1
  elif [[ "$ARG" == --effort=* ]]; then
    continue
  else
    ARGS+=("$ARG")
  fi
done

CHOSEN_MODEL="$REQUESTED_MODEL"

# Find index of requested model
START_INDEX=0
for idx in "${!TIER_MODELS[@]}"; do
  if [ "${TIER_MODELS[$idx]}" == "$REQUESTED_MODEL" ]; then
    START_INDEX=$idx
    break
  fi
done

# If requested model is exhausted, step down tier by tier
for ((idx=$START_INDEX; idx<${#TIER_MODELS[@]}; idx++)); do
  candidate="${TIER_MODELS[$idx]}"
  if ! grep -q "^$candidate$" "$STATE_FILE" 2>/dev/null; then
    CHOSEN_MODEL="$candidate"
    break
  fi
done

if [ -n "$CHOSEN_MODEL" ] && [ "$CHOSEN_MODEL" != "$REQUESTED_MODEL" ]; then
  echo "[Ensemble Fallback] Model '$REQUESTED_MODEL' het quota -> Tu dong ha xuong cap: '$CHOSEN_MODEL'" >&2
fi

exec /usr/local/bin/agy "${ARGS[@]}" --model "$CHOSEN_MODEL"

