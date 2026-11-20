# Hướng Dẫn Cài Đặt & Sử Dụng pnpm Cho Dự Án Angular / Node.js (Windows & WSL2)

Tài liệu này hướng dẫn chi tiết cách cài đặt, cấu hình và vận hành **pnpm** (Performant npm) trên môi trường **Windows 11** và **WSL2**, đặc biệt tối ưu cho các dự án **Angular Monorepo** nằm trên ổ `D:\Projects`.

---

## 1. pnpm Là Gì? Tại Sao Nên Dùng Thay npm?

**pnpm** là trình quản lý gói thế hệ mới cho Node.js với 3 ưu điểm vượt trội:

* **Tiết kiệm ổ đĩa tối đa (Hard Links)**: Mọi thư viện (`@angular/core`, `rxjs`, `typescript`...) chỉ được tải và lưu **duy nhất 1 bản trên ổ đĩa** (trong thư mục `D:\.pnpm-store`). Các dự án (`HR.Admin`, `EAM.Admin`, `Shared`...) chỉ tạo liên kết cứng (hard links) trỏ về kho này.
* **Tốc độ cài đặt cực nhanh**: Nhanh hơn `npm` từ 2 đến 5 lần nhờ cơ chế cache thông minh và xử lý song song.
* **Tối ưu cho Windows + WSL2**: Giảm thiểu việc sao chép hàng trăm nghìn tệp nhỏ li ti qua cầu nối `/mnt/d/`, giúp IDE (Antigravity) và AI Agent (Claude Code) quét codebase nhanh gấp nhiều lần.

---

## 2. Hướng Dẫn Cài Đặt Trên Windows

Mở **PowerShell** (hoặc Windows Terminal) và chọn một trong các cách sau:

### Cách 1: Cài qua npm (Đơn giản nhất nếu máy đã có Node.js)
```powershell
npm install -g pnpm
```

### Cách 2: Cài qua Winget (Chuẩn Windows Package Manager)
```powershell
winget install pnpm.pnpm
```

### Cách 3: Bật qua Corepack (Đi kèm sẵn từ Node.js 16.9+)
```powershell
corepack enable
corepack prepare pnpm@latest --activate
```

> [!TIP]
> Kiểm tra phiên bản sau khi cài đặt:
> ```powershell
> pnpm -v
> ```

---

## 3. Cấu Hình Angular CLI Tự Động Dùng pnpm (Tùy chọn - Optional)

> [!NOTE]
> Bước này **không bắt buộc**. Nếu trong dự án bạn chỉ chạy `pnpm install`, `pnpm start`, `pnpm build` thì bạn có thể **bỏ qua bước này** để sang ngay [Mục 4](#4-chuyển-đổi-dự-án-angular-từ-npm-sang-pnpm).

Nếu máy bạn chưa cài đặt `@angular/cli` toàn cục (gặp lỗi `ng : The term 'ng' is not recognized`), bạn có 2 cách:

* **Cách 1: Chạy trực tiếp qua npx (Không cần cài đặt)**:
  ```powershell
  npx -p @angular/cli ng config -g cli.packageManager pnpm
  ```
* **Cách 2: Cài đặt Angular CLI toàn cục bằng pnpm trước**:
  ```powershell
  pnpm add -g @angular/cli
  ng config -g cli.packageManager pnpm
  ```

---

## 4. Chuyển Đổi Dự Án Angular Từ npm Sang pnpm

### Bước 1: Xóa thư mục cũ & Cập nhật `package.json`
Mở terminal tại thư mục gốc của dự án Angular:

1. **Xóa `node_modules` và `package-lock.json` cũ**:
   ```powershell
   Remove-Item -Recurse -Force node_modules
   Remove-Item -Force package-lock.json
   ```

2. **Xóa (hoặc đổi) khai báo `packageManager` trong `package.json`**:
   *(Nếu trong `package.json` đang có dòng `"packageManager": "npm@..."`, pnpm sẽ báo lỗi `ERR_PNPM_OTHER_PM_EXPECTED` vì nó phát hiện dự án đang bị khóa với npm).*
   
   Bạn chỉ cần chạy lệnh PowerShell này để xóa dòng đó tự động:
   ```powershell
   (Get-Content package.json) | Where-Object { $_ -notmatch '"packageManager"' } | Set-Content package.json
   ```
   *(Hoặc mở `package.json` xóa dòng `"packageManager": "npm@..."` đi).*

### Bước 2: Tạo tệp cấu hình `.npmrc` (Bắt buộc cho Angular)

> [!NOTE]
> Các dòng bên dưới là **nội dung nằm trong tệp `.npmrc`**, không phải lệnh gõ vào terminal.

Bạn có thể chạy ngay lệnh PowerShell này để tự động tạo tệp `.npmrc`:
```powershell
Set-Content -Path .npmrc -Value "auto-install-peers=true`nshamefully-hoist=true"
```

*(Hoặc tạo tệp tên `.npmrc` bằng Antigravity/VS Code và dán nội dung sau vào)*:
```ini
# Tự động cài đặt các peer dependencies
auto-install-peers=true

# Trải phẳng cấu trúc module giống npm (tránh lỗi module không tìm thấy của các thư viện bên thứ 3)
shamefully-hoist=true
```

> [!IMPORTANT]
> Dòng `shamefully-hoist=true` rất quan trọng với Angular: Nó tạo ra cấu trúc `node_modules` phẳng tương tự `npm`, giúp 100% thư viện bên thứ 3 (như UI controls, date picker, lodash...) tìm thấy nhau bình thường mà không bị lỗi phân giải module.

### Bước 3: Cài đặt gói với pnpm
Chạy lệnh cài đặt:
```powershell
pnpm install
```

> [!NOTE]
> **Nếu gặp thông báo `ERR_PNPM_IGNORED_BUILDS`**:
> Ở các phiên bản pnpm mới, tính năng bảo mật mặc định sẽ tạm hoãn các script cài đặt nhị phân (như `esbuild`, `@parcel/watcher` cần thiết cho Angular build).
> 
> Bạn chỉ cần chạy lệnh sau để phê duyệt tự động toàn bộ:
> ```powershell
> pnpm approve-builds --all
> ```
> Sau đó chạy lại:
> ```powershell
> pnpm install
> ```
> Quá trình cài đặt sẽ hoàn tất thành công 100%.

### Bước 4: Khởi chạy dự án
```powershell
# Chạy script start khai báo trong package.json
pnpm start

# Hoặc dùng Angular CLI trực tiếp
ng serve
```

---

## 5. Bảng Tra Cứu Lệnh Thông Dụng (pnpm vs npm)

| Thao tác | Lệnh `npm` | Lệnh `pnpm` tương đương |
| :--- | :--- | :--- |
| **Cài đặt toàn bộ** | `npm install` | `pnpm install` (hoặc ngắn gọn: `pnpm i`) |
| **Thêm thư viện** | `npm install lodash` | `pnpm add lodash` |
| **Thêm thư viện dev** | `npm install -D @types/node` | `pnpm add -D @types/node` |
| **Gỡ thư viện** | `npm uninstall lodash` | `pnpm remove lodash` (hoặc `pnpm rm`) |
| **Chạy script** | `npm run build` | `pnpm build` *(bỏ được chữ `run`)* |
| **Chạy dev server** | `npm start` / `npm run start` | `pnpm start` |
| **Cập nhật gói** | `npm update` | `pnpm update` |
| **Chạy công cụ không cài đặt** | `npx prettier --write .` | `pnpm dlx prettier --write .` |

---

## 6. Cơ Chế Lưu Trữ & Quản Lý Dung Lượng Đĩa

### Vị trí lưu trữ dữ liệu thật (Global Store)
Do `pnpm` sử dụng liên kết cứng NTFS (Hard Link chỉ tạo được trên cùng một phân vùng ổ đĩa):
* Dự án nằm trên ổ `D:\Projects\...` $\rightarrow$ Store nằm tại: **`D:\.pnpm-store\`**
* Dự án nằm trên ổ `C:\...` $\rightarrow$ Store nằm tại: **`C:\Users\<User>\AppData\Local\pnpm\store\`**

### Kiểm tra đường dẫn Store trên máy bạn
```powershell
pnpm store path
```

### Dọn dẹp dung lượng đĩa thừa (Prune)
Khi bạn gỡ bỏ dự án cũ hoặc nâng cấp thư viện, các gói cũ không còn ai sử dụng sẽ được thu hồi bộ nhớ bằng lệnh:
```powershell
pnpm store prune
```

---

## 7. Cài Đặt pnpm Trong WSL2 (Cho Claude Code & Agent)

Nếu bạn chạy Claude Code hoặc AI Agent trong Ubuntu (WSL2), nên cài đặt đồng bộ `pnpm` bên trong WSL:

```bash
# Mở terminal WSL2 và chạy:
curl -fsSL https://get.pnpm.io/install.sh | sh -

# Cập nhật biến môi trường:
source ~/.bashrc

# Kiểm tra:
pnpm -v
```

---

## 8. Xử Lý Các Sự Cố Thường Gặp (Troubleshooting)

### 1. Lỗi phân quyền liên kết (Symlink / Hard link) trên Windows
* **Nguyên nhân**: Windows 11 yêu cầu quyền Administrator để tạo symlink nếu chưa bật Developer Mode.
* **Khắc phục**:
  1. Mở Windows **Settings** $\rightarrow$ **System** $\rightarrow$ **For developers**.
  2. Bật chế độ **Developer Mode** sang **ON**.

### 3. Lỗi `The .../ABCD.Projects.Webs.Shared/public asset path must be within the workspace root`
* **Nguyên nhân**: Khi cài mới mà không có lockfile, dấu mũ `^` trong `package.json` khiến pnpm tự nâng `@angular/build` lên bản `21.2.30`. Bản mới này của Angular chặn tham chiếu assets ra ngoài thư mục dự án (ra thư mục `Shared`).
* **Khắc phục**: Khóa cứng phiên bản `@angular/build` và `@angular/cli` về **`21.2.8`** (phiên bản chuẩn của dự án):
  ```json
  "devDependencies": {
    "@angular/build": "21.2.8",
    "@angular/cli": "21.2.8"
  }
  ```
  Sau đó chạy `pnpm install` lại.
