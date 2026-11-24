# LockIn — Ôn thi ngay trên Lock Screen (iOS 17+)

**LockIn** là ứng dụng iOS SwiftUI thuần bản địa (Native iOS 17.0+, **Portrait-only**, **Local-first**) giúp bạn đưa flashcard ôn thi, tiến độ ngày và tác vụ ưu tiên trực tiếp lên **Interactive Live Activity** và **Interactive Lock Screen Widgets** để đọc ngay khi bật sáng màn hình và chạm chuyển thẻ / lật đáp án / đánh dấu đã thuộc ngay trên màn hình khóa mà không cần mở ứng dụng (sau khi iOS xác thực thiết bị theo chính sách WidgetKit/ActivityKit).

Dự án được thiết kế để lập trình trên **Windows**, biên dịch & kiểm thử tự động trên **GitHub Actions (`macos-latest`)**, và cài lên iPhone hoàn toàn **miễn phí \$0** qua **Sideloadly**, **AltStore**, hoặc **SideStore** (hỗ trợ nâng cấp lên **TestFlight** ở Phase 2).

---

## 1. Kiến trúc & Tính năng Phase 1 (MVP)

- **2 App Targets + 1 Test Target (tương thích giới hạn Personal Team của Apple ID miễn phí: 10 App IDs/7 ngày, 3 ứng dụng trên thiết bị):**
  - `LockInApp`: Tách biệt `Frontend/` (3 Tabs + 8 Features) và `Backend/` (8 modules qua protocol tại `Backend/Core/AppModuleProtocols.swift`).
  - `LockInWidgetsExtension`: Interactive Live Activity (`StudyLiveActivityWidget`) + `accessoryCircular` (**Tiến độ ôn thi**) + `accessoryRectangular` (**Ôn nhanh & Việc cần làm**).
  - `Shared/`: `AppConstants`, `SwiftDataEntities`, `StudySessionAttributes` (< 4KB), `AppGroupSnapshotStore` (JSON + POSIX `flock` + `sessionEpoch` + `snapshotRevisionId`), `CrossProcessNotifier` (Darwin IPC), `ExtensionCore/` và `7 Intents`.
  - `LockInTests/`: Đủ **8 bộ Unit Tests** kiểm thử Crypto/PBKDF2 600k, Auth/Session, cô lập đa hồ sơ, Encrypted Backup, Quick Import, Task/Progress/Streak, Scheduler/Notifications và Theme Shuffle.
- **3 Tab chính:**
  1. **Học & Tác vụ (`StudyHubTabView`):** Thanh Progress Bar & Streak, CRUD Bộ đề/Thẻ + đếm ngược ngày thi, Quick Import (`Câu hỏi | Đáp án | Ghi chú`, tối đa 500 dòng), nút **Đưa lên màn hình khóa**, danh sách Task & Lịch ôn tập real-time (`StudySchedule`) + thông báo cục bộ.
  2. **Giao diện (`ThemesTabView`):** 6 Theme tối giản (`Minimal Paper`, `Dark Focus`, `Pastel Matcha`, `Exam High-Contrast`, `Midnight Ink`, `Warm Sand`), chế độ **Shuffle Pool** (mở app / lịch học / iOS Shortcuts), tần suất thông báo nhắc việc và Pop-up việc tồn đọng.
  3. **Cài đặt (`SettingsTabView`):** Setup Wizard kết nối Live Activity / Thông báo / Shared App Group, tùy chỉnh cỡ chữ (`Compact` / `Standard` / `Large`), ẩn đáp án mặc định, **Privacy Mode** (`.privacySensitive()`), tạo & lưu ảnh **Wallpaper** vào Photos đặt thủ công, **App Lock** (Face ID / Touch ID dùng Keychain `.biometryCurrentSet` + PIN 6 số dự phòng PBKDF2 600k), Export/Import `.lockinbackup` mã hóa AES-GCM (tối đa 10 MB) và cô lập đa tài khoản cục bộ.

---

## 2. Quy trình Build trên Windows → GitHub Actions → Lấy file `.ipa` (\$0)

Bạn không cần máy Mac để build `LockIn`:

1. **Đẩy mã nguồn lên GitHub:**
   ```bash
   git add .
   git commit -m "Update LockIn"
   git push origin main
   ```
   *(Hoặc vào tab **Actions** trên GitHub → chọn workflow **iOS Free IPA Build & Verify** → nhấn **Run workflow**.)*
2. **CI tự động thực hiện trên `macos-latest`:**
   - Cài `xcodegen`, sinh `LockIn.xcodeproj` từ `project.yml`, kiểm tra `plutil -lint` cho 4 file `.plist`/`.entitlements` (bảo đảm Portrait-only và không có `aps-environment`).
   - Biên dịch `LockInWidgetsExtension` trên iOS Simulator.
   - Chạy toàn bộ **8 bộ Unit Tests (`LockInTests`)**.
   - Build bản Release unsigned của `LockInApp.app` (kèm `PlugIns/LockInWidgetsExtension.appex`), kiểm tra cấu trúc ZIP và đóng gói thành **`LockIn-unsigned.ipa`**.
3. **Tải file `.ipa` về Windows:**
   - Mở lần chạy workflow thành công trong **GitHub Actions** → kéo xuống mục **Artifacts** → tải **`LockIn-unsigned-ipa`** và giải nén để lấy file `LockIn-unsigned.ipa`.

---

## 3. Hướng dẫn cài đặt lên iPhone miễn phí (\$0)

> **Lưu ý giới hạn Personal Team (Apple ID miễn phí):** Tài khoản miễn phí cho phép tối đa **10 App IDs trong vòng 7 ngày**, tối đa **3 ứng dụng cài đặt hoạt động cùng lúc trên mỗi thiết bị**, và provisioning profile hết hạn sau **7 ngày**. `LockIn` dùng đúng **2 App IDs** (`LockInApp` + `LockInWidgetsExtension`), tức 2/10 App IDs và chỉ chiếm **1 trong 3 slot ứng dụng** trên thiết bị.

### Bước A — Bật Developer Mode trên iPhone (bắt buộc iOS 16/17+)
1. Mở **Cài đặt (Settings)** → **Quyền riêng tư & Bảo mật (Privacy & Security)** → **Chế độ Nhà phát triển (Developer Mode)** → Gạt bật và khởi động lại iPhone theo hướng dẫn.

### Bước B — Chọn một trong 3 công cụ sideload trên Windows

#### Cách 1: **SideStore** *(Khuyên dùng để tự gia hạn qua Wi-Fi không cần bật PC)*
1. Cài **SideStore** lên iPhone theo hướng dẫn trang chủ SideStore.
2. Gửi file `LockIn-unsigned.ipa` vào iPhone (iCloud Drive / Files / AirDrop / USB).
3. Mở **SideStore** → nhấn dấu **+** → chọn `LockIn-unsigned.ipa` → chọn **Keep App Extensions (Install Extensions)** khi được hỏi để giữ lại `LockInWidgetsExtension`.
4. Sau khi cài xong, vào **Cài đặt → Cài đặt chung → Quản lý VPN & Thiết bị** để tin cậy Apple ID cá nhân của bạn.
5. Bật Widget/Live Activity bình thường và gia hạn mỗi 7 ngày trực tiếp trong SideStore.

#### Cách 2: **AltStore**
1. Cài **AltServer** trên Windows và **iTunes / Apple Devices** + **iCloud** (bản tải từ apple.com, không dùng bản Microsoft Store).
2. Cắm iPhone vào PC qua cáp USB → cài **AltStore** lên iPhone.
3. Gửi `LockIn-unsigned.ipa` sang iPhone → mở bằng **AltStore** → **bắt buộc chọn giữ App Extensions (`Keep Extensions`)**.

#### Cách 3: **Sideloadly** *(Nhanh nhất nếu thử nghiệm từ PC Windows)*
1. Cài **Sideloadly** trên Windows, cắm iPhone qua USB (hoặc bật Wi-Fi Sync).
2. Kéo `LockIn-unsigned.ipa` vào Sideloadly → nhập Apple ID miễn phí → nhấn **Start**.
3. Mở **Cài đặt → Cài đặt chung → Quản lý VPN & Thiết bị** → tin cậy chứng chỉ Apple ID của bạn.
4. *(Nhắc nhớ: Cần cắm máy tính hoặc đồng bộ lại Sideloadly mỗi 7 ngày.)*

> **Cơ chế Shared App Group & xác minh chữ ký khi sideload:** File `embedded.mobileprovision` chỉ là **danh sách cho phép (entitlement allowlist)** của provisioning profile; quyền truy cập container lúc chạy thực tế phụ thuộc vào entitlement `com.apple.security.application-groups` trong **chữ ký đã resign của cả hai binary `LockInApp` và `LockInWidgetsExtension`**.
> `AppConstants.resolvedAppGroupIdentifier` ưu tiên `LockInAppGroupIdentifier` trong `Info.plist`, lọc **tất định chỉ các App Group thuộc phạm vi `LockIn`** (loại bỏ mọi App Group không liên quan của app khác và không phụ thuộc thứ tự trong profile), rồi kiểm tra `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` để cả 2 target luôn hội tụ về đúng một Shared App Group duy nhất ngay cả khi công cụ sideload đổi hậu tố Team ID.
> **Cách xác minh sau khi cài / resign:**
> 1. Khi cài qua SideStore / AltStore / Sideloadly, **bắt buộc chọn `Keep App Extensions`** để giữ `LockInWidgetsExtension` đi kèm cùng Team ID.
> 2. Mở app → **Cài đặt → Setup Wizard**: xác nhận mục **Shared App Group** báo **`Đồng bộ sẵn sàng`** (và kiểm tra nút hoàn thành nhanh trên Widget đồng bộ hai chiều tức thì với app trên iPhone thật).
> 3. *(Tùy chọn nếu có máy Mac kiểm tra tệp `.ipa` đã resign)*: chạy `codesign -d --entitlements :-` cho cả `LockInApp.app` và `LockInApp.app/PlugIns/LockInWidgetsExtension.appex` để đối chiếu `com.apple.security.application-groups` khớp nhau hoàn toàn.

---

## 4. Thiết lập Màn hình khóa, iOS Shortcuts & Nghiệm thu trên iPhone thật

### 4.1. Cài Widgets & iOS Shortcuts Automation
1. **Thêm Lock Screen Widgets:** Nhấn giữ màn hình khóa → **Tùy chỉnh** → **Màn hình khóa** → thêm **`Tiến độ ôn thi`** (widget tròn) và **`Ôn nhanh & Việc cần làm`** (widget chữ nhật) ngay dưới đồng hồ.
2. **Tạo Shortcut Automation xoay theme & ưu tiên lịch tự động:** Mở app **Phím tắt (Shortcuts)** → tab **Tự động hóa (Automation)** → `+` → chọn một trigger hợp lệ của iOS:
   - *Theo giờ trong ngày (Time of Day)*, *Chế độ Tập trung (Focus Mode)*, *Khi mở/đóng app (App Opened/Closed)*, hoặc *Khi cắm/rút sạc (Charger)*.
   - Thêm tác vụ **`Xoay Theme LockIn`** (*Run Immediately*, tắt Ask Before Running).
3. **Khởi động lại Live Activity sau 8–12 giờ:** Hệ điều hành iOS tự kết thúc Live Activity sau tối đa 8–12 giờ. Mở lại app và nhấn **Đưa lên màn hình khóa** hoặc tạo Shortcut gọi **`Khởi động lại phiên ôn trên Lock Screen`** (`StartStudyActivityIntent`).

### 4.2. Checklist Nghiệm thu trực tiếp trên iPhone thật (`spec.md §9`)
> Khi gửi báo cáo nghiệm thu trên iPhone thật, cần ghi rõ: **Model iPhone**, **Phiên bản iOS**, **Công cụ sideload**, **Commit SHA / Artifact ID**.

- [ ] **Cài đặt & Chữ ký Shared App Group:** Cài `LockIn-unsigned.ipa` giữ `LockInWidgetsExtension`; **Setup Wizard** báo `Shared App Group: Đồng bộ sẵn sàng`.
- [ ] **Hướng hiển thị:** Xoay ngang máy không làm app xoay (khóa chặt Portrait-only).
- [ ] **Đa hồ sơ, App Lock & Khôi phục đổi sinh trắc học (`agents.md §5.2.3`):** Tạo User A và User B, đăng xuất/chuyển tài khoản -> dữ liệu bộ đề, thẻ, task, lịch và theme tách biệt hoàn toàn; bật Face ID + PIN 6 số -> mở lại từ background có màn che bảo mật; thử thay đổi sinh trắc học trên máy -> mở khóa khôi phục thành công bằng mã PIN 6 số hoặc mật khẩu tài khoản.
- [ ] **Tab 1 (`Học & Tác vụ`):** Tạo bộ đề + Quick Import 2–3 cột -> Pin lên Lock Screen -> tạo lịch real-time -> nhận thông báo cục bộ đúng giờ.
- [ ] **Live Activity & 4 nút trên Lock Screen (Kiểm thử TRƯỚC và SAU xác thực):**
  - *Trước xác thực:* Bật sáng màn hình thấy thẻ (khi tắt Privacy Mode); chạm nút khi máy còn khóa -> iOS yêu cầu xác thực (Face ID / Touch ID / mật mã) theo chính sách hệ điều hành.
  - *Sau xác thực:* Chạm **`Trước`**, **`Lật`**, **`Thuộc`**, **`Tiếp`** -> nội dung cập nhật ngay trên Lock Screen **không nhảy vào app (`openAppWhenRun = false`)**; khi mở app thấy tiến độ & số thẻ thuộc đồng bộ tức thì (cả foreground lẫn quay lại từ background).
- [ ] **Widgets & Privacy Mode:** Widget `Tiến độ ôn thi` và `Ôn nhanh & Việc cần làm` (nút hoàn thành nhanh task) đồng bộ **hai chiều** tức thì với `LockInApp`; bật **Privacy Mode** -> khóa máy -> nội dung câu hỏi/đáp án ẩn trước khi quét Face ID và hiện rõ sau khi xác thực Face ID.
- [ ] **Tab 2 & Shortcuts:** Đổi 6 theme, kiểm tra Shuffle Pool khi mở app & khi kích hoạt `Xoay Theme LockIn` trong ứng dụng Phím tắt.
- [ ] **Tab 3 (Backup & Wallpaper):** Export `.lockinbackup` có passphrase -> thử Import sai passphrase (bị từ chối) -> Import đúng passphrase (khôi phục thành công); tạo & lưu ảnh Wallpaper vào Photos.

---

## 5. Nâng cấp Phase 2 lên TestFlight (\$99/năm)

Khi đã có tài khoản **Apple Developer Program (\$99/năm)**:
1. Tạo 2 App IDs có capability **App Groups** (`group.com.lockin.shared`) cho `com.lockin.app` và `com.lockin.app.widgets`, cùng 2 **App Store Distribution Provisioning Profiles**.
2. Khai báo các **GitHub Repository Secrets** cho workflow [`.github/workflows/ios-testflight.yml`](.github/workflows/ios-testflight.yml):
   - `APPLE_DIST_CERT_BASE64`, `APPLE_DIST_CERT_PASSWORD`, `RUNNER_KEYCHAIN_PASSWORD`
   - `APP_PROVISIONING_PROFILE_BASE64`, `WIDGET_PROVISIONING_PROFILE_BASE64`
   - `APP_EXPORT_OPTIONS_PLIST_BASE64`
   - `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_BASE64`
3. Chạy workflow **iOS TestFlight Distribution (Phase 2)** từ tab **Actions** trên GitHub để tự động archive, ký và upload lên **App Store Connect / TestFlight** (thời hạn 90 ngày/bản build).
