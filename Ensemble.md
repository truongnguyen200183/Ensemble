# Hướng Dẫn Cài Đặt, Tối Ưu và Vận Hành Ensemble Multi-Agent (Dual Antigravity CLI)

Tài liệu này ghi chép lại **toàn bộ quy trình cài đặt thực tế chuẩn xác**, bao gồm các bản vá lỗi mã nguồn gốc của Ensemble khi chạy trên môi trường Linux/WSL2, thiết lập Web Group Chat UI hiện đại, cài đặt daemon service hệ thống và phương pháp tích hợp điều khiển trực tiếp từ Windows.

---

## 1. Tổng Quan Kiến Trúc

* **Hệ điều hành máy chủ (Host):** Windows 10/11.
* **Môi trường điều phối nền:** WSL2 (Ubuntu 22.04+ / 24.04+).
* **Động cơ điều phối:** [Ensemble](https://github.com/michelhelsdingen/ensemble.git) (Node.js 20+, TypeScript, systemd daemon).
* **Hệ thống tác tử (Dual Agent):**
  * **Lead (`agy`)**: Kiến trúc sư trưởng / Quản lý nhóm (`gemini-4-argon-low`).
  * **Worker (`agy-worker`)**: Lập trình viên thực thi (`gemini-3.8-flash-low` - tốc độ cao, tiết kiệm token).
  * **Critic / Reviewer (`agy-pro`)**: Chuyên gia phản biện cao cấp ngang hàng Lead (`gemini-4-argon-low`).
* **Giao diện theo dõi & Tương tác:**
  * **Web Dashboard (Mặc định)**: `http://localhost:23000` — Group Chat một khung duy nhất (Lead bên Trái, Worker bên Phải, tên hiển thị theo Role, hover xóa phiên).
  * **Terminal Split Monitor (Tùy chọn)**: `wsl tmux attach` — Màn hình chia đôi 50/50 nếu muốn xem terminal.

---

## 2. Chuẩn Bị Môi Trường trên Windows & WSL2

### Bước 1: Kích hoạt WSL2 Ubuntu
Mở **PowerShell (Admin)** và kiểm tra:
```powershell
wsl -l -v
# Nếu chưa có Ubuntu, cài đặt:
wsl --install -d Ubuntu
```

### Bước 2: Cài đặt công cụ hệ thống & Node.js 20+ trong Ubuntu
Vào terminal Ubuntu (`wsl -d Ubuntu`) và chạy:
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl tmux python3 python3-pip build-essential

# Cài đặt Node.js LTS/Current chính thức qua NodeSource:
curl -fsSL https://deb.nodesource.com/setup_current.x | sudo bash -
sudo apt install -y nodejs
node -v   # Yêu cầu v20 trở lên
npm -v
```

---

## 3. Cài Đặt và Xác Thực Antigravity CLI (`agy`)

> ⚠️ **Lưu ý quan trọng từ thực tế:** Gói `@antigravity/cli` **không có trên npm registry** (sẽ gặp lỗi `404 Not Found`). Antigravity CLI là một binary ELF 64-bit chính thức của Google, cần cài qua script chính hãng.

### Bước 1: Cài đặt binary Antigravity CLI trong WSL
```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash
```
Binary sẽ được lưu tại `~/.local/bin/agy`. Đưa ra thư mục dùng chung toàn hệ thống:
```bash
sudo cp ~/.local/bin/agy /usr/local/bin/agy
sudo chmod +x /usr/local/bin/agy
```

### Bước 2: Tạo các Shim Alias cho Worker
```bash
# Tạo agy-worker (Dùng cho Worker)
sudo ln -sf /usr/local/bin/agy /usr/local/bin/agy-worker
ln -sf ~/.local/bin/agy ~/.local/bin/agy-worker

# Tạo agy-pro (Dùng cho Chuyên gia phản biện)
sudo ln -sf /usr/local/bin/agy /usr/local/bin/agy-pro
ln -sf ~/.local/bin/agy ~/.local/bin/agy-pro
```

### Bước 3: Chia sẻ phiên xác thực Google (OAuth Session)
Chia sẻ phiên đăng nhập đã có từ Windows sang WSL để sử dụng gói thuê bao Google Gemini Pro/Advanced:
```bash
ln -sf /mnt/c/Users/<TenUserWindows>/.gemini ~/.gemini
```
* Sau đó gõ `agy` trong terminal Ubuntu (không gõ `agy login`).
* Màn hình sẽ yêu cầu xác nhận **Workspace Trust** (`> Yes, I trust this folder`) ➔ Nhấn **`Enter`**.
* Kiểm tra góc dưới hiển thị model (ví dụ `Gemini 4 Argon` hoặc `Gemini 3.8 Flash`) là đăng nhập thành công. Nhấn `Ctrl + D` để thoát.

---

## 4. Cài Đặt Ensemble & Các Bản Vá Lỗi (Patches)

### Bước 1: Clone mã nguồn và cài dependencies
```bash
cd ~
git clone https://github.com/michelhelsdingen/ensemble.git
cd ensemble
npm install
sudo ln -sf ~/ensemble/node_modules/.bin/tsx /usr/local/bin/tsx
```

---

### Bước 2: Vá lỗi `nocorrect: command not found`
* **Nguyên nhân:** Ensemble hardcode cú pháp zsh (`nocorrect unset CLAUDECODE; ...`), gây lỗi trên bash của Ubuntu.
* **Cách sửa:** Trong file `~/ensemble/lib/agent-spawner.ts`: xóa chữ `nocorrect` đi, chỉ giữ lại `unset CLAUDECODE; ...`.

---

### Bước 3: Vá tính năng tự động chia đôi màn hình 50/50
* **Nguyên nhân:** Mặc định Ensemble tạo 2 phiên tmux riêng biệt, khi attach chỉ thấy 1 bên.
* **Cách sửa:** Trong `~/ensemble/services/ensemble-service.ts`, sau khi kết thúc Phase 3 (sau thông báo `🚀 ... collaboration started`), thêm:
  ```typescript
  if (activeAgents.length === 2) {
    try {
      const { execSync } = await import('child_process');
      const s1 = `${team.name}-${activeAgents[0].name}`;
      const s2 = `${team.name}-${activeAgents[1].name}`;
      execSync(`tmux join-pane -h -s "${s2}:0" -t "${s1}:0" && tmux select-layout -t "${s1}" even-horizontal`, { stdio: 'ignore' });
    } catch (e) {}
  }
  ```

---

### Bước 4: Vá tính năng Giữ Màn Hình Khi Xong (Hold on Completion)
* **Nguyên nhân:** Mặc định hàm `killLocalAgent` trong `~/ensemble/lib/agent-spawner.ts` sẽ kill session ngay, làm đóng cửa sổ trước khi người dùng kịp đọc kết luận.
* **Cách sửa:** Sửa hàm `killLocalAgent` thành:
  ```typescript
  export async function killLocalAgent(sessionName: string): Promise<void> {
    const runtime = getRuntime()
    try {
      await runtime.sendKeys(sessionName, 'C-c', { enter: false })
      await new Promise(r => setTimeout(r, 500))
      await runtime.sendKeys(sessionName, '/exit', { enter: true })
      await new Promise(r => setTimeout(r, 500))

      await runtime.sendKeys(sessionName, ' echo -e "\\n\\033[1;32m══════════════════════════════════════════════════════════════════════════════\\033[0m"', { enter: true })
      await runtime.sendKeys(sessionName, ' echo -e "\\033[1;32m  ✔ [NHIỆM VỤ ĐÃ HOÀN TẤT] Bạn có thể cuộn (Ctrl+B [) để xem lại toàn bộ.\\033[0m"', { enter: true })
      await runtime.sendKeys(sessionName, ' echo -e "\\033[1;33m  Nhấn phím bất kỳ (ESC, Enter...) để đóng cửa sổ này...\\033[0m"', { enter: true })
      await runtime.sendKeys(sessionName, ' echo -e "\\033[1;32m══════════════════════════════════════════════════════════════════════════════\\033[0m"', { enter: true })
      await runtime.sendKeys(sessionName, ' read -r -s -n 1; exit', { enter: true })
    } catch {}
  }
  ```

---

### Bước 5: Cấu hình mô hình tối ưu Token (`agents.json`)
Chỉnh sửa file `~/ensemble/agents.json`:
```json
{
  "agy": {
    "name": "agy",
    "command": "agy",
    "flags": ["--dangerously-skip-permissions", "--model", "gemini-4-argon-low", "--effort", "low"],
    "readyMarker": "? for shortcuts",
    "inputMethod": "sendKeys",
    "color": "red",
    "icon": "▲",
    "unsetEnv": ["GEMINI_API_KEY", "GOOGLE_API_KEY"]
  },
  "agy-worker": {
    "name": "agy-worker",
    "command": "agy-worker",
    "flags": ["--dangerously-skip-permissions", "--model", "gemini-3.8-flash-low", "--effort", "low"],
    "readyMarker": "? for shortcuts",
    "inputMethod": "sendKeys",
    "color": "yellow",
    "icon": "▼",
    "unsetEnv": ["GEMINI_API_KEY", "GOOGLE_API_KEY"]
  },
  "agy-pro": {
    "name": "agy-pro",
    "command": "agy-pro",
    "flags": ["--dangerously-skip-permissions", "--model", "gemini-4-argon-low", "--effort", "low"],
    "readyMarker": "? for shortcuts",
    "inputMethod": "sendKeys",
    "color": "magenta",
    "icon": "◆",
    "unsetEnv": ["GEMINI_API_KEY", "GOOGLE_API_KEY"]
  }
}
```

---

### Bước 6: Tích hợp Web Dashboard & API Xóa Phiên trong `server.ts`
1. Đặt `HOST = 0.0.0.0` để Windows có thể truy cập `http://localhost:23000`.
2. Thêm route phục vụ Web Dashboard từ `~/ensemble/public/index.html`.
3. Thêm các endpoint quản lý phiên:
   * `GET /api/ensemble/agents`: Lấy thông tin cấu hình agent và model.
   * `POST /api/ensemble/teams/:id/delete`: Xóa 1 phiên khỏi cơ sở dữ liệu.
   * `POST /api/ensemble/teams/purge-completed`: Dọn dẹp hàng loạt các phiên cũ.

---

### Bước 7: Cài đặt Daemon Service hệ thống (systemd)
Tạo file `/etc/systemd/system/ensemble.service` để server tự chạy 24/7 trong nền:
```ini
[Unit]
Description=Ensemble Multi-Agent HTTP Server and Web Dashboard
After=network.target

[Service]
Type=simple
User=truong
Group=truong
WorkingDirectory=/home/truong/ensemble
ExecStart=/usr/local/bin/tsx /home/truong/ensemble/server.ts
Restart=always
RestartSec=2
Environment=PORT=23000
Environment=HOST=0.0.0.0
Environment=HOME=/home/truong
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```
Kích hoạt service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ensemble.service
```

---

## 5. Tích Hợp Điều Khiển từ Windows & Biến Môi Trường PATH

Để có thể đứng ở **bất kỳ thư mục dự án nào trên Windows** (`D:\Projects\...`, `C:\...`) và gõ trực tiếp `collab "Nhiệm vụ"`:

### Bước 1: Script điều phối `run.sh` tại `D:\Ensemble\run.sh`
```bash
#!/usr/bin/env bash
TASK="${1:-Kiem tra phoi hop giua 2 agent}"
DIR="${2:-$HOME/test-collab}"
MODE="${3:-}"

export COLLAB_MONITOR="none"
mkdir -p "$DIR"
cd "$DIR"

AGENTS="agy,agy-worker"
TEMPLATE=""

case "$MODE" in
  review|review-pro)
    AGENTS="agy,agy-pro"
    TEMPLATE="review"
    ;;
  review-fast|review-flash)
    AGENTS="agy,agy-worker"
    TEMPLATE="review"
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
```

### Bước 2: Windows Launcher `collab.bat` tại `D:\Ensemble\collab.bat`
```cmd
@echo off
setlocal
set "TASK=%~1"
set "TEMPLATE=%~2"
if "%TASK%"=="" set "TASK=Kiem tra thu muc hien tai"

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
```

### Bước 3: Cấu hình biến môi trường PATH
Thêm `D:\Ensemble` vào biến môi trường **User PATH**:
```powershell
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*D:\Ensemble*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;D:\Ensemble", "User")
}
```

> 💡 **Quy tắc gọi lệnh:**
> * Gõ **`collab "nhiệm vụ"`** (không có `.\`) để Windows tự tìm trong `PATH` từ bất kỳ thư mục nào.
> * Tránh gõ `.\collab.bat` vì dấu `.\` bắt buộc file phải nằm ngay thư mục hiện tại.

---

## 6. Hướng Dẫn Sử Dụng Hàng Ngày

### 6.1. Khởi chạy nhiệm vụ
Mở PowerShell / CMD ở bất kỳ dự án nào:
```powershell
# 1. Chế độ mặc định (Lead Argon + Worker Flash):
collab "Phân tích backend và viết unit test"

# 2. Chế độ Phản biện Ngang Hàng (Lead Argon + Critic Argon):
collab "Rà soát toàn diện bảo mật và logic" review

# 3. Chế độ Phản biện Nhanh & Tiết kiệm (Lead Argon + Critic Flash):
collab "Kiểm tra syntax và conventions" review-fast
```

### 6.2. Theo dõi & Tương tác trên Web (`http://localhost:23000`)
* **Khung Group Chat duy nhất:**
  * **👑 LEAD**: Căn bên **Trái** (màu xanh dương đậm, vương miện, `Gemini 4 Argon`).
  * **⚡ WORKER / 🔍 REVIEWER**: Căn bên **Phải** (màu xanh ngọc / tím, `Gemini 3.8 Flash`).
  * **Tên Role chuẩn**: Tự động chuẩn hóa, không hiển thị mã `agy-1`, `agy-2`.
* **Xóa phiên chạy:** Bấm vào mục **Phiên chạy**, rê chuột (hover) vào dòng bất kỳ để hiện icon thùng rác 🗑️ và bấm xóa. Hoặc bấm nút **"🗑️ Dọn phiên cũ"** để dọn dẹp hàng loạt.
* **Tương tác 2 chiều:** Nhập tin nhắn vào ô chat dưới cùng để can thiệp / chỉ đạo trực tiếp cho cả nhóm hoặc từng agent.
* **Xem Terminal (Tùy chọn):** Nếu khi nào muốn xem dạng màn hình chia đôi 50/50 trên CLI, gõ `wsl tmux attach`.
