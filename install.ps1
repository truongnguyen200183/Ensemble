# ==============================================================================
# Ensemble Collab - Automated Universal Installer for Windows
# Reads install.config.json -> Checks Git, Node, WSL -> Auto-configures ENV & CLI
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor White
    Write-Host "========================================================================" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Text)
    Write-Host "[OK] $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "[!] $Text" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Text)
    Write-Host "[i] $Text" -ForegroundColor Cyan
}

function Write-Err {
    param([string]$Text)
    Write-Host "[X] $Text" -ForegroundColor Red
}

Write-Header "ENSEMBLE COLLAB - TRÌNH CÀI ĐẶT TỰ ĐỘNG (WINDOWS & WSL)"

# ------------------------------------------------------------------------------
# 1. Nạp file cấu hình install.config.json
# ------------------------------------------------------------------------------
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

$configFile = Join-Path $scriptDir "install.config.json"
if (-not (Test-Path $configFile)) {
    $configFile = Join-Path $scriptDir "_original\install.config.json"
}

if (-not (Test-Path $configFile)) {
    Write-Err "Không tìm thấy file install.config.json!"
    exit 1
}

Write-Info "Đang đọc cấu hình từ: $configFile"
$config = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json

$repoUrl = $config.project.repository
$branch = $config.project.branch
$port = $config.server.port
$domain = if ($config.server.domain) { $config.server.domain.Trim() } else { "" }
$ensembleUrl = if ($domain) {
    if ($domain.StartsWith("http://") -or $domain.StartsWith("https://")) { $domain } else { "https://$domain" }
} else { $config.server.url }
$corsOrigin = if ($config.server.cors_origins) { $config.server.cors_origins } else { "$ensembleUrl,http://localhost:$port" }
$wslDistro = $config.platforms.windows.recommended_distro
$wslTargetDir = $config.platforms.windows.wsl_target_dir

Write-Success "Dự án: $($config.project.name) v$($config.project.version)"
Write-Success "Repository: $repoUrl (Branch: $branch)"
if ($domain) {
    Write-Success "Tên miền (Domain): $domain ($ensembleUrl)"
} else {
    Write-Success "Server Port: $port ($ensembleUrl)"
}

# ------------------------------------------------------------------------------
# 2. Kiểm tra các công cụ trên Windows (Git, Node.js)
# ------------------------------------------------------------------------------
Write-Header "Bước 1/6: Kiểm tra môi trường Windows Host"

# Kiểm tra Git
try {
    $gitVer = & git --version 2>$null
    Write-Success "Windows Git: $gitVer"
} catch {
    Write-Warn "Chưa tìm thấy Git trên Windows."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Info "Đang tự động cài Git qua winget..."
        & winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements
    } else {
        Write-Err "Vui lòng cài đặt Git từ: https://git-scm.com/download/win"
    }
}

# Kiểm tra Node.js trên Windows
try {
    $nodeVer = & node -v 2>$null
    Write-Success "Windows Node.js: $nodeVer"
} catch {
    Write-Warn "Chưa tìm thấy Node.js trên Windows."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Info "Đang tự động cài Node.js LTS qua winget..."
        & winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-source-agreements --accept-package-agreements
    }
}

# ------------------------------------------------------------------------------
# 3. Kiểm tra và thiết lập WSL (Windows Subsystem for Linux)
# ------------------------------------------------------------------------------
Write-Header "Bước 2/6: Kiểm tra và thiết lập WSL (Bắt buộc cho Agents & Tmux)"

$wslInstalled = $false
try {
    $wslCheck = & wsl --status 2>$null
    if ($LASTEXITCODE -eq 0 -or $wslCheck) {
        $wslInstalled = $true
    }
} catch {}

if (-not $wslInstalled) {
    # Thử kiểm tra wsl -l
    try {
        $distros = & wsl -l -q 2>$null
        if ($distros) { $wslInstalled = $true }
    } catch {}
}

if (-not $wslInstalled) {
    Write-Err "WSL chưa được kích hoạt hoặc chưa cài đặt Distro!"
    Write-Info "Ensemble sử dụng WSL để chạy các Agent trong môi trường Linux cô lập và Tmux."
    Write-Host "Bạn có muốn cài đặt WSL Ubuntu tự động ngay bây giờ? (Y/N): " -NoNewline -ForegroundColor Yellow
    $ans = Read-Host
    if ($ans -eq "Y" -or $ans -eq "y" -or $ans -eq "") {
        Write-Info "Đang chạy: wsl --install -d Ubuntu..."
        & wsl --install -d Ubuntu --no-launch
        Write-Warn "Sau khi cài WSL, bạn cần khởi động lại máy tính (Restart) rồi chạy lại install.bat!"
        exit 0
    } else {
        Write-Err "Hủy cài đặt vì thiếu WSL."
        exit 1
    }
}

Write-Success "WSL đã sẵn sàng."

# Cấu hình .wslconfig tối ưu RAM, mạng mirrored và duy trì server ngầm liên tục
$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
$wslConfigContent = @"
[wsl2]
memory=10GB
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
vmIdleTimeout=-1

[experimental]
autoMemoryReclaim=gradual
"@
try {
    [System.IO.File]::WriteAllText($wslConfigPath, $wslConfigContent, [System.Text.Encoding]::ASCII)
    Write-Success "Đã tối ưu .wslconfig (memory=10GB, networkingMode=mirrored, autoMemoryReclaim=gradual, vmIdleTimeout=-1)."
} catch {
    Write-Warn "Không thể ghi tệp .wslconfig: $_"
}

# Tự động loại trừ D:\Projects khỏi Windows Defender để tăng tốc I/O cho Agent
if (Test-Path "D:\Projects") {
    try {
        Write-Info "Đang cấu hình Windows Defender loại trừ D:\Projects để tăng tốc I/O..."
        Add-MpPreference -ExclusionPath "D:\Projects" -ErrorAction SilentlyContinue
        Write-Success "Đã thêm D:\Projects vào danh sách loại trừ của Windows Defender."
    } catch {
        Write-Warn "Chưa thể tự động thêm Windows Defender Exclusion (cần quyền Administrator, có thể cấu hình sau)."
    }
}

# Tìm distro phù hợp
$wslDistroFound = ""
$rawDistros = & wsl -l -q 2>$null
foreach ($d in $rawDistros) {
    $cleanD = $d.Trim().Replace("`0", "")
    if ($cleanD -like "*Ubuntu*" -or $cleanD -eq "Ubuntu") {
        $wslDistroFound = $cleanD
        break
    }
}
if (-not $wslDistroFound -and $rawDistros.Count -gt 0) {
    $wslDistroFound = $rawDistros[0].Trim().Replace("`0", "")
}
if (-not $wslDistroFound) { $wslDistroFound = "Ubuntu" }

Write-Success "Sử dụng WSL Distro: $wslDistroFound"

# Cấu hình /etc/wsl.conf trong WSL: kích hoạt systemd và tối ưu mount phân quyền metadata
Write-Info "Đang cấu hình /etc/wsl.conf (kích hoạt systemd=true & automount metadata)..."
$wslConfContent = @"
[boot]
systemd=true

[automount]
enabled = true
options = "metadata,umask=22,fmask=11"
"@
try {
    $wslConfContent | & wsl -d $wslDistroFound -u root tee /etc/wsl.conf | Out-Null
    Write-Success "Đã cấu hình /etc/wsl.conf thành công: [boot] systemd=true & [automount] metadata."
} catch {
    Write-Warn "Không thể ghi /etc/wsl.conf qua wsl root: $_"
}

# Kiểm tra kết nối vào WSL
$wslUser = (& wsl -d $wslDistroFound -e whoami).Trim()
Write-Success "WSL User: $wslUser"

# ------------------------------------------------------------------------------
# 4. Cài đặt các gói phụ thuộc bên trong WSL
# ------------------------------------------------------------------------------
Write-Header "Bước 3/6: Cài đặt gói công cụ trong WSL (curl, git, tmux, jq, nodejs, tsx)"

$pkgList = ($config.platforms.windows.required_wsl_packages -join " ")
Write-Info "Đang kiểm tra và cài đặt: $pkgList..."

$installScript = @"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq git curl tmux jq

# Kiểm tra nodejs trong WSL, nếu chưa có hoặc < v18 thì cài từ NodeSource
if ! command -v node >/dev/null 2>&1 || [ "\$(node -v | cut -d'v' -f2 | cut -d'.' -f1)" -lt 18 ]; then
    echo ">> Đang cài Node.js LTS vào WSL..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y -qq nodejs
fi

# Cài đặt tsx toàn cục để chạy server.ts trực tiếp
if ! command -v tsx >/dev/null 2>&1; then
    echo ">> Đang cài tsx (TypeScript execution engine)..."
    sudo npm install -g tsx
fi
"@

& wsl -d $wslDistroFound -e bash -c "$installScript"
Write-Success "Các gói công cụ trong WSL đã được cập nhật đầy đủ."

# Kiểm tra Google Antigravity CLI (agy)
$hasAgy = (& wsl -d $wslDistroFound -e bash -c "command -v agy || command -v antigravity || true").Trim()
if ($hasAgy) {
    Write-Success "Tìm thấy Google Antigravity CLI tại: $hasAgy"
} else {
    Write-Warn "Chưa tìm thấy lệnh 'agy' trong WSL."
    Write-Info "(Nếu dùng Antigravity, bạn có thể cài hoặc link vào /usr/local/bin/agy sau)."
}

# ------------------------------------------------------------------------------
# 5. Clone / Cập nhật Repository vào WSL
# ------------------------------------------------------------------------------
Write-Header "Bước 4/6: Đồng bộ mã nguồn Ensemble vào WSL ($wslTargetDir)"

$syncScript = @"
TARGET_DIR="\$HOME/ensemble"
if [ ! -d "\$TARGET_DIR/.git" ]; then
    echo ">> Đang clone $repoUrl vào \$TARGET_DIR..."
    git clone -b $branch "$repoUrl" "\$TARGET_DIR"
else
    echo ">> Đang cập nhật mã nguồn mới nhất..."
    cd "\$TARGET_DIR"
    git fetch origin $branch
    git reset --hard origin/$branch || true
fi

cd "\$TARGET_DIR"
if [ -d "_original" ]; then
    cd _original
fi

echo ">> Đang cài đặt thư viện NPM trong WSL..."
npm install --prefer-offline --no-audit

# Cấp quyền thực thi cho các scripts và cài đặt wrapper vào PATH
find scripts -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
find ../scripts -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
chmod +x ../run.sh 2>/dev/null || true
[ -f scripts/agy-smart.sh ] && sudo cp scripts/agy-smart.sh /usr/local/bin/agy-smart && sudo chmod +x /usr/local/bin/agy-smart 2>/dev/null || true
[ -f scripts/claude-smart.sh ] && sudo cp scripts/claude-smart.sh /usr/local/bin/claude-smart && sudo chmod +x /usr/local/bin/claude-smart 2>/dev/null || true
"@

& wsl -d $wslDistroFound -e bash -c "$syncScript"
Write-Success "Mã nguồn và NPM dependencies trong WSL đã sẵn sàng."

# ------------------------------------------------------------------------------
# 4b. Tùy chọn cấu hình Mô hình Cục bộ Ollama (Aider CLI)
# ------------------------------------------------------------------------------
$ollamaConfig = $config.ollama
$defaultOllamaApi = if ($ollamaConfig -and $ollamaConfig.api_base) { $ollamaConfig.api_base } else { "http://192.168.86.23:11434" }
$defaultOllamaModel = if ($ollamaConfig -and $ollamaConfig.model) { $ollamaConfig.model } else { "gemma4:12b" }

$installOllama = $false
if ($ollamaConfig -and $ollamaConfig.enabled -eq $true) {
    $installOllama = $true
} elseif ($ollamaConfig -and $ollamaConfig.prompt_during_install -ne $false) {
    Write-Host ""
    Write-Host ">> Bạn có muốn cấu hình kết nối Mô hình cục bộ Ollama (Mạng nội bộ / Local) không? (y/N): " -NoNewline -ForegroundColor Yellow
    $ansOllama = Read-Host
    if ($ansOllama -eq "Y" -or $ansOllama -eq "y") {
        $installOllama = $true
    }
}

if ($installOllama) {
    Write-Host "   Nhập URL máy chủ Ollama [Mặc định: $defaultOllamaApi]: " -NoNewline -ForegroundColor Cyan
    $userApi = Read-Host
    if ($userApi -and $userApi.Trim()) { $defaultOllamaApi = $userApi.Trim() }

    Write-Host "   Nhập tên Model Ollama [Mặc định: $defaultOllamaModel]: " -NoNewline -ForegroundColor Cyan
    $userModel = Read-Host
    if ($userModel -and $userModel.Trim()) { $defaultOllamaModel = $userModel.Trim() }

    Write-Info "Đang kiểm tra kết nối tới máy chủ Ollama ($defaultOllamaApi)..."
    $checkConn = (& wsl -d $wslDistroFound -e bash -c "curl -s --connect-timeout 3 $defaultOllamaApi/api/tags 2>/dev/null || true").Trim()
    if ($checkConn) {
        Write-Success "Kết nối Ollama thành công!"
    } else {
        Write-Warn "Chưa kết nối được tới $defaultOllamaApi (máy chủ tắt hoặc máy tính này không cùng mạng LAN)."
        Write-Info "Hệ thống vẫn sẽ chuẩn bị sẵn Aider CLI để bạn có thể kết nối bất kỳ lúc nào."
    }

    Write-Info "Đang cài đặt / cập nhật Aider CLI cho Ollama trong WSL..."
    $ollamaSetup = @"
if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="\$HOME/.local/bin:\$PATH"
if ! command -v aider >/dev/null 2>&1; then
    uv tool install --python 3.12 aider-chat
fi
[ -f \$HOME/.local/bin/aider ] && sudo ln -sf \$HOME/.local/bin/aider /usr/local/bin/aider

cat << 'AIDEREOF' > /tmp/aider-smart.sh
#!/usr/bin/env bash
# Runner for Aider connected to local Ollama (gemma4:12b / qwen3-coder:30b)
# Hard context cap: 16384 tokens (num_ctx: 16384, max-chat-history-tokens: 12288)
export OLLAMA_API_BASE="${defaultOllamaApi}"
export OPENAI_API_BASE="${defaultOllamaApi}/v1"
export OPENAI_API_KEY="ollama"
MODEL="ollama/${defaultOllamaModel}"
ARGS=()
SKIP_NEXT=0
for ((i=1; i<=\$#; i++)); do
  if [ \$SKIP_NEXT -eq 1 ]; then SKIP_NEXT=0; continue; fi
  ARG="\${!i}"
  if [ "\$ARG" == "--model" ]; then
    next_i=\$((i+1))
    M="\${!next_i}"
    if [[ "\$M" == "ollama-gemma" || "\$M" == "gemma4:12b" ]]; then
      MODEL="ollama/gemma4:12b"
    elif [[ "\$M" == "ollama-qwen" || "\$M" == "qwen3-coder:30b" || "\$M" == "qwen3-coder" ]]; then
      MODEL="ollama/qwen3-coder:30b"
    elif [[ "\$M" != ollama/* && "\$M" != openai/* ]]; then
      MODEL="ollama/\$M"
    else
      MODEL="\$M"
    fi
    SKIP_NEXT=1
  elif [ "\$ARG" == "--effort" ]; then
    SKIP_NEXT=1
  elif [[ "\$ARG" == --effort=* ]]; then
    continue
  else
    ARGS+=("\$ARG")
  fi
done

EXTRA_FLAGS=()
for s in "\$(pwd)/.aider.model.settings.yml" "\$HOME/ensemble/.aider.model.settings.yml" "\$HOME/.aider.model.settings.yml"; do
  if [ -f "\$s" ]; then
    EXTRA_FLAGS+=("--model-settings-file" "\$s")
    break
  fi
done
for m in "\$(pwd)/.aider.model.metadata.json" "\$HOME/ensemble/.aider.model.metadata.json" "\$HOME/.aider.model.metadata.json"; do
  if [ -f "\$m" ]; then
    EXTRA_FLAGS+=("--model-metadata-file" "\$m")
    break
  fi
done

AIDER_BIN="\$(command -v aider || echo "\$HOME/.local/bin/aider")"
exec "\$AIDER_BIN" --model "\$MODEL" --max-chat-history-tokens 12288 --no-check-model-accepts-settings "\${EXTRA_FLAGS[@]}" --yes-always --no-auto-commits --no-analytics --dark-mode "\${ARGS[@]}"
AIDEREOF

sudo mv /tmp/aider-smart.sh /usr/local/bin/aider-smart
sudo chmod +x /usr/local/bin/aider-smart

# Cấu hình giới hạn Model Context Window 16384 (tránh tràn RAM GPU / RAM máy chủ)
cat << 'SETTINGSEOF' > /tmp/aider-settings.yml
- name: ollama/gemma4:12b
  edit_format: diff
  weak_model_name: ollama/gemma4:12b
  use_repo_map: true
  extra_params:
    num_ctx: 16384

- name: ollama/qwen3-coder:30b
  edit_format: diff
  weak_model_name: ollama/qwen3-coder:30b
  use_repo_map: true
  extra_params:
    num_ctx: 16384

- name: gemma4:12b
  edit_format: diff
  weak_model_name: gemma4:12b
  use_repo_map: true
  extra_params:
    num_ctx: 16384

- name: qwen3-coder:30b
  edit_format: diff
  weak_model_name: qwen3-coder:30b
  use_repo_map: true
  extra_params:
    num_ctx: 16384
SETTINGSEOF

cat << 'METAEof' > /tmp/aider-metadata.json
{
  "ollama/gemma4:12b": {
    "max_tokens": 4096,
    "max_input_tokens": 16384,
    "max_output_tokens": 4096,
    "input_cost_per_token": 0.0,
    "output_cost_per_token": 0.0,
    "litellm_provider": "ollama",
    "mode": "chat"
  },
  "ollama/qwen3-coder:30b": {
    "max_tokens": 4096,
    "max_input_tokens": 16384,
    "max_output_tokens": 4096,
    "input_cost_per_token": 0.0,
    "output_cost_per_token": 0.0,
    "litellm_provider": "ollama",
    "mode": "chat"
  },
  "gemma4:12b": {
    "max_tokens": 4096,
    "max_input_tokens": 16384,
    "max_output_tokens": 4096,
    "input_cost_per_token": 0.0,
    "output_cost_per_token": 0.0,
    "litellm_provider": "ollama",
    "mode": "chat"
  },
  "qwen3-coder:30b": {
    "max_tokens": 4096,
    "max_input_tokens": 16384,
    "max_output_tokens": 4096,
    "input_cost_per_token": 0.0,
    "output_cost_per_token": 0.0,
    "litellm_provider": "ollama",
    "mode": "chat"
  }
}
METAEof

cp -f /tmp/aider-settings.yml \$HOME/.aider.model.settings.yml
cp -f /tmp/aider-metadata.json \$HOME/.aider.model.metadata.json
[ -d \$HOME/ensemble ] && cp -f /tmp/aider-settings.yml \$HOME/ensemble/.aider.model.settings.yml
[ -d \$HOME/ensemble ] && cp -f /tmp/aider-metadata.json \$HOME/ensemble/.aider.model.metadata.json

python3 -c "
import json, os
for p in ['\$HOME/ensemble/agents.json', '\$HOME/ensemble/_original/agents.json']:
    if os.path.exists(p):
        try:
            with open(p, 'r') as f: d = json.load(f)
            d['ollama-gemma'] = {
                'name': 'ollama-gemma',
                'command': 'aider-smart',
                'flags': ['--model', 'ollama/gemma4:12b'],
                'readyMarker': '>',
                'inputMethod': 'sendKeys',
                'color': 'cyan',
                'icon': '🦙'
            }
            d['ollama-qwen'] = {
                'name': 'ollama-qwen',
                'command': 'aider-smart',
                'flags': ['--model', 'ollama/qwen3-coder:30b'],
                'readyMarker': '>',
                'inputMethod': 'sendKeys',
                'color': 'cyan',
                'icon': '🦙'
            }
            with open(p, 'w') as f: json.dump(d, f, indent=2)
        except: pass
"
"@
    & wsl -d $wslDistroFound -e bash -c "$ollamaSetup"
    Write-Success "Đã cài đặt Aider CLI và kích hoạt Ollama ($defaultOllamaModel)."
} else {
    Write-Info "Bỏ qua cài đặt Ollama (máy tính không dùng mô hình nội bộ)."
    # Gỡ bỏ entry nếu có để tránh gọi nhầm
    & wsl -d $wslDistroFound -e bash -c "python3 -c \"
import json, os
for p in ['\$HOME/ensemble/agents.json', '\$HOME/ensemble/_original/agents.json']:
    if os.path.exists(p):
        try:
            with open(p, 'r') as f: d = json.load(f)
            if 'ollama-gemma' in d:
                del d['ollama-gemma']
                with open(p, 'w') as f: json.dump(d, f, indent=2)
        except: pass
\""
}

# ------------------------------------------------------------------------------
# 6. Thiết lập Biến môi trường (ENV) & Service
# ------------------------------------------------------------------------------
Write-Header "Bước 5/6: Thiết lập Biến môi trường (ENV) & Dịch vụ nền"

# 1. Set Windows User Environment Variables
[Environment]::SetEnvironmentVariable("ENSEMBLE_PORT", "$port", "User")
[Environment]::SetEnvironmentVariable("ENSEMBLE_URL", "$ensembleUrl", "User")
[Environment]::SetEnvironmentVariable("ENSEMBLE_CORS_ORIGIN", "$corsOrigin", "User")
[Environment]::SetEnvironmentVariable("COLLAB_MONITOR", "$($config.environment.COLLAB_MONITOR)", "User")
$env:ENSEMBLE_PORT = "$port"
$env:ENSEMBLE_URL = "$ensembleUrl"
$env:ENSEMBLE_CORS_ORIGIN = "$corsOrigin"
$env:COLLAB_MONITOR = "$($config.environment.COLLAB_MONITOR)"
Write-Success "Đã lưu biến môi trường Windows (ENSEMBLE_PORT=$port, ENSEMBLE_URL=$ensembleUrl)."

# 2. Set WSL Environment Variables in ~/.bashrc
$envScript = @"
grep -q "ENSEMBLE_PORT=" ~/.bashrc 2>/dev/null || cat << 'EOF' >> ~/.bashrc

# Ensemble Collab Environment
export ENSEMBLE_PORT=$port
export ENSEMBLE_URL="$ensembleUrl"
export ENSEMBLE_CORS_ORIGIN="$corsOrigin"
export COLLAB_MONITOR="$($config.environment.COLLAB_MONITOR)"
export PATH="\$HOME/ensemble/bin:\$PATH"
EOF
"@
& wsl -d $wslDistroFound -e bash -c "$envScript"
Write-Success "Đã lưu biến môi trường WSL vào ~/.bashrc."

# 3. Kích hoạt dịch vụ ensemble trong WSL (systemd hoặc background daemon)
$serviceScript = @"
TSX_BIN="\$(which tsx 2>/dev/null || echo /usr/local/bin/tsx)"
if command -v systemctl >/dev/null 2>&1; then
    sudo tee /etc/systemd/system/ensemble.service > /dev/null << SVCEOF
[Unit]
Description=Ensemble Multi-Agent HTTP Server and Web Dashboard
After=network.target

[Service]
User=$wslUser
Group=$wslUser
Environment=HOME=/home/$wslUser
Environment=TMUX_TMPDIR=/tmp
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=PATH=/usr/local/bin:/usr/bin:/bin:/home/$wslUser/.local/bin
Type=simple
WorkingDirectory=/home/$wslUser/ensemble
ExecStart=\$TSX_BIN /home/$wslUser/ensemble/server.ts
Restart=always
RestartSec=2
Environment=PORT=$port
Environment=HOST=0.0.0.0
Environment=NODE_ENV=production
Environment=ENSEMBLE_PORT=$port
Environment=ENSEMBLE_URL=$ensembleUrl

[Install]
WantedBy=multi-user.target
SVCEOF
    sudo systemctl daemon-reload
    sudo systemctl enable --now ensemble 2>/dev/null || true
    echo ">> Service ensemble.service đã được kích hoạt qua systemd!"
else
    # Fallback chạy nền qua nohup nếu systemd chưa sẵn sàng
    if ! pgrep -f "server.ts" >/dev/null 2>&1; then
        cd \$HOME/ensemble && nohup \$TSX_BIN server.ts > \$HOME/.ensemble/server.log 2>&1 &
        echo ">> Ensemble server đã chạy ngầm trong background."
    fi
fi
"@
& wsl -d $wslDistroFound -e bash -c "$serviceScript"
Write-Success "Dịch vụ Ensemble Server đã được cấu hình chạy tự động."

# ------------------------------------------------------------------------------
# 7. Cài đặt lệnh 'collab' toàn cục vào Windows PATH
# ------------------------------------------------------------------------------
Write-Header "Bước 6/6: Đăng ký lệnh 'collab' toàn cục trên Windows"

$binDir = Join-Path $scriptDir "bin"
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}

# Tạo wrapper collab.cmd
$collabCmdPath = Join-Path $binDir "collab.cmd"
$collabCmdContent = @"
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0collab.ps1" %*
"@
[System.IO.File]::WriteAllText($collabCmdPath, $collabCmdContent, [System.Text.Encoding]::ASCII)

# Thêm thư mục bin vào User PATH
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$binDir*") {
    $newPath = "$userPath;$binDir"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    $env:PATH = "$env:PATH;$binDir"
    Write-Success "Đã thêm $binDir vào Windows PATH."
} else {
    Write-Success "$binDir đã tồn tại trong Windows PATH."
}

# Đăng ký Custom Protocol (collab://) trong Windows Registry (để Web có thể click mở/start WSL)
try {
    $regPath = "HKCU:\Software\Classes\collab"
    New-Item -Path $regPath -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "(Default)" -Value "URL:Collab Protocol"
    Set-ItemProperty -Path $regPath -Name "URL Protocol" -Value ""
    $cmdReg = Join-Path $regPath "shell\open\command"
    New-Item -Path $cmdReg -Force | Out-Null
    $collabPs1Path = Join-Path $binDir "collab.ps1"
    Set-ItemProperty -Path $cmdReg -Name "(Default)" -Value "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$collabPs1Path`" protocol `"%1`""
    Write-Success "Đã đăng ký giao thức 'collab://' (Cho phép web 1-click kích hoạt WSL/Server)."
} catch {
    Write-Warn "Không thể đăng ký giao thức 'collab://': $_"
}

# Đăng ký tự động khởi động cùng Windows (Startup Folder)
try {
    $startupFolder = [Environment]::GetFolderPath("Startup")
    if ($startupFolder -and (Test-Path $startupFolder)) {
        $startupCmd = Join-Path $startupFolder "EnsembleCollabStartup.cmd"
        $startupContent = "@echo off`r`nwsl -e systemctl start ensemble 2>nul`r`n"
        [System.IO.File]::WriteAllText($startupCmd, $startupContent, [System.Text.Encoding]::ASCII)
        Write-Success "Đã đăng ký tự khởi động WSL Ensemble Server cùng Windows."
    }
} catch {}

# ------------------------------------------------------------------------------
# 8. Hoàn tất & Mở Web Dashboard
# ------------------------------------------------------------------------------
Write-Header "CÀI ĐẶT THÀNH CÔNG!"

Write-Host "Hệ thống Ensemble Collab đã sẵn sàng hoạt động!" -ForegroundColor Green
Write-Host ""
Write-Host "CÁC LỆNH BẠN CÓ THỂ SỬ DỤNG NGAY BÂY GIỜ TỪ BẤT KỲ ĐÂU:" -ForegroundColor Cyan
Write-Host "  collab `"Nhiệm vụ của bạn`"   -> Khởi động nhóm 2 Agent tại thư mục hiện tại & mở Web" -ForegroundColor White
Write-Host "  collab status               -> Xem trạng thái Server & danh sách Agent đang chạy" -ForegroundColor White
Write-Host "  collab reactivate           -> Kích hoạt lại phiên làm việc cũ gần nhất" -ForegroundColor White
Write-Host "  collab web                  -> Mở nhanh giao diện Web Dashboard ($ensembleUrl)" -ForegroundColor White
Write-Host "  collab help                 -> Xem toàn bộ tài liệu hướng dẫn" -ForegroundColor White
Write-Host ""

# Thử mở trình duyệt nếu cấu hình yêu cầu
if ($config.server.auto_open_browser) {
    Write-Info "Đang mở Web Dashboard tại: $ensembleUrl ..."
    Start-Process "$ensembleUrl"
}

Write-Host "Nhấn phím bất kỳ để kết thúc..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

