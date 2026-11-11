@echo off
setlocal
set "TASK=%~1"
set "TEMPLATE=%~2"
if "%TASK%"=="" set "TASK=Kiem tra thu muc hien tai"

:: Chuyển đổi đường dẫn thư mục hiện tại của Windows sang đường dẫn WSL (/mnt/c/... hoặc /mnt/d/...)
for /f "usebackq delims=" %%i in (`wsl wslpath -a -u "%CD:\=/%"`) do set "WSL_CWD=%%i"

echo [Ensemble] Working Directory: %WSL_CWD%
echo [Ensemble] Task: %TASK%
if not "%TEMPLATE%"=="" echo [Ensemble] Template: %TEMPLATE%
echo.

:: 1. Khởi chạy nhóm agent trong WSL
wsl -d Ubuntu -u truong bash /mnt/d/Ensemble/run.sh "%TASK%" "%WSL_CWD%" "%TEMPLATE%"

:: 2. Tự động mở Web Dashboard (Group Chat UI)
echo.
echo [Ensemble] ==============================================================
echo [Ensemble] Dang mo Web Group Chat tai: http://localhost:23000
echo [Ensemble] (Khong mo cua so WSL, theo doi va tuong tac 100%% tren Web)
echo [Ensemble] ==============================================================
start http://localhost:23000

:: Neu muon xem them qua man hinh terminal WSL, co the go: wsl tmux attach
