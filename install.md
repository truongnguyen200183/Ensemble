# 🚀 Hướng Dẫn Cài Đặt & Sử Dụng Ensemble Collab

> **Ensemble Collab** là hệ thống điều phối đa Agent AI tự trị (Lead, Worker, Reviewer) phối hợp giải quyết tác vụ kỹ thuật theo thời gian thực, tích hợp giao diện Web Dashboard trực quan và bộ công cụ dòng lệnh `collab` 1-Click.

---

## 📋 Mục lục

1. [Yêu cầu hệ thống](#-yêu-cầu-hệ-thống)
2. [Cấu hình trước khi cài đặt (`install.config.json`)](#-cấu-hình-trước-khi-cài-đặt-installconfigjson)
3. [Cài đặt trên Windows (1-Click)](#-cài-đặt-trên-windows-1-click)
4. [Cài đặt trên macOS & Linux (1-Click)](#-cài-đặt-trên-macos--linux-1-click)
5. [Tra cứu lệnh dòng lệnh `collab` (CLI Guide)](#-tra-cứu-lệnh-dòng-lệnh-collab-cli-guide)
6. [Cấu hình Tên miền riêng (Custom Domain & SSL)](#-cấu-hình-tên-miền-riêng-custom-domain--ssl)
7. [Xử lý sự cố thường gặp (Troubleshooting)](#-xử-lý-sự-cố-thường-gặp-troubleshooting)

---

## 💻 Yêu cầu hệ thống

| Hệ điều hành | Yêu cầu cốt lõi | Lưu ý |
| :--- | :--- | :--- |
| **Windows** | Windows 10 (Build 19041+) hoặc Windows 11 | Hỗ trợ WSL2 (Trình cài đặt sẽ tự động kiểm tra và cài đặt nếu thiếu) |
| **macOS** | macOS Monterey (12.0) trở lên | Hỗ trợ cả Apple Silicon (M1/M2/M3) và Intel |
| **Linux** | Ubuntu 20.04+, Debian 11+, Fedora 38+, Arch Linux | Cần quyền `sudo` để cài gói hệ thống |

---

## ⚙️ Cấu hình trước khi cài đặt (`install.config.json`)

Toàn bộ thông số hệ thống, mô hình AI và tên miền được quản lý tập trung trong file [`install.config.json`](./install.config.json):

```json
{
  "project": {
    "repository": "https://github.com/truongnguyen200183/Ensemble.git",
    "branch": "main"
  },
  "server": {
    "host": "0.0.0.0",
    "port": 23000,
    "domain": "",                                    // Điền domain riêng nếu có (vd: collab.congty.vn)
    "url": "http://localhost:23000",
    "cors_origins": "http://localhost:23000,http://127.0.0.1:23000",
    "auto_open_browser": true
  },
  "models": {
    "roles": {
      "lead": "gemini-3.8-flash-thinking",          // Model cho Trưởng nhóm (Lead)
      "worker": "gemini-3.8-flash",                  // Model cho Thực thi (Worker)
      "reviewer": "gemini-3.8-flash-thinking"        // Model cho Phản biện (Reviewer)
    },
    "fallbacks": {
      "lead": ["gemini-3.8-flash-thinking", "gemini-3.8-flash", "gemini-4-argon"],
      "worker": ["gemini-3.8-flash", "gemini-3.8-flash-thinking"],
      "reviewer": ["gemini-3.8-flash-thinking", "gemini-3.8-flash"]
    }
  }
}
```

> [!TIP]
> Bạn có thể giữ nguyên cấu hình mặc định hoặc tùy chỉnh các vai trò mô hình tùy theo gói Quota API mà bạn sở hữu.

---

## 🪟 Cài đặt trên Windows (1-Click)

### Cách thực hiện:
1. Mở thư mục dự án trên máy Windows (`D:\Ensemble`).
2. **Nhấp đúp chuột vào file [`install.bat`](./install.bat)** (hoặc chuột phải chọn *Run as administrator* nếu muốn tự động thêm Windows Defender Exclusion).

### Những gì trình cài đặt tự động thực hiện (Không cần gõ lệnh thủ công):
* [x] **Kiểm tra Windows Host**: Tự kiểm tra `git`, `node` (nếu thiếu, tự gọi `winget` để cài đặt tự động).
* [x] **Kiểm tra & Cài đặt WSL**: Kiểm tra xem WSL đã bật chưa. Nếu chưa có, tự động kích hoạt và cài đặt `Ubuntu`.
* [x] **Tự động cấu hình `/etc/wsl.conf` (Quan trọng)**:
  * Kích hoạt `[boot] systemd=true` để các lệnh quản lý dịch vụ `systemctl` hoạt động trơn tru.
  * Kích hoạt `[automount] metadata,umask=22,fmask=11` để phân quyền và đọc ghi file trên ổ `D:\` không bị lỗi quyền giả.
* [x] **Tự động tối ưu tài nguyên (`.wslconfig`)**: Thiết lập `memory=8GB`, `autoMemoryReclaim=gradual` và `vmIdleTimeout=-1` để server không bị tắt khi đóng cửa sổ.
* [x] **Tự động cấu hình Windows Defender**: Thêm thư mục `D:\Projects` vào danh sách loại trừ để CPU không bị nghẽn khi Agent quét mã nguồn.
* [x] **Cài đặt môi trường trong WSL**: Tự động cài `git`, `tmux`, `curl`, `jq`, `nodejs`, và công cụ chạy TypeScript `tsx`.
* [x] **Đồng bộ mã nguồn**: Tự động tải/cập nhật phiên bản mới nhất từ Git về WSL (`~/ensemble`).
* [x] **Cài đặt thư viện NPM**: Chạy `npm install` hoàn chỉnh trên Linux WSL.
* [x] **Cấu hình Dịch vụ nền (Systemd Service)**: Đăng ký dịch vụ `ensemble.service` tự động khởi động và chạy ngầm trên cổng `23000`.
* [x] **Thiết lập Biến môi trường (ENV)**: Lưu `ENSEMBLE_PORT`, `ENSEMBLE_URL`, `COLLAB_MONITOR` vào Windows User Environment và `~/.bashrc`.
* [x] **Đăng ký lệnh toàn cục**: Đưa thư mục `bin/` vào Windows `PATH`. Bạn có thể mở bất kỳ cửa sổ nào và gõ lệnh `collab` ngay lập tức!

---

## 🍎 Cài đặt trên macOS & Linux (1-Click)

### Cách thực hiện:
Mở Terminal và chạy lệnh sau:

```bash
chmod +x install.sh
./install.sh
```

### Những gì trình cài đặt tự động thực hiện:
* [x] **Kiểm tra công cụ**: Tự động cài đặt các công cụ còn thiếu qua Homebrew (macOS) hoặc APT/DNF/Pacman (Linux).
* [x] **Đồng bộ mã nguồn**: Clone hoặc pull repository vào `$HOME/Ensemble`.
* [x] **Cài đặt NPM Dependencies**: Cài đặt trọn gói thư viện TypeScript & Node.js.
* [x] **Đăng ký biến môi trường**: Tự động thêm vào `~/.zshrc` và `~/.bashrc`.
* [x] **Tạo liên kết toàn cục**: Tạo lệnh `/usr/local/bin/collab`.
* [x] **Cấu hình Daemon chạy ngầm**:
  * Trên macOS: Tạo **macOS LaunchAgent** (`com.ensemble.server.plist`).
  * Trên Linux: Tạo **Systemd Service** (`ensemble.service`).

---

## 🕹️ Tra cứu lệnh dòng lệnh `collab` (CLI Guide)

Sau khi cài đặt xong, bạn có thể mở bất kỳ cửa sổ dòng lệnh nào (CMD, PowerShell, Git Bash, Terminal macOS/Linux) và ra lệnh:

### 1. Khởi chạy nhiệm vụ cho 2 Agent
```bash
collab "Hãy rà soát bảo mật mã nguồn trong thư mục hiện tại"
```
* Tự động nhận diện thư mục làm việc hiện tại (tự chuyển đổi đường dẫn Windows `D:\...` sang Linux `/mnt/d/...`).
* Khởi động nhóm 2 Agent (Lead & Worker) độc lập trong Tmux.
* Tự động bật trình duyệt mở Web Dashboard (`http://localhost:23000`) để bạn theo dõi và chat trực tiếp.

### 2. Khởi chạy kèm Template chuyên biệt
```bash
# Template Phản biện ngang hàng (Reviewer vs Critic)
collab "Phản biện kiến trúc cơ sở dữ liệu" review

# Template Triển khai tính năng (Implement)
collab "Viết chức năng thanh toán Stripe" implement

# Template Gỡ lỗi sâu (Debug)
collab "Tìm nguyên nhân tràn bộ nhớ" debug
```

### 3. Kiểm tra trạng thái hệ thống
```bash
collab status
```
* Hiển thị trạng thái máy chủ, phiên bản, thời gian uptime.
* Liệt kê các phiên làm việc (Teams) đang hoạt động hoặc đã hoàn thành.

### 4. Kích hoạt lại phiên làm việc cũ (Reactivate)
```bash
# Kích hoạt lại phiên gần nhất
collab reactivate

# Hoặc kích hoạt lại theo ID phiên cụ thể
collab reactivate 2b13e9a3
```

### 5. Mở nhanh Web Dashboard
```bash
collab web
```

### 6. Quản lý dịch vụ máy chủ
```bash
collab start    # Khởi động máy chủ chạy nền
collab stop     # Dừng máy chủ
collab help     # Xem toàn bộ hướng dẫn
```

---

## 🌐 Cấu hình Tên miền riêng (Custom Domain & SSL)

Nếu bạn muốn truy cập Web Dashboard từ xa qua Internet bằng tên miền riêng (ví dụ: `collab.domain.com`):

### Bước 1: Khai báo trong `install.config.json`
Mở file [`install.config.json`](./install.config.json) và sửa:
```json
"server": {
  "domain": "collab.domain.com",
  "url": "https://collab.domain.com",
  "cors_origins": "https://collab.domain.com,http://localhost:23000"
}
```
Sau đó chạy lại `install.bat` (hoặc `install.sh`) để hệ thống tự động cập nhật CORS whitelist và biến môi trường.

### Bước 2: Triển khai Domain

#### Lựa chọn A: Dùng Cloudflare Tunnel (Khuyên dùng cho máy cá nhân / WSL tại nhà)
> Không cần mở cổng modem (NAT Port), không cần IP tĩnh, có sẵn SSL HTTPS miễn phí.

1. Cài đặt `cloudflared` từ trang chủ Cloudflare.
2. Trỏ domain về Ensemble:
   ```bash
   cloudflared tunnel --url http://localhost:23000
   ```

#### Lựa chọn B: Dùng Nginx Reverse Proxy (Khuyên dùng cho VPS / Dedicated Server)
1. Cấu hình file Nginx (`/etc/nginx/sites-available/ensemble`):
   ```nginx
   server {
       server_name collab.domain.com;
       location / {
           proxy_pass http://127.0.0.1:23000;
           proxy_http_version 1.1;
           proxy_set_header Upgrade $http_upgrade;
           proxy_set_header Connection 'upgrade';
           proxy_set_header Host $host;
           proxy_cache_bypass $http_upgrade;
       }
   }
   ```
2. Cấp chứng chỉ SSL HTTPS:
   ```bash
   sudo certbot --nginx -d collab.domain.com
   ```

---

## 🛠️ Xử lý sự cố thường gặp (Troubleshooting)

### 1. Lỗi PowerShell: `Execution_Policies` trên Windows
* **Hiện tượng**: Không chạy được file `.ps1` do chính sách bảo mật của Windows.
* **Khắc phục**: Luôn chạy file [`install.bat`](./install.bat) hoặc [`collab.bat`](./collab.bat) vì các file này đã tích hợp sẵn cờ `-ExecutionPolicy Bypass`.

### 2. Gõ lệnh `collab` báo `command not found`
* **Khắc phục**:
  * Tắt cửa sổ dòng lệnh hiện tại và mở cửa sổ mới để Windows/macOS cập nhật biến `PATH`.
  * Trên Windows, kiểm tra biến môi trường User PATH xem đã có đường dẫn thư mục `bin/` của Ensemble chưa.

### 3. Cảnh báo hết Quota mô hình AI
* **Hiện tượng**: Nút `⚙️ Model` trên thanh công cụ chuyển sang màu đỏ báo `Hết Quota`.
* **Khắc phục**: Nhấp vào nút `⚙️ Model` trên thanh công cụ Web Dashboard và chuyển vai trò của Agent sang mô hình còn hạn mức (khuyên dùng `Gemini 3.8 Flash`).

### 4. Muốn xem trực tiếp màn hình Terminal Tmux của các Agent
* Trên Windows: Gõ `wsl tmux attach`
* Trên macOS / Linux: Gõ `tmux attach`
* Thoát khỏi màn hình tmux: Nhấn `Ctrl + B`, sau đó nhấn `D`.

### 5. Lỗi `System has not been booted with systemd as init system (PID 1)`
* **Nguyên nhân**: File `/etc/wsl.conf` bị thiếu cấu hình `[boot] systemd=true` khiến WSL2 khởi động ở chế độ init thông thường và không hỗ trợ `systemctl`.
* **Khắc phục**:
  1. Chỉ cần **nhấp đúp chuột chạy lại `install.bat`** (trình cài đặt sẽ tự động nạp lại `systemd=true` và `metadata` vào `/etc/wsl.conf`).
  2. Mở PowerShell trên Windows và chạy lệnh khởi động lại WSL:
     ```powershell
     wsl --shutdown
     ```
  3. Sau đó mở lại terminal WSL, dịch vụ `ensemble` sẽ tự động chạy ngầm bình thường.

### 6. Tích hợp Mô hình Cục bộ Ollama (Local Network - Không tốn Quota)
Ensemble hỗ trợ kết nối trực tiếp với server **Ollama** nội bộ (ví dụ: `http://192.168.86.23:11434`) chạy mô hình **`gemma4:12b`** thông qua **Aider CLI**:
* **Cài đặt Aider**: Đã được tự động hóa qua `uv tool install --python 3.12 aider-chat`.
* **Sử dụng**: Trong giao diện Web Dashboard, chọn `⚙️ Model` hoặc khi tạo Task mới, chọn Agent là **`Ollama Gemma 4 (12B Local)`**.
* **Ưu điểm**:
  * 100% riêng tư và chạy trong mạng nội bộ.
  * Hoàn toàn không tốn tiền API hay quota hàng ngày.
  * Hỗ trợ tư duy (thinking mode) và chỉnh sửa code tự động.


