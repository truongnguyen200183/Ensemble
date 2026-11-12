#!/usr/bin/env bash
# Wrapper chạy Claude Code (gói Claude Pro) cho Ensemble.
# Nhận model dạng cc-<opus|sonnet>-<low|medium|high> và đổi thành
# --model <alias> --effort <level> của Claude Code CLI.
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN

ARGS=()
MODEL=""
SKIP_NEXT=0
for ((i=1; i<=$#; i++)); do
  if [ $SKIP_NEXT -eq 1 ]; then SKIP_NEXT=0; continue; fi
  ARG="${!i}"
  if [ "$ARG" == "--model" ]; then
    next_i=$((i+1)); MODEL="${!next_i}"; SKIP_NEXT=1
  else
    ARGS+=("$ARG")
  fi
done

ALIAS="sonnet"; EFFORT="medium"
if [[ "$MODEL" =~ ^cc-(opus|sonnet)-(low|medium|high)$ ]]; then
  ALIAS="${BASH_REMATCH[1]}"; EFFORT="${BASH_REMATCH[2]}"
elif [ -n "$MODEL" ]; then
  ALIAS="$MODEL"
fi

CLAUDE_BIN="$(command -v claude || echo "$HOME/.local/bin/claude")"
exec "$CLAUDE_BIN" "${ARGS[@]}" --model "$ALIAS" --effort "$EFFORT"
