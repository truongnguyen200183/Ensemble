# Sổ Tay Vận Hành Ensemble Multi-Agent (Dual Antigravity CLI)

Tài liệu hướng dẫn nhanh cách vận hành hệ thống đa tác tử AI (**Lead Agent** + **Worker Agent**) phối hợp giải quyết công việc lập trình trực tiếp trên các dự án Windows, theo dõi qua Web Group Chat.

---

## 1. Kiến Trúc Hoạt Động

* **👑 LEAD (`agy`)**: Kiến trúc sư trưởng / Lập kế hoạch (`gemini-4-argon-low`).
* **⚡ WORKER (`agy-worker`)**: Lập trình viên thực thi (`gemini-3.8-flash-low` - siêu nhẹ, tiết kiệm token).
* **🔍 REVIEWER (`agy-pro`)**: Chuyên gia phản biện cao cấp ngang hàng Lead (`gemini-4-argon-low`).
* **🌐 Web Group Chat Dashboard**: Giao diện trực quan tại **[http://localhost:23000](http://localhost:23000)**:
  * Khung chat nhóm duy nhất (Group Chat Stream).
  * **Lead** ở bên **Trái** (xanh dương), **Worker/Reviewer** ở bên **Phải** (xanh ngọc/tím).
  * Hiển thị chuẩn theo **Role**, không dùng mã kỹ thuật `agy-1`, `agy-2`.
  * Rê chuột (hover) vào danh sách phiên để hiện icon thùng rác 🗑️ xóa phiên.
  * Có nút **"Dọn phiên cũ"** để 1-click dọn dẹp các phiên đã hoàn tất.
  * Hỗ trợ gõ tin nhắn chỉ đạo trực tiếp từ ô chat dưới cùng.
* **Gọn gàng tối đa**: Khi ra lệnh, hệ thống **chỉ tự động mở Web**, hoàn toàn không bật thêm cửa sổ WSL đen nào.

---

## 2. Thao Tác Gọi Lệnh Hàng Ngày Trên Windows

Nhờ thư mục `D:\Ensemble` đã nằm trong `PATH`, bạn có thể mở terminal (PowerShell hoặc CMD) ở **bất kỳ thư mục nào trên máy tính** và gọi:

> ⚠️ **Lưu ý cách gõ lệnh:**
> * Gõ trực tiếp **`collab "nhiệm vụ"`** (không có `.\` phía trước) để Windows tự tìm trong `PATH`.
> * Không gõ `.\collab.bat` vì dấu `.\` bắt buộc file phải nằm ngay thư mục hiện hành.

### 2.1. Nhiệm vụ thông thường (Mặc định: Lead Argon + Worker Flash)
Phù hợp cho lập trình tính năng mới, viết unit test, sửa lỗi:
```powershell
collab "Viết một hàm xác thực JWT trong auth.js và viết unit test"
```
> 🚀 Sau khi bấm Enter, trình duyệt sẽ tự động bật tab **http://localhost:23000** để bạn theo dõi nhóm chat.

---

### 2.2. Hai Chế Độ Review & Phản Biện Code

#### 🔥 Chế độ 1: Phản biện Ngang Hàng (Lead Argon + Critic Argon)
Dành cho task khó, thiết kế kiến trúc hoặc audit bảo mật:
```powershell
collab "Rà soát toàn diện bảo mật và logic backend ABCD" review
```

#### ⚡ Chế độ 2: Phản biện Nhanh & Tiết Kiệm (Lead Argon + Critic Flash)
Dành cho kiểm tra syntax, coding conventions, tiết kiệm token tối đa:
```powershell
collab "Kiểm tra syntax và format code của module HR" review-fast
```

---

## 3. Quản Lý & Tương Tác Trên Giao Diện Web

Truy cập: **[http://localhost:23000](http://localhost:23000)**

* **Theo dõi thời gian thực**: Tin nhắn của Lead và Worker sẽ lần lượt xuất hiện theo dòng thời gian.
* **Chỉ đạo thêm cho Agent**: Ở thanh công cụ dưới đáy màn hình, bạn có thể chọn gửi đến `👥 Cả nhóm` hoặc chỉ định `👑 LEAD` / `⚡ WORKER`, gõ tin nhắn và nhấn **Enter** để can thiệp trực tiếp.
* **Xóa phiên chạy**:
  1. Bấm vào nút **"Phiên chạy"** trên thanh tiêu đề.
  2. Rê chuột vào phiên bạn muốn xóa ➔ Icon thùng rác 🗑️ màu đỏ sẽ xuất hiện ở bên phải.
  3. Bấm vào icon 🗑️ để xóa.
* **Dọn dẹp hàng loạt**: Bấm nút **"🗑️ Dọn phiên cũ"** ở đầu menu để xóa tất cả các phiên đã kết thúc/thử nghiệm, chỉ giữ lại các phiên đang chạy.
* **Bật/Tắt âm thanh & Tự cuộn**: Các nút điều khiển ở góc phải trên cùng.

---

## 4. Các Lệnh Tiện Ích Khác

| Nhu cầu | Lệnh thực hiện |
| :--- | :--- |
| **Kiểm tra trạng thái server** | `curl.exe http://localhost:23000/api/v1/health` |
| **Xem màn hình Terminal CLI (tùy chọn)** | Mở Ubuntu hoặc gõ `wsl tmux attach` |
| **Khởi động lại service nền Ensemble** | `wsl -u root systemctl restart ensemble.service` |
