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

