# ==============================================================================
# Collab CLI - Windows Entrypoint
# Seamless integration between Windows Terminal and WSL Ensemble Agents
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$arg1 = $args[0]
$arg2 = $args[1]
$arg3 = $args[2]

$port = if ($env:ENSEMBLE_PORT) { $env:ENSEMBLE_PORT } else { "23000" }
$url = if ($env:ENSEMBLE_URL) { $env:ENSEMBLE_URL } else { "http://localhost:$port" }

# 0. Protocol handler (collab://start, collab://open)
if ($arg1 -eq "protocol" -or $arg1 -like "collab://*") {
    $uri = if ($arg1 -like "collab://*") { $arg1 } else { $arg2 }
    # Silently wake up WSL and start the ensemble systemd service or background daemon
    wsl -u root -e systemctl start ensemble 2>$null
    if ($LASTEXITCODE -ne 0) {
        wsl -e bash -c "cd ~/ensemble/_original && nohup npm start > ~/.ensemble/server.log 2>&1 &"
    }
    exit 0
}

function Convert-ToWslPath {
    param([string]$WinPath)
    try {
        $p = (& wsl wslpath -a -u ($WinPath -replace '\\', '/')).Trim()
        if ($p) { return $p }
    } catch {}
    
    # Fallback thủ công nếu wslpath lỗi
    if ($WinPath -match '^([a-zA-Z]):\\(.*)$') {
        $drive = $matches[1].ToLower()
        $rest = $matches[2] -replace '\\', '/'
        return "/mnt/$drive/$rest"
    }
    return "/home"
}

# 1. Lệnh xem trạng thái: collab status
if ($arg1 -eq "status") {
    Write-Host ">> Đang kiểm tra trạng thái Ensemble Server ($url)..." -ForegroundColor Cyan
    try {
        $statusJson = Invoke-RestMethod -Uri "$url/api/v1/health" -TimeoutSec 3 -ErrorAction Stop
        Write-Host "[✓] Server đang hoạt động!" -ForegroundColor Green
        Write-Host "    - Trạng thái: $($statusJson.status)"
        Write-Host "    - Phiên bản : $($statusJson.version)"
        Write-Host "    - Uptime    : $($statusJson.uptimeSeconds) giây"
        
        $teamsResp = Invoke-RestMethod -Uri "$url/api/ensemble/teams" -TimeoutSec 3 -ErrorAction SilentlyContinue
        $teamList = if ($teamsResp.teams) { $teamsResp.teams } else { $teamsResp }
        if ($teamList -and $teamList.Count -gt 0) {
            Write-Host "`nDANH SÁCH PHIÊN (TEAMS):" -ForegroundColor Yellow
            foreach ($t in $teamList) {
                Write-Host "  • [$($t.id.Substring(0, 8))] $($t.description) - $($t.status)" -ForegroundColor White
            }
        }
    } catch {
        Write-Host "[✗] Server chưa chạy hoặc không phản hồi tại $url" -ForegroundColor Red
        Write-Host "    Chạy lệnh: collab start  để khởi động server." -ForegroundColor Yellow
    }
    exit 0
}

# 2. Lệnh mở Web: collab web
if ($arg1 -eq "web") {
    Write-Host ">> Đang mở Web Dashboard: $url" -ForegroundColor Green
    Start-Process "$url"
    exit 0
}

# 3. Lệnh kích hoạt lại: collab reactivate [team-id]
if ($arg1 -eq "reactivate") {
    Write-Host ">> Đang tìm phiên gần nhất để kích hoạt lại..." -ForegroundColor Cyan
    try {
        $teamsResp = Invoke-RestMethod -Uri "$url/api/ensemble/teams" -TimeoutSec 3
        $teams = if ($teamsResp.teams) { $teamsResp.teams } else { $teamsResp }
        if (-not $teams -or $teams.Count -eq 0) {
            Write-Host "[!] Không tìm thấy phiên nào để kích hoạt." -ForegroundColor Yellow
            exit 0
        }
        $targetTeam = if ($arg2) { $arg2 } else { $teams[0].id }
        $res = Invoke-RestMethod -Uri "$url/api/ensemble/teams/$targetTeam/reactivate" -Method Post -TimeoutSec 5
        Write-Host "[✓] Đã kích hoạt lại thành công phiên: $targetTeam" -ForegroundColor Green
        Start-Process "$url"
    } catch {
        Write-Host "[✗] Lỗi khi kích hoạt lại phiên: $_" -ForegroundColor Red
    }
    exit 0
}

# 4. Lệnh khởi động server: collab start
if ($arg1 -eq "start") {
    Write-Host ">> Đang khởi động Ensemble Server trong WSL..." -ForegroundColor Cyan
    wsl -u root -e systemctl start ensemble 2>$null
    if ($LASTEXITCODE -ne 0) {
        wsl -e bash -c "cd ~/ensemble/_original && nohup npm start > ~/.ensemble/server.log 2>&1 &"
    }
    Start-Sleep -Seconds 2
    Start-Process "$url"
    exit 0
}

# 5. Lệnh dừng: collab stop
if ($arg1 -eq "stop") {
    Write-Host ">> Đang dừng Ensemble Server trong WSL..." -ForegroundColor Yellow
    wsl bash -c "sudo systemctl stop ensemble 2>/dev/null || pkill -f 'server.ts' 2>/dev/null || true"
    Write-Host "[✓] Đã gửi lệnh dừng." -ForegroundColor Green
    exit 0
}

# 6. Lệnh trợ giúp: collab help
if ($arg1 -eq "help" -or $arg1 -eq "-h" -or $arg1 -eq "--help") {
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "                     ENSEMBLE COLLAB CLI GUIDE                          " -ForegroundColor White
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "Cú pháp:" -ForegroundColor Yellow
    Write-Host "  collab `"Nội dung nhiệm vụ`" [template]   Khởi chạy nhóm 2 Agent tại thư mục hiện tại"
    Write-Host "  collab status                            Kiểm tra sức khỏe Server & các phiên đang chạy"
    Write-Host "  collab reactivate [team-id]              Kích hoạt lại phiên làm việc cũ"
    Write-Host "  collab web                               Mở giao diện Web Dashboard ($url)"
    Write-Host "  collab start                             Khởi động Ensemble Server ngầm"
    Write-Host "  collab stop                              Dừng Ensemble Server"
    Write-Host ""
    Write-Host "Ví dụ:" -ForegroundColor Yellow
    Write-Host "  collab `"Phân tích bảo mật backend NestJS`""
    Write-Host "  collab `"Kiểm thử API login`" implement"
    Write-Host "  collab `"Phản biện giải pháp caching`" review"
    exit 0
}

# 7. Khởi chạy nhiệm vụ Agent (Mặc định)
$currentWinDir = (Get-Location).Path
$wslDir = Convert-ToWslPath $currentWinDir

$task = if ($arg1) { $arg1 } else { "Kiểm tra và hỗ trợ dự án tại thư mục hiện tại" }
$template = if ($arg2) { $arg2 } else { "" }

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  [Ensemble Collab] Khởi chạy nhóm Agent phối hợp tự động" -ForegroundColor White
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  • Thư mục làm việc : $currentWinDir" -ForegroundColor White
Write-Host "  • Đường dẫn WSL    : $wslDir" -ForegroundColor White
Write-Host "  • Nhiệm vụ         : $task" -ForegroundColor Yellow
if ($template) {
    Write-Host "  • Template         : $template" -ForegroundColor Magenta
}
Write-Host ""

# Đảm bảo server đang chạy trước khi launch
try {
    $null = Invoke-RestMethod -Uri "$url/api/ensemble/status" -TimeoutSec 1 -ErrorAction SilentlyContinue
} catch {
    Write-Host ">> Server chưa chạy, đang tự động kích hoạt..." -ForegroundColor Cyan
    wsl bash -c "sudo systemctl start ensemble 2>/dev/null || (cd ~/ensemble/_original && nohup npm start > ~/.ensemble/server.log 2>&1 &)"
    Start-Sleep -Seconds 2
}

# Chạy run.sh trong WSL
$launchCmd = "bash -c 'if [ -f ~/ensemble/run.sh ]; then bash ~/ensemble/run.sh `"$task`" `"$wslDir`" `"$template`"; elif [ -f /mnt/d/Ensemble/run.sh ]; then bash /mnt/d/Ensemble/run.sh `"$task`" `"$wslDir`" `"$template`"; fi'"
wsl $launchCmd

Write-Host ""
Write-Host ">> Đang mở Web Group Chat: $url" -ForegroundColor Green
Start-Process "$url"
