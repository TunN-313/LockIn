# Hướng dẫn Điều phối Multi-Agent (`agents.md`) — Dự án **LockIn**

> Tài liệu này dành cho **Orchestrator Neon** và toàn bộ đội ngũ sub-agents / workers khi làm việc trên workspace `LockIn`.
> Mọi agent tham gia dự án **bắt buộc đọc kỹ `spec.md` và `agents.md`** trước khi thiết kế hoặc sinh bất kỳ dòng code nào.

---

## 1. Nguyên tắc gốc & Nguồn sự thật (Source of Truth)

1. **`spec.md` là đặc tả gốc duy nhất:** Mọi tên file, cấu trúc module, schema dữ liệu, luồng Lock Screen và tiêu chí nghiệm thu phải tuân thủ tuyệt đối [spec.md](./spec.md). Không tự ý thêm/bớt tính năng hay đổi kiến trúc ngoài `spec.md`.
2. **Cập nhật `spec.md` trước khi kiểm toán:** Nếu phát hiện thiếu quyết định sản phẩm hoặc giới hạn kỹ thuật mới của iOS cần điều chỉnh kiến trúc, agent phải dừng lại báo `Orchestrator Neon` trình chủ dự án duyệt và **cập nhật `spec.md` trước** khi sinh code và trước khi gửi kiểm toán.
3. **Ngôn ngữ giao tiếp:** Mọi báo cáo, giải thích và yêu cầu xác nhận gửi tới chủ dự án phải viết bằng **Tiếng Việt** rõ ràng; giữ nguyên tên kỹ thuật, tên class/protocol, đường dẫn file và lệnh CLI.
4. **Quy trình "Confirm từng Wave" + Kiểm toán độc lập (GPT-6.2 Sol):** Dự án triển khai theo **4 Wave (Wave 0 → Wave 3)** ánh xạ đầy đủ từ **M0 → M5** (bao gồm cả **M4 Tests/CI** và **M5 Nghiệm thu**). Kết thúc mỗi Wave, `Orchestrator Neon` xuất **Audit Hand-off Packet** (Mục 8) để chủ dự án gửi **GPT-6.2 Sol** kiểm toán độc lập (tối đa **2 vòng phản hồi / Wave**), sau đó **chờ chủ dự án Confirm** trước khi mở Wave tiếp theo.

---

## 2. Đội hình Agent & Phân quyền sở hữu tệp (Agent Roster & File Ownership)

Để các agent làm việc song song an toàn mà không ghi đè lẫn nhau, mỗi vai trò chỉ được tạo/sửa các đường dẫn thuộc quyền sở hữu của mình:

| Vai trò Agent | Nhiệm vụ chính | Phạm vi đường dẫn sở hữu (Write Ownership) | Quyền đọc |
|---|---|---|---|
| **`Orchestrator Neon`** *(Coordinator / Tech Lead)* | Phân công theo Wave, khóa Contract ở Wave 0 (`AppModuleProtocols.swift`, `SyncEventBus.swift`, `CrossProcessNotifier.swift`), kiểm chứng chéo, rà soát bảo mật và xin Confirm từ chủ dự án. | Điều phối tổng thể; cập nhật `spec.md` / `agents.md` khi chủ dự án duyệt | Toàn bộ repo |
| **`contract-architect`** *(Shared & Contracts Agent)* | Thiết lập `project.yml` (compile `Shared/**` vào cả 2 app targets), Shared App Group, SwiftData `@Model`, `StudySessionAttributes` (< 4KB), bộ 6 `ThemePalette`, `CrossProcessNotifier` (Darwin IPC), interface `Shared/ExtensionCore/` và `Backend/Core/**`. | `project.yml`, `Shared/Config/**`, `Shared/Models/**`, `Shared/Storage/**`, `Shared/Themes/**`, `Shared/IPC/**`, `Backend/Core/**` | Toàn bộ repo |
| **`backend-engineer`** *(Backend Modules Agent)* | Cài đặt độc lập 8 Backend modules nghiệp vụ, lưu trữ, bảo mật (PBKDF2 600k, `.biometryCurrentSet`), lập lịch, theme, cầu nối Lock Screen và backup mã hóa; tái sử dụng `Shared/ExtensionCore/**`. | `Backend/StorageModule/**`, `Backend/SecurityModule/**`, `Backend/AuthModule/**`, `Backend/StudyModule/**`, `Backend/SchedulerModule/**`, `Backend/ThemeModule/**`, `Backend/LockScreenModule/**`, `Backend/BackupModule/**` | `spec.md`, `Shared/**`, `Backend/**` |
| **`frontend-engineer`** *(Frontend Features & Tabs Agent)* | Xây dựng DesignSystem, 8 `Features/` tách biệt (`*ViewModel` + `*View`) và lắp ghép vào `Tabs/` + `App/` theo đúng bảng ánh xạ. | `Frontend/App/**`, `Frontend/DesignSystem/**`, `Frontend/Tabs/**`, `Frontend/Features/**` | `spec.md`, `Backend/Core/AppModuleProtocols.swift`, `Backend/Core/DependencyContainer.swift`, `Backend/Core/SyncEventBus.swift`, `Shared/Models/**`, `Shared/Themes/**`, `Frontend/**` |
| **`lockscreen-engineer`** *(Lock Screen & Widgets Agent)* | Cài đặt `Shared/ExtensionCore/**`, 7 `AppIntent` / `LiveActivityIntent` trong `Shared/Intents/**` và giao diện Live Activity + Widgets trong `LockInWidgetsExtension/**`. | `Shared/ExtensionCore/**`, `Shared/Intents/**`, `LockInWidgetsExtension/**` | `spec.md`, `Shared/**` *(Cấm đọc/phụ thuộc `Backend/**`)* |
| **`qa-ci-engineer`** *(QA, Security & CI/CD Agent)* | Viết đủ 8 bộ Unit Tests cho toàn bộ logic trọng yếu, kiểm tra ranh giới import/bảo mật, xây dựng pipeline build `.ipa` miễn phí trên GitHub Actions. | `LockInTests/**`, `.github/workflows/**` | Toàn bộ repo |

> **Quy tắc chống xung đột:** Không agent nào được sửa file ngoài phạm vi `Write Ownership` của mình.
> - `Shared/Intents/**` và `LockInWidgetsExtension/**` **chỉ được dùng `Shared/**`**, tuyệt đối không import hay gọi `Backend/**`.
> - Khi `backend-engineer` và `lockscreen-engineer` chạy song song ở **Wave 1**, hợp đồng hàm công khai của `Shared/ExtensionCore/**` do `contract-architect` chốt khung sẵn từ **Wave 0** để hai luồng ghép nối không xung đột.
> - Nếu cần mở rộng protocol mới, gửi yêu cầu lên `Orchestrator Neon` để cập nhật `AppModuleProtocols.swift` trước.

---

## 3. Rào chắn Kiến trúc & Quy tắc Đồng bộ Frontend ↔ Backend (Hard Guardrails)

### 3.1. Tách biệt tuyệt đối `Backend/`, `Frontend/` và `LockInWidgetsExtension/`
- **`Frontend/` CẤM tuyệt đối:**
  - Không `import SwiftData`, `import Security`, `import CryptoKit`, `import CommonCrypto`, `import ActivityKit`, `import UserNotifications`, `import LocalAuthentication`.
  - Không truy vấn database, Keychain hay UserDefaults trực tiếp.
  - Mọi dữ liệu và hành động đều đi qua `*ViewModel` → các protocol trong `Backend/Core/AppModuleProtocols.swift` (được cung cấp qua `Backend/Core/DependencyContainer.swift`).
- **`Backend/` CẤM tuyệt đối:**
  - Không chứa SwiftUI `View` màn hình hay navigation của app (ngoại lệ duy nhất: render ảnh tĩnh ra `UIImage` trong `Backend/LockScreenModule/StudyWallpaperRenderService.swift`).
  - Không phụ thuộc ngược vào bất kỳ file nào trong `Frontend/`.
- **Ranh giới xuyên Target (`Shared/` vs `Backend/`):**
  - `Shared/Intents/**` và `LockInWidgetsExtension/**` **TUYỆT ĐỐI KHÔNG** tham chiếu hoặc phụ thuộc vào `Backend/**`. Mọi logic mà Intent cần phải nằm trong `Shared/ExtensionCore/**`.
  - Toàn bộ `Shared/**` (gồm `Config`, `Models`, `Storage`, `Themes`, `IPC`, `ExtensionCore`, `Intents`) **phải được cấu hình biên dịch ở cả 2 targets** `LockInApp` và `LockInWidgetsExtension` trong `project.yml`.

### 3.2. Single Responsibility & Self-Documenting Header
- Tên file, thư mục và trách nhiệm phải khớp **100%** sơ đồ cây trong mục 2.4 của `spec.md`. Không gộp nhiều feature hoặc nhiều backend service vào một file.
- Đầu mỗi file `.swift` **bắt buộc** có header comment 1–3 dòng nêu rõ:
  1. Tên & trách nhiệm duy nhất của file.
  2. Module/Protocol mà file này phụ thuộc hoặc cung cấp.

### 3.3. Quy tắc Đồng bộ trạng thái & IPC Liên tiến trình (`SyncEventBus` + `CrossProcessNotifier`)
1. **Luồng ghi đồng bộ:** Mọi thao tác làm thay đổi dữ liệu (tạo/sửa thẻ, đánh dấu đã thuộc, hoàn thành task, đổi theme, xoay Shuffle Pool, đổi cài đặt Privacy Mode) từ **Frontend Tabs** hoặc từ **`Shared/Intents`** đều phải:
   - Ghi qua `SharedStoreContainer` (`SwiftData`) và cập nhật `AppGroupSnapshotStore` kèm tăng **`snapshotVersion`**.
   - Nếu thao tác xuất phát từ `LockInApp`: `Backend/Core/SyncEventBus.swift` phát sự kiện domain (`cardsChanged`, `tasksChanged`, `progressUpdated`, `themeRotated`, `userSessionChanged`) tới các Tab, đồng thời gọi `LiveActivityBridgeService` (`Activity.update(...)`) và `WidgetCenter.shared.reloadAllTimelines()`.
   - Nếu thao tác xuất phát từ tiến trình `LockInWidgetsExtension`: `Shared/ExtensionCore/**` cập nhật trực tiếp `Activity.update(...)` + `WidgetCenter.shared.reloadAllTimelines()` và gọi **`CrossProcessNotifier.postStateDidChange()`** qua **Darwin Notification Center (`CFNotificationCenterGetDarwinNotifyCenter()`)**.
2. **Đồng bộ ngược từ Lock Screen vào `LockInApp` (2 kịch bản đầy đủ):**
   - **App đang ở Foreground:** `Backend/Core/SyncEventBus.swift` lắng nghe Darwin Notification từ `CrossProcessNotifier` để làm mới dữ liệu & UI các Tab **tức thì** ngay khi người dùng bấm nút trên Notification Center / Live Activity.
   - **App đang ở Background hoặc bị đóng:** Khi người dùng mở lại app (`scenePhase == .active`), `LockInAppEntry.swift` đối chiếu `snapshotVersion` với `AppGroupSnapshotStore` và gọi `SyncEventBus.refreshAll()` để đồng bộ toàn bộ thay đổi đã diễn ra trong Extension về cho Tab 1, Tab 2, Tab 3.

### 3.4. Bảng ánh xạ bắt buộc (Cấm nối tắt sai tầng)

| Frontend Tab / Gate | Frontend Feature | Backend Module được phép gọi |
|---|---|---|
| *(Root Gate)* | `Frontend/Features/Auth` | `AuthModule`, `SecurityModule` |
| **Tab 1:** `StudyHubTabView` | `Frontend/Features/ProgressAndStreak` | `StudyModule`, `Core/SyncEventBus` |
| **Tab 1:** `StudyHubTabView` | `Frontend/Features/DecksAndCards` | `StudyModule`, `LockScreenModule` |
| **Tab 1:** `StudyHubTabView` | `Frontend/Features/TasksAndSchedule` | `StudyModule`, `SchedulerModule` |
| **Tab 2:** `ThemesTabView` | `Frontend/Features/ThemeGallery` | `ThemeModule`, `LockScreenModule` |
| **Tab 2:** `ThemesTabView` | `Frontend/Features/ReminderPopup` | `StudyModule`, `SchedulerModule` |
| **Tab 3:** `SettingsTabView` | `Frontend/Features/LockScreenWizard` | `LockScreenModule`, `ThemeModule` |
| **Tab 3:** `SettingsTabView` | `Frontend/Features/SecurityAndBackup` | `SecurityModule`, `AuthModule`, `BackupModule`, `StorageModule` |

---

## 4. Quy tắc Đồ họa, Tài nguyên ngoài & MCP (Mandatory Asset Reporting Gate)

- **Tiêu chuẩn Phase 1:** Thiết kế tối giản (Minimalist / Flat Vector), khóa màn hình dọc (**Portrait-only**), dùng **100% SF Symbols** và **San Francisco system fonts** (`SF Pro`, `SF Pro Rounded`, `SF Mono`). Không tự ý nhúng file ảnh, Lottie, custom font hay Swift Package bên ngoài.
- **CỔNG DỪNG BẮT BUỘC (Asset & Dependency Gate):** Nếu bất kỳ agent nào nhận thấy cần tìm kiếm hoặc thêm đồ họa, icon pack, font ngoài, animation hoặc thư viện bên thứ 3 (từ repository, web, hoặc qua MCP server):
  1. **DỪNG NGAY** thao tác tải, cài đặt hoặc viết code tham chiếu tới tài nguyên đó.
  2. Gửi báo cáo cho `Orchestrator Neon` để trình chủ dự án đủ **4 thông tin**:
     - **Tên & loại tài nguyên/gói**
     - **Nguồn gốc cụ thể** (URL / Repo / Tên công cụ MCP)
     - **Giấy phép (License)** (MIT, Apache-2.0, CC0, v.v.)
     - **Mục đích & vị trí sử dụng trong dự án**
  3. Chỉ được tích hợp sau khi có **xác nhận đồng ý bằng văn bản từ chủ dự án**.

---

## 5. Quy tắc Kỹ thuật iOS (\$0 Sideload) & Tiêu chuẩn Bảo mật

### 5.1. Kỹ thuật iOS & Sideload miễn phí \$0
- **Quản lý Project bằng XcodeGen:** Không bao giờ tạo hoặc chỉnh tay file `.pbxproj`. Mọi target, entitlements, Info.plist và đường dẫn file khai báo trong `project.yml`. Toàn bộ `Shared/**` phải gắn vào **cả `LockInApp` và `LockInWidgetsExtension`**.
- **Giới hạn 2 App Targets (Free Apple ID 3-App-ID Limit):** Phase 1 chỉ duy trì đúng `LockInApp` và `LockInWidgetsExtension` (kèm `LockInTests` chỉ chạy lúc test). Tuyệt đối không tạo thêm Extension phụ khác.
- **Không dùng APNs / Remote Push:** Không khai báo entitlement `aps-environment`.
- **`LiveActivityIntent` & `StartStudyActivityIntent` (`openAppWhenRun`):**
  - 4 Intent tương tác thẻ (`FlipCardIntent`, `NextCardIntent`, `PrevCardIntent`, `MarkMasteredIntent`) **bắt buộc conform `LiveActivityIntent`**, đặt `openAppWhenRun = false` và compile ở cả 2 targets.
  - Vì `Activity.request(...)` yêu cầu app ở foreground (khi không có APNs push-to-start), **`StartStudyActivityIntent` BẮT BUỘC đặt `static var openAppWhenRun: Bool = true`**. Khi Live Activity hết hạn 8–12 giờ, người dùng phải mở app để khởi tạo lại phiên mới.
- **iOS Shortcuts Triggers thực tế & Phạm vi Wallpaper đã chốt:**
  - Cấm ghi hoặc giả định iOS Shortcuts có trigger "khi khóa / mở điện thoại". Chỉ hướng dẫn và thiết kế cho trigger có thật (*Time of Day*, *Focus Mode*, *App Opened/Closed*, *Charger*).
  - **Study Wallpaper Generator (Mục 4.3 `spec.md`):** Đã chốt hạ cấp cho Phase 1 — chỉ render ảnh PNG tóm tắt bài ôn để lưu vào Photos đặt thủ công (`NSPhotoLibraryAddUsageDescription`), **bỏ `GenerateStudyWallpaperIntent`** khỏi Phase 1.
- **App Group linh hoạt khi sideload:** Mọi truy cập App Group ID và Bundle ID phải đi qua `Shared/Config/AppConstants.swift` để dễ thích nghi khi AltStore/SideStore/Sideloadly đổi prefix Bundle ID theo Apple ID cá nhân.
- **Giới hạn payload ActivityKit (< 4KB):** `StudySessionAttributes.ContentState` chỉ mang dữ liệu của **1 thẻ đang hiển thị** (rút gọn an toàn `questionText` và `answerText` tối đa 220 ký tự), danh sách thẻ đầy đủ lưu trong `SharedStoreContainer`.

### 5.2. Tiêu chuẩn Bảo mật Không thỏa hiệp (Chuẩn OWASP)
1. **Không plain-text secret:** Cấm lưu mật khẩu, PIN hoặc passphrase ở dạng plain-text trong `SwiftData`, `UserDefaults` hay log.
2. **Băm chuẩn OWASP 600,000 vòng:** Dùng **`PBKDF2-HMAC-SHA256` tối thiểu `600,000` iterations** + `16-byte random salt` (`SecRandomCopyBytes`) + so sánh constant-time cho **tất cả 3 hạng mục**: (a) mật khẩu tài khoản cục bộ, (b) mã PIN 6 số dự phòng, và (c) dẫn xuất khóa AES-256 cho file backup.
3. **Keychain đúng chuẩn & Ranh giới áp dụng `.biometryCurrentSet`:**
   - **CHỈ áp dụng `.biometryCurrentSet`** (`SecAccessControlCreateWithFlags` + `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`) cho **khóa bảo vệ của App Lock** (`biometricUnlockSecret` — chỉ đọc khi mở khóa app ở foreground trong Main App).
   - **CẤM áp dụng `.biometryCurrentSet` đại trà:** Không dùng cờ này cho `session token`, bản hash PIN 6 số dự phòng (dùng `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), hay bất kỳ dữ liệu nào mà `LiveActivityIntent` / `AppIntent` / Widget chạy nền trên Lock Screen cần đọc (dùng `AppGroupSnapshotStore` / `SharedStoreContainer`, xóa sạch khi đăng xuất) — vì item gắn `.biometryCurrentSet` sẽ đòi Face ID hoặc thất bại khi đọc ở nền.
   - Nếu sinh trắc học bị thay đổi làm vô hiệu hóa item `.biometryCurrentSet`, cho phép người dùng mở khóa bằng **mật khẩu hoặc mã PIN 6 số** (kiểm tra qua bản hash PBKDF2 `600,000` vòng tách biệt trong Keychain, cooldown tăng dần sau 5 lần sai) rồi cấp lại item `.biometryCurrentSet` mới.
4. **Cô lập dữ liệu đa user:** Mọi thao tác đọc/ghi trong `StorageModule` bắt buộc đi qua `UserDataIsolationGuard.swift` để lọc theo `activeUserId`.
5. **Privacy Mode:** Hỗ trợ `.privacySensitive()` trên text câu hỏi/đáp án ở Live Activity & Widget khi người dùng bật Privacy Mode trong Settings (mặc định tắt để tiện ôn thi trực tiếp trên màn hình khóa).
6. **Encrypted Backup:** File `.lockinbackup` mã hóa bằng `CryptoKit.AES.GCM` từ khóa dẫn xuất PBKDF2 (`600,000` vòng) của passphrase; kiểm tra tag toàn vẹn khi Import.
7. **Input Validation & Least Privilege:** Giới hạn Quick Import tối đa `500` dòng/lần, tối đa `500` ký tự/trường; giới hạn dung lượng import backup tối đa `10 MB`. Chỉ xin quyền hệ thống đúng lúc người dùng kích hoạt tính năng.

---

## 6. Lộ trình Thực thi Song song theo Wave & Ánh xạ Milestone (`M0–M5`)

> **Quy tắc Kiểm toán Độc lập:** Toàn bộ **4 Wave** (ánh xạ đầy đủ **M0 → M5**, bao gồm cả **M4 Tests/CI** và **M5 Nghiệm thu**) đều **BẮT BUỘC** xuất `Audit Hand-off Packet` (Mục 8) cho **GPT-6.2 Sol** kiểm toán độc lập trước khi Confirm, vì `M4`/`M5` là nơi các lỗi cấu hình `project.yml`, cross-target và CI dễ lộ ra nhất. Giới hạn tối đa **2 vòng phản hồi kiểm toán / Wave**.

| Wave thực thi | Milestone (`M0–M5`) tương ứng | Trọng tâm công việc | Kiểm toán GPT-6.2 Sol & Confirm |
|---|---|---|---|
| **Wave 0** | **`M0`** — Contract & Phạm vi | Khóa `project.yml`, `Shared/**` contracts, `Backend/Core/**`, IPC + chốt hạ cấp mục 4.3 (`spec.md`) | Có (tối đa 2 vòng) → Confirm |
| **Wave 1** | **`M1` + `M3` + `M4a`** *(Song song 3 luồng)* | `M1` Backend 8 modules · `M3` `ExtensionCore`/7 Intents/Widgets · `M4a` CI workflows, xác minh `xcodegen` & test fixtures | Có (tối đa 2 vòng) → Confirm |
| **Wave 2** | **`M2` + `M4b`** *(Song song 2 luồng)* | `M2` Frontend Features & 3 Tabs · `M4b` Hoàn thiện đủ 8 bộ Unit Tests | Có (tối đa 2 vòng) → Confirm |
| **Wave 3** | **`M5`** — Nghiệm thu Tổng thể | Đối chiếu mục 9 `spec.md`, audit cuối `project.yml`/CI & hướng dẫn sideload `.ipa` | Có (tối đa 2 vòng) → Confirm kết thúc |

### Wave 0 (`M0`) — Khóa Contract, IPC & Chốt phạm vi Phase 1
- **Phụ trách:** `contract-architect` + `Orchestrator Neon`
- **Đầu ra:**
  - `project.yml` (`SWIFT_VERSION: "5.0"`, khai báo đầy đủ `properties:` cho 2 `Info.plist` + 2 `.entitlements`, compile `Shared/**` ở cả `LockInApp` và `LockInWidgetsExtension`, khóa `Portrait-only`, iOS `17.0`).
  - `Shared/Config/AppConstants.swift`, `Shared/Models/SwiftDataEntities.swift`, `Shared/Models/StudySessionAttributes.swift` (`let` bất biến, giới hạn 220 ký tự & `< 4KB` UTF-8), `Shared/Storage/SharedStoreContainer.swift`, `Shared/Storage/AppGroupSnapshotStore.swift` (file JSON + POSIX `flock`, `sessionEpoch`, `snapshotRevisionId`), `Shared/Themes/ThemePalette.swift`, `Shared/IPC/CrossProcessNotifier.swift`.
  - `Backend/Core/AppModuleProtocols.swift`, `Backend/Core/DependencyContainer.swift`, `Backend/Core/SyncEventBus.swift` (tích hợp Darwin IPC + `refreshAll()` theo `SnapshotStateMarker`), và khung interface `Shared/ExtensionCore/` để Wave 1 chạy song song không xung đột.
  - **Chốt mục 4.3 `spec.md`:** Hạ cấp sang lưu ảnh Wallpaper vào Photos đặt thủ công, bỏ `GenerateStudyWallpaperIntent`. Việc lấy log `xcodegen generate` + 4 file cấu hình sinh ra trên `macos-latest` được chuyển sang xác minh qua GitHub Actions ở **Wave 1 (`M4a`)**.
- **Kiểm chứng bắt buộc:** Khớp 100% schema mục 7 của `spec.md`; `ContentState` < 4KB UTF-8; chỉ có 2 app targets + 1 test target; khóa bằng `flock` + `sessionEpoch` + `snapshotRevisionId`.
- **Điểm dừng:** In `Audit Hand-off Packet` (Mục 8) cho **GPT-6.2 Sol** (tối đa 2 vòng) → **Chờ chủ dự án Confirm Wave 0 (`M0`)**.

### Wave 1 (`M1 + M3 + M4a`) — Song song 3 luồng (`Backend`, `LockScreen/Extension`, `CI/Test Fixtures`)
*Chỉ kích hoạt sau khi Wave 0 đã Confirm; 3 agent chạy **đồng thời**:*
- **Luồng `M1` (`backend-engineer`):** Cài đặt 8 module trong `Backend/**` (`StorageModule`, `SecurityModule`, `AuthModule`, `StudyModule`, `SchedulerModule`, `ThemeModule`, `LockScreenModule`, `BackupModule`), áp dụng PBKDF2 `600,000` vòng + `.biometryCurrentSet` đúng phạm vi App Lock và tái sử dụng `Shared/ExtensionCore/**`.
- **Luồng `M3` (`lockscreen-engineer` — song song):** Hoàn thiện `Shared/ExtensionCore/**`, **7 Intents** trong `Shared/Intents/**` (`Flip/Next/Prev/MarkMastered` conform `LiveActivityIntent` với `openAppWhenRun = false`; `CompleteNextTaskIntent` & `RotateLockInThemeIntent`; `StartStudyActivityIntent` đặt `openAppWhenRun = true`; không đụng `Backend/**`) và toàn bộ UI trong `LockInWidgetsExtension/**`.
- **Luồng `M4a` (`qa-ci-engineer` — song song):** Tạo `.github/workflows/ios-free-ipa.yml`, `.github/workflows/ios-testflight.yml` (có bước chạy `xcodegen generate`, `swift --version`, kiểm tra 4 file `.plist`/`.entitlements` đầu ra) và khung fixtures / contract tests trong `LockInTests/**`.
- **Kiểm chứng bắt buộc:** Không có file nào đụng chéo `Write Ownership`; `Shared/Intents/**` không import `Backend/**`; `LockInWidgetsExtension` compile đủ với `Shared/**`; `Backend/SecurityModule` đạt PBKDF2 600k + `.biometryCurrentSet` chỉ cho App Lock.
- **Điểm dừng:** In `Audit Hand-off Packet` (Mục 8) tổng hợp cả 3 luồng cho **GPT-6.2 Sol** (tối đa 2 vòng) → **Chờ chủ dự án Confirm Wave 1 (`M1 + M3 + M4a`)**.

### Wave 2 (`M2 + M4b`) — Song song 2 luồng (`Frontend Features/Tabs` + `Full 8 Unit Test Suites`)
*Chỉ kích hoạt sau khi Wave 1 đã Confirm; 2 agent chạy **đồng thời**:*
- **Luồng `M2` (`frontend-engineer`):** Xây dựng `Frontend/App/**`, `Frontend/DesignSystem/**`, 8 `Frontend/Features/**` và 4 file trong `Frontend/Tabs/**`, nối đúng bảng ánh xạ mục 3.4 và lắng nghe `SyncEventBus` (cả foreground qua Darwin IPC lẫn background qua `scenePhase == .active`).
- **Luồng `M4b` (`qa-ci-engineer` — song song):** Hoàn thiện đầy đủ **8 bộ Unit Tests** trong `LockInTests/**` (`PasswordCryptoServiceTests`, `LocalAuthServiceTests`, `UserDataIsolationGuardTests`, `EncryptedBackupServiceTests`, `QuickImportParserServiceTests`, `TaskProgressStreakServiceTests`, `StudyScheduleServiceTests`, `ThemeShuffleEngineTests`).
- **Kiểm chứng bắt buộc:** Kiểm tra tĩnh `Frontend/` không có import bị cấm (`SwiftData`, `Security`, `CryptoKit`, `CommonCrypto`, `ActivityKit`, `UserNotifications`, `LocalAuthentication`); đủ 8 file test khớp danh sách `spec.md`; chỉ dùng SF Symbols & San Francisco fonts.
- **Điểm dừng:** In `Audit Hand-off Packet` (Mục 8) cho **GPT-6.2 Sol** (tối đa 2 vòng) → **Chờ chủ dự án Confirm Wave 2 (`M2 + M4b`)**.

### Wave 3 (`M5`) — Audit Nghiệm thu Cuối cùng & Hướng dẫn Cài lên iPhone
- **Phụ trách:** `Orchestrator Neon` + `qa-ci-engineer`
- **Đầu ra:** Đối chiếu từng checkbox ở mục 9 (`Tiêu chí nghiệm thu MVP`) của `spec.md`, rà soát toàn bộ repo không còn `TODO`/stub/plain-text secret, kiểm tra mọi file Swift đều được khai báo đúng trong `project.yml`, kiểm tra cuối cấu hình CI `.github/workflows/*.yml`, bàn giao hướng dẫn push lên GitHub chạy CI tải `LockIn-unsigned.ipa` và cài qua Sideloadly / AltStore / SideStore.
- **Điểm dừng:** In `Audit Hand-off Packet` cuối cùng (Mục 8) cho **GPT-6.2 Sol** kiểm toán tổng thể `M4`/`M5` (tối đa 2 vòng) → **Chờ chủ dự án Confirm kết thúc**.

---

## 7. Giao thức Tự kiểm chứng & Leo thang xử lý (Verification & Escalation)

### 7.1. Checklist Tự kiểm chứng trước khi bất kỳ Agent nào báo "Xong"
1. **Kiểm tra ranh giới thư mục & xuyên Target:** `Frontend/` không chứa import bị cấm; `Backend/` không chứa UI tab/screen; `Shared/Intents/` và `LockInWidgetsExtension/` không phụ thuộc `Backend/`.
2. **Kiểm tra Header & Single Responsibility:** Mỗi file đúng tên trong `spec.md`, có comment mô tả chính xác mục đích ở đầu file.
3. **Kiểm tra Đồng bộ & Intent:** Mọi thay đổi dữ liệu đều cập nhật `SharedStoreContainer` + tăng `snapshotVersion` + phát `SyncEventBus` / `CrossProcessNotifier` (Darwin Notification) + làm mới `ActivityKit`/`WidgetKit`; 4 nút thẻ conform `LiveActivityIntent` (`openAppWhenRun = false`); `StartStudyActivityIntent` đặt `openAppWhenRun = true`.
4. **Kiểm tra Bảo mật & Chất lượng code:** PBKDF2 đạt `600,000` vòng cho password/PIN/backup; sinh trắc học dùng Keychain `.biometryCurrentSet` **chỉ cho App Lock** (không gắn lên `session token` hay dữ liệu Intent nền); không để sót `TODO`, `FIXME`, `fatalError("not implemented")` hoặc bí mật hardcode.
5. **Kiểm tra `project.yml` & Tests:** Toàn bộ `Shared/**` compile cho cả 2 targets (`LockInApp`, `LockInWidgetsExtension`); đủ **8 bộ test** trong `LockInTests/**` (bao gồm `LocalAuthServiceTests` và `StudyScheduleServiceTests`).

### 7.2. Khi nào Agent phải DỪNG và leo thang lên `Orchestrator Neon` (hoặc Chủ dự án)?
- Cần thêm tài nguyên đồ họa, icon, font hoặc gói thư viện ngoài (kích hoạt Cổng dừng mục 4).
- Gặp mâu thuẫn giữa `spec.md` và API thực tế của iOS 17 (`ActivityKit`, `WidgetKit`, `SwiftData`).
- Một lỗi cấu hình/build CI hoặc lỗi kiểm thử thất bại quá **2 lần** liên tiếp mà không rõ nguyên nhân.
- **Vượt quá 2 vòng phản hồi kiểm toán độc lập với GPT-6.2 Sol trong cùng một Wave:** Dừng tranh luận giữa hai mô hình, tổng hợp ngắn gọn bất đồng và các phương án để **chủ dự án tự quyết định**.
- Phát hiện lỗ hổng bảo mật tiềm ẩn hoặc nguy cơ vượt giới hạn 3 App IDs của Free Apple ID.

---

## 8. Audit Hand-off Packet (Cuối mỗi Wave — Bắt buộc cho Kiểm toán Độc lập)

Ở cuối **mỗi Wave (`Wave 0` → `Wave 3`)**, `Orchestrator Neon` **bắt buộc** in đúng cấu trúc 5 mục dưới đây, **không tóm tắt bằng lời thay cho bằng chứng thô**, để chủ dự án gửi thẳng sang **GPT-6.2 Sol** kiểm toán (tối đa **2 vòng phản hồi / Wave**):

1. **Wave / Milestone & Danh sách file tạo/sửa:**
   - Ghi rõ tên Wave + Milestone ánh xạ (ví dụ: `Wave 0 (M0)`, `Wave 1 (M1 + M3 + M4a)`, `Wave 2 (M2 + M4b)`, `Wave 3 (M5)`).
   - Liệt kê đầy đủ đường dẫn tương đối của mọi file vừa tạo hoặc chỉnh sửa trong Wave đó.
2. **Kết quả lệnh quét thô (dán nguyên output từ terminal, kể cả khi kết quả rỗng — ghi rõ lệnh đã chạy + exit code):**
   - Lệnh `grep` / `rg` / `Select-String` quét các import cấm trong `Frontend/` (`SwiftData`, `Security`, `CryptoKit`, `CommonCrypto`, `ActivityKit`, `UserNotifications`, `LocalAuthentication`).
   - Lệnh quét SwiftUI `View` trong `Backend/` (ngoại lệ duy nhất được phép: `StudyWallpaperRenderService.swift`).
   - Lệnh quét tham chiếu `Backend` trong `Shared/Intents/` và `LockInWidgetsExtension/`.
   - Lệnh quét `TODO | FIXME | fatalError` và từ khóa secret/password hardcode trên các file vừa tạo/sửa.
3. **Trạng thái từng mục `7.1` và `5.2`:**
   - Liệt kê từng điểm trong checklist mục **7.1** và mục **5.2** với trạng thái rõ ràng: `Đạt` / `Chưa đạt` / `N/A (chưa tới Wave)` + trích dẫn **`file:dòng`** làm bằng chứng cụ thể.
4. **Các điểm lệch `spec.md` đã tự phát hiện & cách xử lý:**
   - Nếu có bất kỳ điểm nào cần điều chỉnh so với `spec.md`, phải cập nhật `spec.md` (và xin chủ dự án duyệt) **trước** khi xuất gói kiểm toán này.
5. **Nội dung đầy đủ chỉ của file thuộc nhóm trọng yếu:**
   - Chỉ dán toàn văn nội dung của các file trọng yếu mới tạo/sửa trong Wave hiện tại thuộc: `project.yml`, `Backend/Core/**`, `Backend/SecurityModule/**`, `Shared/IPC/**`, `Shared/ExtensionCore/**`, `Shared/Intents/**`, và `.github/workflows/**` (ở Wave 1 & Wave 3).
   - Các file UI / feature thông thường chỉ liệt kê đường dẫn ở Mục 1 để giữ gói kiểm toán gọn nhẹ.
