#!/usr/bin/env bash
# ==============================================================================
# Ensemble Collab - Universal Installer for macOS and Linux
# Reads install.config.json -> Checks Git, Node, Tmux -> Auto-configures ENV & CLI
# ==============================================================================
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

header() {
  echo -e "\n${CYAN}========================================================================${NC}"
  echo -e "  $1"
  echo -e "${CYAN}========================================================================${NC}"
}
success() { echo -e "${GREEN}[✓] $1${NC}"; }
warn() { echo -e "${YELLOW}[!] $1${NC}"; }
info() { echo -e "${CYAN}[i] $1${NC}"; }
err() { echo -e "${RED}[✗] $1${NC}"; exit 1; }

header "ENSEMBLE COLLAB - TRÌNH CÀI ĐẶT TỰ ĐỘNG (MACOS & LINUX)"

# ------------------------------------------------------------------------------
# 1. Nạp file cấu hình install.config.json
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/install.config.json"
[ ! -f "$CONFIG_FILE" ] && CONFIG_FILE="$SCRIPT_DIR/_original/install.config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  err "Không tìm thấy file install.config.json!"
fi

info "Đang đọc cấu hình từ: $CONFIG_FILE"

# Sử dụng node để phân tích JSON cấu hình chính xác
read -r REPO_URL BRANCH PORT URL < <(node -e "
  const c = require('$CONFIG_FILE');
  console.log(c.project.repository, c.project.branch, c.server.port, c.server.url);
" 2>/dev/null || echo "https://github.com/truongnguyen200183/Ensemble.git main 23000 http://localhost:23000")

success "Repository: $REPO_URL (Branch: $BRANCH)"
success "Server Port: $PORT ($URL)"

# ------------------------------------------------------------------------------
# 2. Kiểm tra Hệ điều hành & Package Manager
# ------------------------------------------------------------------------------
header "Bước 1/5: Kiểm tra môi trường hệ điều hành"

OS_TYPE="$(uname -s)"
if [ "$OS_TYPE" = "Darwin" ]; then
  success "Phát hiện hệ điều hành: macOS"
  if ! command -v brew >/dev/null 2>&1; then
    warn "Chưa tìm thấy Homebrew (brew). Khuyến nghị cài đặt Homebrew: https://brew.sh"
    echo "Đang thử cài Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
  fi
  info "Đang kiểm tra và cài đặt công cụ (git, node, tmux, jq, curl)..."
  brew install git node tmux jq curl 2>/dev/null || true

elif [ "$OS_TYPE" = "Linux" ]; then
  success "Phát hiện hệ điều hành: Linux"
  info "Đang kiểm tra và cài đặt công cụ cần thiết..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq git curl tmux jq nodejs npm
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y git curl tmux jq nodejs npm
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm git curl tmux jq nodejs npm
  fi
else
  err "Hệ điều hành $OS_TYPE chưa được hỗ trợ tự động."
fi

# Kiểm tra Node.js version
NODE_VER="$(node -v 2>/dev/null || echo 'none')"
success "Node.js Version: $NODE_VER"

# Kiểm tra Google Antigravity CLI (agy)
if command -v agy >/dev/null 2>&1 || command -v antigravity >/dev/null 2>&1; then
  success "Tìm thấy Google Antigravity CLI (agy)."
else
  warn "Chưa tìm thấy lệnh 'agy' trên máy."
  info "(Nếu dùng Antigravity, bạn có thể cài hoặc link vào /usr/local/bin/agy sau)."
fi

# ------------------------------------------------------------------------------
# 3. Đồng bộ mã nguồn và cài đặt dependencies
# ------------------------------------------------------------------------------
header "Bước 2/5: Đồng bộ mã nguồn Ensemble & cài đặt thư viện"

TARGET_DIR="$HOME/Ensemble"
[ "$OS_TYPE" = "Linux" ] && TARGET_DIR="$HOME/ensemble"

if [ ! -d "$TARGET_DIR/.git" ]; then
  info "Đang clone repository vào: $TARGET_DIR ..."
  git clone -b "$BRANCH" "$REPO_URL" "$TARGET_DIR"
else
  info "Đang cập nhật mã nguồn mới nhất tại $TARGET_DIR ..."
  cd "$TARGET_DIR"
  git fetch origin "$BRANCH"
  git reset --hard origin/"$BRANCH" || true
fi

cd "$TARGET_DIR/_original"
info "Đang cài đặt các gói NPM..."
npm install --prefer-offline --no-audit

# Cấp quyền thực thi
chmod +x "$TARGET_DIR/bin/collab" "$TARGET_DIR/run.sh" 2>/dev/null || true
find "$TARGET_DIR/_original/scripts" -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true

success "Mã nguồn và NPM dependencies đã được cài đặt thành công."

# ------------------------------------------------------------------------------
# 4. Thiết lập Biến môi trường (ENV)
# ------------------------------------------------------------------------------
header "Bước 3/5: Cấu hình Biến môi trường (ENV)"

RC_FILES=()
[ -f "$HOME/.bashrc" ] && RC_FILES+=("$HOME/.bashrc")
[ -f "$HOME/.zshrc" ] && RC_FILES+=("$HOME/.zshrc")
[ ${#RC_FILES[@]} -eq 0 ] && RC_FILES+=("$HOME/.profile")

for rc in "${RC_FILES[@]}"; do
  if ! grep -q "ENSEMBLE_PORT=" "$rc" 2>/dev/null; then
    cat << EOF >> "$rc"

# Ensemble Collab Environment
export ENSEMBLE_PORT=$PORT
export ENSEMBLE_URL="$URL"
export COLLAB_MONITOR="none"
export PATH="$TARGET_DIR/bin:\$PATH"
EOF
    success "Đã cập nhật cấu hình ENV vào: $rc"
  else
    success "Biến môi trường đã tồn tại trong: $rc"
  fi
done

# ------------------------------------------------------------------------------
# 5. Cài đặt lệnh 'collab' toàn cục
# ------------------------------------------------------------------------------
header "Bước 4/5: Đăng ký lệnh 'collab' toàn cục"

GLOBAL_BIN="/usr/local/bin/collab"
LOCAL_BIN="$HOME/.local/bin/collab"

INSTALLED_CLI=0
if [ -w "/usr/local/bin" ]; then
  ln -sf "$TARGET_DIR/bin/collab" "$GLOBAL_BIN"
  chmod +x "$GLOBAL_BIN"
  success "Đã tạo liên kết toàn cục tại: $GLOBAL_BIN"
  INSTALLED_CLI=1
elif sudo ln -sf "$TARGET_DIR/bin/collab" "$GLOBAL_BIN" 2>/dev/null; then
  sudo chmod +x "$GLOBAL_BIN"
  success "Đã tạo liên kết toàn cục tại: $GLOBAL_BIN (sudo)"
  INSTALLED_CLI=1
else
  mkdir -p "$HOME/.local/bin"
  ln -sf "$TARGET_DIR/bin/collab" "$LOCAL_BIN"
  chmod +x "$LOCAL_BIN"
  success "Đã tạo liên kết tại: $LOCAL_BIN"
  INSTALLED_CLI=1
fi

# ------------------------------------------------------------------------------
# 6. Cấu hình dịch vụ nền (Launchd trên macOS hoặc Systemd trên Linux)
# ------------------------------------------------------------------------------
header "Bước 5/5: Cấu hình dịch vụ nền Ensemble Server"

if [ "$OS_TYPE" = "Darwin" ]; then
  PLIST_DIR="$HOME/Library/LaunchAgents"
  mkdir -p "$PLIST_DIR"
  PLIST_FILE="$PLIST_DIR/com.ensemble.server.plist"

  cat << EOF > "$PLIST_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ensemble.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(command -v node)</string>
        <string>--import</string>
        <string>tsx</string>
        <string>$TARGET_DIR/_original/server.ts</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$TARGET_DIR/_original</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.ensemble/server.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.ensemble/server.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>NODE_ENV</key>
        <string>production</string>
        <key>ENSEMBLE_PORT</key>
        <string>$PORT</string>
        <key>ENSEMBLE_URL</key>
        <string>$URL</string>
    </dict>
</dict>
</plist>
EOF
  mkdir -p "$HOME/.ensemble"
  launchctl unload "$PLIST_FILE" 2>/dev/null || true
  launchctl load "$PLIST_FILE" 2>/dev/null || true
  success "Đã cấu hình và kích hoạt macOS LaunchAgent: $PLIST_FILE"

elif [ "$OS_TYPE" = "Linux" ]; then
  if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
    sudo tee /etc/systemd/system/ensemble.service > /dev/null << SVCEOF
[Unit]
Description=Ensemble Collab Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$TARGET_DIR/_original
ExecStart=$(command -v npm) start
Restart=always
RestartSec=3
Environment=NODE_ENV=production
Environment=ENSEMBLE_PORT=$PORT
Environment=ENSEMBLE_URL=$URL

[Install]
WantedBy=multi-user.target
SVCEOF
    sudo systemctl daemon-reload
    sudo systemctl enable --now ensemble
    success "Đã cấu hình và khởi chạy service ensemble.service qua systemd"
  else
    cd "$TARGET_DIR/_original" && nohup npm start > "$HOME/.ensemble/server.log" 2>&1 &
    success "Đã khởi chạy Ensemble Server ngầm qua background process"
  fi
fi

# ------------------------------------------------------------------------------
# Hoàn tất
# ------------------------------------------------------------------------------
header "CÀI ĐẶT HOÀN TẤT!"

echo -e "${GREEN}Hệ thống Ensemble Collab đã được cài đặt và cấu hình thành công!${NC}"
echo ""
echo -e "${CYAN}CÁC LỆNH SỬ DỤNG TRÊN TERMINAL:${NC}"
echo "  collab \"Nhiệm vụ của bạn\"   -> Khởi chạy nhóm 2 Agent tại thư mục hiện tại & mở Web"
echo "  collab status               -> Xem trạng thái Server & Agent đang hoạt động"
echo "  collab reactivate           -> Kích hoạt lại phiên làm việc cũ gần nhất"
echo "  collab web                  -> Mở nhanh giao diện Web Dashboard ($URL)"
echo "  collab help                 -> Xem chi tiết hướng dẫn"
echo ""

if [ "$OS_TYPE" = "Darwin" ]; then
  open "$URL" 2>/dev/null || true
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$URL" 2>/dev/null || true
fi

echo -e "${YELLOW}>> Lưu ý: Mở terminal mới để biến môi trường và lệnh 'collab' có hiệu lực.${NC}"
