#!/usr/bin/env bash
TASK="${1:-Kiem tra phoi hop giua 2 agent}"
DIR="${2:-$HOME/test-collab}"
MODE="${3:-}"

# Tat monitor feed log rieng de tmux attach luon vao thang man hinh chia doi 2 agent
export COLLAB_MONITOR="none"

mkdir -p "$DIR"
cd "$DIR"

AGENTS="agy,agy-worker"
TEMPLATE=""

case "$MODE" in
  review|review-pro)
    AGENTS="agy,agy-pro"
    TEMPLATE="review"
    echo ">> [Review Ngang Hang]: Reviewer (Argon) vs Critic (Argon)"
    ;;
  review-fast|review-flash)
    AGENTS="agy,agy-worker"
    TEMPLATE="review"
    echo ">> [Review Nhanh]: Reviewer (Argon) vs Critic (Flash)"
    ;;
  implement)
    AGENTS="agy,agy-worker"
    TEMPLATE="implement"
    ;;
  debug)
    AGENTS="agy,agy-worker"
    TEMPLATE="debug"
    ;;
  *)
    AGENTS="agy,agy-worker"
    TEMPLATE="$MODE"
    ;;
esac

"$HOME/ensemble/scripts/collab-launch.sh" "$DIR" "$TASK" "$AGENTS" "$TEMPLATE"

echo ""
echo "========================================================================"
echo "  [Ensemble] 2 Agent dang hoat dong tren man hinh chia doi!"
echo "  >> Mo cua so Ubuntu va go lenh sau de xem: tmux attach"
echo "========================================================================"
