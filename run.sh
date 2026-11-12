#!/usr/bin/env bash
# ==============================================================================
# Ensemble Collab - Universal Agent Runner (WSL / Linux / macOS)
# ==============================================================================
TASK="${1:-Kiem tra phoi hop giua 2 agent}"
DIR="${2:-$HOME/test-collab}"
MODE="${3:-}"

# Tắt monitor riêng, ưu tiên 100% Web Dashboard
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
  review-claude)
    AGENTS="agy,claude"
    TEMPLATE="review"
    echo ">> [Review Claude]: Lead (Argon) vs Critic (Claude Sonnet)"
    ;;
  review-opus)
    AGENTS="agy,claude-opus"
    TEMPLATE="review"
    echo ">> [Review Opus]: Lead (Argon) vs Critic (Claude Opus)"
    ;;
  claude-worker)
    AGENTS="agy,claude"
    TEMPLATE="implement"
    echo ">> [Claude Worker]: Lead (Argon) + Worker (Claude Sonnet)"
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

# Tự động định vị script collab-launch.sh
LAUNCHER=""
if [ -f "$HOME/ensemble/scripts/collab-launch.sh" ]; then
  LAUNCHER="$HOME/ensemble/scripts/collab-launch.sh"
elif [ -f "$HOME/ensemble/_original/scripts/collab-launch.sh" ]; then
  LAUNCHER="$HOME/ensemble/_original/scripts/collab-launch.sh"
elif [ -f "$HOME/Ensemble/_original/scripts/collab-launch.sh" ]; then
  LAUNCHER="$HOME/Ensemble/_original/scripts/collab-launch.sh"
elif [ -f "/mnt/d/Ensemble/_original/scripts/collab-launch.sh" ]; then
  LAUNCHER="/mnt/d/Ensemble/_original/scripts/collab-launch.sh"
fi

if [ -z "$LAUNCHER" ]; then
  echo "[!] Không tìm thấy collab-launch.sh! Vui lòng chạy lại install.sh hoặc install.bat"
  exit 1
fi

"$LAUNCHER" "$DIR" "$TASK" "$AGENTS" "$TEMPLATE"

echo ""
echo "========================================================================"
echo "  [Ensemble] 2 Agent đang phối hợp tự động!"
echo "  >> Truy cập Web Dashboard để theo dõi & chat: http://localhost:23000"
echo "  >> Hoặc gõ lệnh sau trong Terminal để xem tmux: tmux attach"
echo "========================================================================"
