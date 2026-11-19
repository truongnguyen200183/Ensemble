#!/usr/bin/env bash
# Runner for Google Antigravity CLI (agy)
# Disables silent auto-fallback: executes the exact model requested by the user.

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

if [ -n "$REQUESTED_MODEL" ]; then
  exec /usr/local/bin/agy "${ARGS[@]}" --model "$REQUESTED_MODEL"
else
  exec /usr/local/bin/agy "${ARGS[@]}"
fi
