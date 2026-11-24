# Đặc tả kỹ thuật dự án: **LockIn**

> **Tài liệu gốc (Source of Truth)** cho quá trình thiết kế, lập trình, kiểm thử và đóng gói ứng dụng iOS **LockIn**.
> Mọi thay đổi về kiến trúc, phạm vi tính năng hoặc tài nguyên bên ngoài đều phải cập nhật tại đây và được chủ dự án xác nhận.

---

## 1. Thông tin dự án & Tầm nhìn (Overview)

- **Tên dự án:** `LockIn`
- **Nền tảng mục tiêu:** Native iOS (**SwiftUI**), yêu cầu tối thiểu **iOS 17.0+** (bắt buộc để sử dụng Interactive Live Activities và Interactive Lock Screen Widgets thông qua `AppIntents`).
- **Định hướng hiển thị:** Màn hình dọc cố định (**Portrait-only**).
- **Bài toán & Mục tiêu cốt lõi:**
  - Người dùng (đặc biệt là học sinh/sinh viên ôn thi) thường cầm điện thoại lên xem giờ hoặc kiểm tra thông báo rồi mới nhận ra mình quên ôn bài.
  - `LockIn` đưa trực tiếp tài liệu ôn thi (flashcard câu hỏi/đáp án, ghi chú ngắn, công việc ưu tiên) lên **Lock Screen** để khi bật sáng màn hình là thấy ngay nội dung cần ôn (khi tắt Privacy Mode), và sau khi iOS xác thực thiết bị (Face ID / Touch ID / mật mã) theo chính sách bảo mật WidgetKit/ActivityKit, người dùng chạm chuyển thẻ / lật đáp án / đánh dấu đã thuộc **ngay trên màn hình khóa mà không cần mở app (`openAppWhenRun = false`)**.
- **Lộ trình phát triển:**
  - **Phase 1 (MVP — Hiện tại):** Native iOS, lưu trữ và xử lý hoàn toàn cục bộ (Local-first), đồ họa tối giản dễ vibe-code, tối ưu chi phí **\$0** bằng quy trình build `.ipa` qua GitHub Actions (`macos-latest`) và cài lên iPhone thông qua AltStore / SideStore / Sideloadly.
  - **Phase 2 (Mở rộng sau MVP):** Nâng cấp phân phối lên **TestFlight / App Store** (khi có tài khoản Apple Developer \$99/năm), đồng bộ đám mây (Cloud Sync), thuật toán lặp lại ngắt quãng (**Spaced Repetition — SM-2**), nhập liệu từ ảnh/PDF (OCR), Pomodoro, và mở rộng sang phiên bản **Android**.

---

## 2. Kiến trúc kỹ thuật (Technical Architecture)

### 2.1. Tech Stack
- **Ngôn ngữ & UI:** Swift 5 language mode (toolchain Swift 5.10+), SwiftUI (khóa hướng dọc `UIInterfaceOrientationPortrait`).
- **Lưu trữ cục bộ:** `SwiftData` (tương thích iOS 17+), kết hợp tệp JSON (`LockInSnapshot.json`) kèm khóa liên tiến trình POSIX `flock` (`LockInSnapshot.lock`) trong **Shared App Group container** cho snapshot trạng thái nhẹ (có kiểm tra `sessionEpoch` & `snapshotRevisionId` chống ghi đè).
- **Tích hợp Lock Screen & Tự động hóa:** `ActivityKit`, `WidgetKit`, `AppIntents`, `UserNotifications`.
- **Bảo mật:** `Security` (iOS Keychain), `CryptoKit` (`SHA256`, `HMAC`, `AES.GCM`), `CommonCrypto` (PBKDF2-HMAC-SHA256), `LocalAuthentication` (Face ID / Touch ID).
- **Quản lý Project (Cross-OS friendly):** Dùng **XcodeGen (`project.yml`)** để sinh file `.xcodeproj` tự động trên CI macOS. Nhờ đó, lập trình viên làm việc trên Windows không bao giờ phải sửa tay file `.pbxproj` phức tạp.

### 2.2. Cấu trúc Targets & App Group
Dự án được cấu trúc thành 3 targets chính trong `project.yml`:
1. **`LockInApp`** (Main iOS Application): Hợp nhất `Frontend/` (giao diện 3 tab, các feature độc lập), `Backend/` (các module nghiệp vụ, bảo mật, lập lịch và cầu nối thiết bị) và `Shared/`.
2. **`LockInWidgetsExtension`** (`WidgetKit` Extension): Chứa cấu hình **Interactive Live Activity** (`StudySessionAttributes`), các **Interactive Lock Screen Widgets** (`accessoryCircular`, `accessoryRectangular`) và biên dịch cùng `Shared/` (bao gồm `Shared/ExtensionCore/**`, `Shared/Intents/**`, `Shared/IPC/**`).
3. **`LockInTests`** (Unit Test Target): Gồm **8 bộ test** kiểm thử toàn diện Auth, Crypto/PBKDF2 (600,000 vòng), User Isolation, AES-GCM Backup, Quick Import parser, Task/Progress/Streak, Real-time Scheduler và Theme Shuffle.

- **Shared App Group (`group.com.lockin.shared`):**
  - Cả `LockInApp` và `LockInWidgetsExtension` dùng chung container của App Group để đồng bộ dữ liệu thẻ ôn, tiến độ ngày và theme hiện tại.
  - Toàn bộ thư mục `Shared/` (gồm `Config`, `Models`, `Storage`, `Themes`, `IPC`, `ExtensionCore`, `Intents`) bắt buộc khai báo biên dịch trong **cả 2 targets** `LockInApp` và `LockInWidgetsExtension` trong `project.yml` để tránh lỗi thiếu symbol xuyên target (đặc biệt với các `LiveActivityIntent`).
  - Toàn bộ hằng số Bundle ID và App Group Identifier phải đặt tập trung tại một cấu hình chung (`AppConstants.swift`) với bộ lọc tất định chỉ dành cho các App Group thuộc phạm vi `LockIn` (loại bỏ mọi App Group không liên quan của app khác và kiểm tra `containerURL`), bảo đảm cả `LockInApp` và `LockInWidgetsExtension` luôn hội tụ về đúng một container chung duy nhất và mang cùng một `com.apple.security.application-groups` entitlement trong chữ ký sau khi resign.

### 2.3. Lưu ý kỹ thuật cho phân phối miễn phí \$0 (Personal Team / Free Apple ID Sideload)
- **Giới hạn Personal Team (Apple ID miễn phí):** Tài khoản Apple ID miễn phí hỗ trợ tối đa **10 App IDs trong vòng 7 ngày**, tối đa **3 ứng dụng cài đặt hoạt động cùng lúc trên mỗi thiết bị**, và provisioning profile hết hạn sau **7 ngày** (có thể tự gia hạn qua Wi-Fi với SideStore/AltStore). Vì vậy, Phase 1 chỉ sử dụng đúng **2 targets** (`LockInApp` + `LockInWidgetsExtension`), tiêu tốn 2/10 App IDs và chiếm 1/3 slot ứng dụng cài trên thiết bị, không tách thêm Extension phụ (Share Extension hay Notification Service Extension).
- **Không phụ thuộc APNs Push:** Tài khoản Apple ID miễn phí không có quyền dùng Push Notification server (`aps-environment`). Kiến trúc `LockIn` chạy **Live Activity hoàn toàn cục bộ** bằng `ActivityKit` + `AppIntents` + `UserNotifications`, đảm bảo mọi tính năng cốt lõi hoạt động 100% ở chế độ \$0.

### 2.4. Kiến trúc mã nguồn: Tách biệt `Backend/` và `Frontend/` (Modular MVVM + Sync Contract)

Để tối ưu cho quy trình vibe-code và tránh rối mã nguồn khi mở rộng, toàn bộ codebase của `LockInApp` được **tách thành 2 thư mục độc lập ở cấp gốc: `Backend/` và `Frontend/`** (cùng `Shared/` dùng chung với Widget Extension). **Mỗi file chỉ đảm nhận đúng một trách nhiệm duy nhất (Single Responsibility)**, tên file và mô tả nói chính xác file đó làm gì:

- **`Backend/`** chứa toàn bộ các **module nghiệp vụ, dữ liệu, bảo mật và cầu nối hệ thống** tách biệt hoàn toàn theo từng domain. Không chứa bất kỳ SwiftUI View hay thành phần UI nào.
- **`Frontend/`** chứa **`Tabs/`** (lắp ghép giao diện chính), **`Features/`** (từng tính năng độc lập gồm `*ViewModel` + `*View`), **`DesignSystem/`** và **`App/`**. **Tuyệt đối không** import hay gọi trực tiếp `SwiftData`, `Security` (Keychain), `CryptoKit`, `ActivityKit` hoặc `UserNotifications` từ `Frontend/`.

```text
LockIn/
├── project.yml                                     # Cấu hình XcodeGen ghép Backend/, Frontend/, Shared/ vào các targets (compile Shared/** ở cả 2 app targets)
│
├── Backend/                                        # TẦNG NGHIỆP VỤ & HỆ THỐNG (Tách theo từng Module độc lập)
│   ├── Core/
│   │   ├── AppModuleProtocols.swift                # Định nghĩa toàn bộ protocol giao tiếp giữa Frontend và từng Backend module
│   │   ├── DependencyContainer.swift               # Khởi tạo, cấu hình và tiêm (inject) tất cả Backend modules vào Frontend
│   │   └── SyncEventBus.swift                      # Phát sự kiện trong app, lắng nghe Darwin Notification (foreground) & đối chiếu snapshotVersion (active)
│   │
│   ├── StorageModule/
│   │   ├── SwiftDataStudyStore.swift               # Đọc/ghi các entity SwiftData trong Shared App Group container
│   │   └── UserDataIsolationGuard.swift            # Ép buộc lọc mọi truy vấn dữ liệu theo activeUserId để cô lập user
│   │
│   ├── SecurityModule/
│   │   ├── KeychainStorageService.swift            # Lưu/đọc session, khóa nhạy cảm và item bảo vệ bằng .biometryCurrentSet trong iOS Keychain
│   │   ├── PasswordCryptoService.swift             # Băm mật khẩu & PIN bằng PBKDF2-HMAC-SHA256 (600,000 vòng) + random salt + constant-time verify
│   │   └── BiometricPinLockService.swift           # Mở khóa Keychain bằng .biometryCurrentSet (Face ID/Touch ID) & fallback PIN 6 số + cooldown
│   │
│   ├── AuthModule/
│   │   └── LocalAuthService.swift                  # Đăng ký, đăng nhập, đăng xuất và chuyển đổi hồ sơ user cục bộ
│   │
│   ├── StudyModule/
│   │   ├── StudyDeckCardService.swift              # CRUD bộ đề (StudyDeck), thẻ ôn (StudyCard), đếm ngược ngày thi (tái sử dụng SharedCardNavigationEngine)
│   │   ├── QuickImportParserService.swift          # Phân tích chuỗi dán nhanh "Câu hỏi | Đáp án | Ghi chú" thành danh sách thẻ hợp lệ
│   │   └── TaskProgressStreakService.swift         # CRUD TaskItem, tính Progress Bar ngày và cập nhật Streak (tái sử dụng SharedTaskQuickActionEngine)
│   │
│   ├── SchedulerModule/
│   │   ├── StudyScheduleService.swift              # Quản lý khung giờ ôn tập real-time theo giờ và ngày lặp lại trong tuần
│   │   └── LocalNotificationService.swift          # Lên lịch, cập nhật và hủy thông báo cục bộ UNUserNotificationCenter
│   │
│   ├── ThemeModule/
│   │   ├── ThemeCatalogService.swift               # Cung cấp 6 theme cài sẵn và lưu lựa chọn theme của user
│   │   └── ThemeShuffleEngine.swift                # Điều phối cấu hình Shuffle Pool, ủy quyền thuật toán xoay vòng cho SharedThemeRotationEngine
│   │
│   ├── LockScreenModule/
│   │   ├── LiveActivityBridgeService.swift         # Bật (foreground Activity.request), cập nhật payload < 4KB và kết thúc Live Activity
│   │   ├── StudyWallpaperRenderService.swift       # Render ảnh PNG tóm tắt 3-5 dòng bài ôn bằng ImageRenderer để lưu vào Photos đặt hình nền thủ công
│   │   └── DevicePermissionChecker.swift           # Kiểm tra trạng thái quyền Live Activities, Notifications và Shared App Group
│   │
│   └── BackupModule/
│       └── EncryptedBackupService.swift            # Đóng gói Export/Import file .lockinbackup mã hóa AES-GCM (khóa PBKDF2 600,000 vòng)
│
├── Frontend/                                       # TẦNG GIAO DIỆN & TÍNH NĂNG (Đọc/ghi dữ liệu hoàn toàn qua Backend)
│   ├── App/
│   │   ├── LockInAppEntry.swift                    # Điểm vào ứng dụng, khởi tạo DependencyContainer và gọi SyncEventBus khi scenePhase == .active
│   │   └── RootGateView.swift                      # Điều hướng giữa AuthLoginRegisterView, AppLockGateView và MainTabContainerView
│   │
│   ├── DesignSystem/
│   │   ├── ThemeStyleModifier.swift                # Áp dụng bảng màu và font chữ của ThemePalette lên bất kỳ View nào
│   │   ├── MinimalCardStyle.swift                  # Component thẻ bo góc tối giản dùng lại thống nhất toàn app
│   │   └── ProgressBarComponent.swift              # Thanh tiến độ hoàn thành tái sử dụng cho Header, Deck và Task
│   │
│   ├── Tabs/                                       # CÁC TAB CHÍNH (Lắp ghép các Features & giữ đồng bộ trạng thái)
│   │   ├── MainTabContainerView.swift              # Thanh TabView 3 tab (Portrait-only), gắn ReminderPopup khi mở app
│   │   ├── StudyHubTabView.swift                   # Tab 1: Ghép ProgressAndStreak + DecksAndCards + TasksAndSchedule
│   │   ├── ThemesTabView.swift                     # Tab 2: Ghép ThemeGallery + ShufflePoolConfig + ReminderPopup settings
│   │   └── SettingsTabView.swift                   # Tab 3: Ghép LockScreenWizard + Display Options + SecurityAndBackup
│   │
│   └── Features/                                   # CÁC FEATURE TÁCH BIỆT (Mỗi feature giữ ViewModel + Views riêng)
│       ├── Auth/
│       │   ├── AuthLoginRegisterViewModel.swift    # Quản lý form và trạng thái đăng nhập / đăng ký qua AuthModule
│       │   ├── AuthLoginRegisterView.swift         # Màn hình đăng nhập và tạo tài khoản cục bộ
│       │   ├── AppLockGateViewModel.swift          # Điều phối xác thực Keychain (.biometryCurrentSet) / PIN khi mở khóa app
│       │   └── AppLockGateView.swift               # Màn hình khóa sinh trắc học / nhập PIN 6 số
│       ├── ProgressAndStreak/
│       │   ├── DailyProgressHeaderViewModel.swift  # Theo dõi phần trăm mục tiêu ngày và streak từ StudyModule + SyncEventBus
│       │   └── DailyProgressHeaderView.swift       # Header hiển thị Progress Bar ngày và huy hiệu Streak
│       ├── DecksAndCards/
│       │   ├── DeckListAndEditorViewModel.swift    # Điều phối CRUD bộ đề/thẻ và kích hoạt Pin to Lock Screen
│       │   ├── DeckListView.swift                  # Danh sách bộ đề kèm tiến độ thuộc bài và đếm ngược ngày thi
│       │   ├── DeckDetailCardsView.swift           # Danh sách và trình sửa thẻ ôn trong một bộ đề
│       │   └── QuickImportSheetView.swift          # Modal dán văn bản nhanh và xem trước thẻ trước khi import
│       ├── TasksAndSchedule/
│       │   ├── TaskListViewModel.swift             # Điều phối CRUD TaskItem và đánh dấu hoàn thành đồng bộ sang Progress
│       │   ├── TaskListSectionView.swift           # Danh sách tác vụ cần làm theo mức ưu tiên và hạn chót
│       │   ├── SchedulePlannerViewModel.swift      # Điều phối cấu hình lịch học real-time và thông báo nhắc giờ
│       │   └── SchedulePlannerView.swift           # Giao diện cài đặt khung giờ ôn tập theo các ngày trong tuần
│       ├── ThemeGallery/
│       │   ├── ThemeGalleryViewModel.swift         # Quản lý chọn theme, cấu hình Shuffle Pool và trigger đồng bộ Lock Screen
│       │   ├── ThemeGalleryView.swift              # Lưới xem trước và chọn 6 theme tối giản
│       │   └── ShufflePoolConfigView.swift         # Bảng chọn các theme đưa vào vòng quay ngẫu nhiên và trigger hợp lệ
│       ├── ReminderPopup/
│       │   ├── PendingReminderViewModel.swift      # Kiểm tra task/thẻ đến hạn khi mở app để kích hoạt pop-up nhắc việc
│       │   └── PendingReminderPopupView.swift      # Pop-up / Sheet nhắc việc tồn đọng kèm nút Ôn ngay / Pin Lock Screen
│       ├── LockScreenWizard/
│       │   ├── LockScreenWizardViewModel.swift     # Đọc trạng thái quyền, bật/tắt Live Activity và tạo Wallpaper từ Backend
│       │   ├── LockScreenWizardView.swift          # Setup Wizard kết nối thiết bị và tùy chỉnh hiển thị Lock Screen
│       │   └── ShortcutsGuideSheetView.swift       # Hướng dẫn cài iOS Shortcuts Automation (Giờ trong ngày / Focus Mode / Mở app / Sạc)
│       └── SecurityAndBackup/
│           ├── SecurityAndBackupViewModel.swift    # Quản lý Face ID (.biometryCurrentSet) / PIN, Privacy Mode, Export/Import và xóa data
│           ├── SecuritySettingsView.swift          # Màn hình cài đặt bảo mật và quản lý hồ sơ cục bộ
│           └── EncryptedBackupSheetView.swift      # Giao diện nhập passphrase xuất/nhập file backup mã hóa
│
├── Shared/                                         # CODE DÙNG CHUNG (Biên dịch vào CẢ LockInApp và LockInWidgetsExtension)
│   ├── Config/AppConstants.swift                   # Tập trung Bundle ID, App Group ID, tên Darwin Notification và giới hạn dữ liệu
│   ├── Models/
│   │   ├── SwiftDataEntities.swift                 # Định nghĩa các @Model (UserProfile, StudyDeck, StudyCard, TaskItem,...)
│   │   └── StudySessionAttributes.swift            # Định nghĩa ActivityAttributes & ContentState (< 4KB) cho Live Activity
│   ├── Storage/
│   │   ├── SharedStoreContainer.swift              # Tạo ModelContainer dùng chung trên Shared App Group (báo lỗi rõ nếu thiếu App Group)
│   │   └── AppGroupSnapshotStore.swift             # Lưu snapshot JSON kèm khóa liên tiến trình flock, sessionEpoch & snapshotRevisionId
│   ├── Themes/
│   │   └── ThemePalette.swift                      # Định nghĩa struct màu sắc, font và danh sách 6 theme chuẩn
│   ├── IPC/
│   │   └── CrossProcessNotifier.swift              # Phát & nhận Darwin Notification (CFNotificationCenter) đồng bộ liên tiến trình
│   ├── ExtensionCore/                              # LOGIC TỐI THIỂU DÙNG CHUNG CHO INTENTS & BACKEND (Không phụ thuộc Backend/)
│   │   ├── SharedCardNavigationEngine.swift        # Xử lý Flip / Next / Prev / MarkMastered trong SharedStore, cập nhật Live Activity & IPC
│   │   ├── SharedTaskQuickActionEngine.swift       # Xử lý đánh dấu hoàn thành nhanh task ưu tiên kế tiếp từ Widget & phát IPC
│   │   └── SharedThemeRotationEngine.swift         # Thuật toán xoay vòng theme trong Shuffle Pool & đồng bộ snapshot/IPC
│   └── Intents/                                    # CHỈ phụ thuộc Shared/** (TUYỆT ĐỐI KHÔNG phụ thuộc Backend/** — 7 Intents Phase 1)
│       ├── FlipCardIntent.swift                    # LiveActivityIntent (openAppWhenRun = false) lật mặt câu hỏi/đáp án trên Lock Screen
│       ├── NextCardIntent.swift                    # LiveActivityIntent (openAppWhenRun = false) chuyển sang thẻ kế tiếp trên Lock Screen
│       ├── PrevCardIntent.swift                    # LiveActivityIntent (openAppWhenRun = false) quay lại thẻ trước trên Lock Screen
│       ├── MarkMasteredIntent.swift                # LiveActivityIntent (openAppWhenRun = false) đánh dấu đã thuộc & qua thẻ mới
│       ├── CompleteNextTaskIntent.swift            # AppIntent (openAppWhenRun = false) tick hoàn thành nhanh task trên Widget
│       ├── RotateLockInThemeIntent.swift           # AppIntent xoay theme tiếp theo trong Shuffle Pool (Shortcuts: Giờ/Focus/Mở app/Sạc)
│       └── StartStudyActivityIntent.swift          # AppIntent (openAppWhenRun = true BẮT BUỘC) mở app foreground để khởi tạo Live Activity mới
│
├── LockInWidgetsExtension/                         # EXTENSION MÀN HÌNH KHÓA (WidgetKit + Live Activity UI)
│   ├── LockInWidgetBundle.swift                    # Đăng ký StudyLiveActivityWidget và StudyLockScreenWidgets
│   ├── StudyLiveActivityWidget.swift               # Giao diện thẻ ôn Interactive Live Activity & Dynamic Island
│   └── StudyLockScreenWidgets.swift                # Giao diện accessoryCircular (vòng tiến độ) & accessoryRectangular (thẻ/task)
│
├── LockInTests/                                    # UNIT TESTS (8 bộ test kiểm thử đầy đủ Backend & Shared/ExtensionCore)
│   ├── PasswordCryptoServiceTests.swift            # Test PBKDF2-HMAC-SHA256 (600,000 vòng), random salt và constant-time verify
│   ├── LocalAuthServiceTests.swift                 # Test đăng ký, chuẩn hóa username, đăng nhập, chuyển hồ sơ, đăng xuất và cooldown PIN
│   ├── UserDataIsolationGuardTests.swift           # Test cô lập dữ liệu tuyệt đối theo ownerUserId giữa các local user
│   ├── EncryptedBackupServiceTests.swift           # Test PBKDF2 600k + AES-GCM Export/Import và từ chối khi sai passphrase / file bị sửa
│   ├── QuickImportParserServiceTests.swift         # Test tách chuỗi "Câu hỏi | Đáp án | Ghi chú", lọc dòng lỗi và chặn quá 500 dòng
│   ├── TaskProgressStreakServiceTests.swift        # Test tính % hoàn thành ngày, tiến độ bộ đề và chuỗi ngày Streak
│   ├── StudyScheduleServiceTests.swift             # Test bitmask T2–CN, tính khung giờ học real-time tiếp theo, ExamCountdown & nhắc giờ
│   └── ThemeShuffleEngineTests.swift               # Test xoay vòng Shuffle Pool (SharedThemeRotationEngine) và tránh lặp theme vừa dùng
│
└── .github/workflows/
    ├── ios-free-ipa.yml                            # CI miễn phí $0: chạy xcodegen, test (8 suites), build và đóng gói LockIn-unsigned.ipa
    └── ios-testflight.yml                          # CI Phase 2: ký certificate và upload lên TestFlight khi có tài khoản $99/năm
```

#### Quy tắc đồng bộ bắt buộc giữa `Frontend/`, `Backend/` và `LockInWidgetsExtension/` (Sync & Cross-Process IPC Contract)
1. **Một chiều phụ thuộc (Unidirectional Dependency):**
   - `Frontend/` chỉ phụ thuộc vào các protocol trong `Backend/Core/AppModuleProtocols.swift` (nhận qua `DependencyContainer`). `Backend/` **không bao giờ** biết đến `Frontend/`.
   - `Shared/Intents/` và `LockInWidgetsExtension/` **chỉ phụ thuộc `Shared/**`** (`Models`, `Storage`, `Themes`, `IPC`, `ExtensionCore`), **tuyệt đối không** phụ thuộc `Backend/`. Ngược lại, `Backend/` tái sử dụng `Shared/ExtensionCore/` để không nhân đôi nghiệp vụ.
2. **Đồng bộ khi thao tác trong App hoặc trên Lock Screen (`SyncEventBus` + `CrossProcessNotifier`):**
   - Khi người dùng thao tác trong app hoặc bấm nút `LiveActivityIntent`/`AppIntent` trên màn hình khóa:
     - Dữ liệu gốc được ghi vào `SharedStoreContainer` (`SwiftData`) và cập nhật `AppGroupSnapshotStore` (tăng `snapshotVersion`).
     - Nếu chạy trong `LockInApp`: `Backend/Core/SyncEventBus.swift` phát sự kiện domain (`cardsChanged`, `tasksChanged`, `progressUpdated`, `themeRotated`, `userSessionChanged`) tới toàn bộ các Tab đang mở, đồng thời gọi `Activity.update(...)` và `WidgetCenter.shared.reloadAllTimelines()`.
     - Nếu chạy trong tiến trình Extension (`LockInWidgetsExtension`): `Shared/ExtensionCore` cập nhật trực tiếp `Activity.update(...)` + `WidgetCenter.shared.reloadAllTimelines()` và gọi `CrossProcessNotifier.postStateDidChange()` (qua `CFNotificationCenterGetDarwinNotifyCenter()`).
3. **Đồng bộ 2 kịch bản vào App (Foreground & Background/Terminated):**
   - **Khi `LockInApp` đang mở ở Foreground** (ví dụ người dùng kéo Notification Center xuống bấm `NextCardIntent` / `MarkMasteredIntent`): `SyncEventBus` lắng nghe Darwin Notification từ `CrossProcessNotifier` để nhận tín hiệu liên tiến trình và làm mới các Tab **ngay lập tức** mà không cần đóng/mở lại app.
   - **Khi `LockInApp` ở Background hoặc đã bị hệ thống đóng:** Ngay khi mở lại app (`scenePhase == .active`), `LockInAppEntry` đối chiếu `snapshotVersion` và kích hoạt `SyncEventBus.refreshAll()` để kéo toàn bộ thay đổi từ `SharedStoreContainer` về đồng bộ nhất quán cho Tab 1, Tab 2, Tab 3.

#### Bảng ánh xạ Frontend (Tabs / Features) ↔ Backend Modules

| Frontend Tab | Frontend Feature | Backend Module tương ứng |
|---|---|---|
| *(Root Gate)* | `Features/Auth` | `AuthModule`, `SecurityModule` |
| **Tab 1:** `StudyHubTabView` | `Features/ProgressAndStreak` | `StudyModule`, `Core/SyncEventBus` |
| **Tab 1:** `StudyHubTabView` | `Features/DecksAndCards` | `StudyModule`, `LockScreenModule` |
| **Tab 1:** `StudyHubTabView` | `Features/TasksAndSchedule` | `StudyModule`, `SchedulerModule` |
| **Tab 2:** `ThemesTabView` | `Features/ThemeGallery` | `ThemeModule`, `LockScreenModule` |
| **Tab 2:** `ThemesTabView` | `Features/ReminderPopup` | `StudyModule`, `SchedulerModule` |
| **Tab 3:** `SettingsTabView` | `Features/LockScreenWizard` | `LockScreenModule`, `ThemeModule` |
| **Tab 3:** `SettingsTabView` | `Features/SecurityAndBackup` | `SecurityModule`, `AuthModule`, `BackupModule`, `StorageModule` |

---

## 3. Đặc tả chức năng 3 Tab (Functional Specification)

### Tab 1: Học & Tác vụ (`StudyHubTabView` — Màn hình chính)
1. **Thanh Tiến độ & Chuỗi ngày ôn (`Progress & Streak Header`):**
   - Hiển thị **Progress Bar** hoàn thành mục tiêu trong ngày (tính tổng hợp theo số thẻ đã ôn/thuộc và task đã xong).
   - Hiển thị thanh tiến độ riêng cho từng bộ đề (`masteredCount / totalCards`).
   - Bộ đếm **Streak** (số ngày liên tiếp người dùng có hoạt động ôn tập hoặc hoàn thành task).
2. **Quản lý Bộ đề & Thẻ ôn (`StudyDeck` & `StudyCard`):**
   - Tạo, sửa, xóa bộ đề (tên bộ đề, tag môn học, màu phân biệt, ngày thi mục tiêu để đếm ngược **`ExamCountdown`**).
   - Tạo, sửa, xóa thẻ ôn gồm: `question` (mặt trước), `answer` (mặt sau), `hintOrNote` (ghi chú ngắn tối đa 1–2 dòng), trạng thái (`new` / `learning` / `mastered`).
   - Nút nổi bật **"Đưa lên màn hình khóa" (Pin to Lock Screen)**: Bắt đầu hoặc cập nhật ngay phiên Live Activity cho bộ đề đó.
3. **Nhập liệu siêu tốc (`Quick Import`):**
   - Cho phép người dùng dán nhiều dòng văn bản theo cú pháp `Câu hỏi | Đáp án` hoặc `Câu hỏi | Đáp án | Ghi chú`.
   - Hiển thị bản xem trước (preview) số thẻ hợp lệ và cảnh báo dòng sai định dạng trước khi lưu hàng loạt.
4. **Danh sách Tác vụ & Lịch Real-time (`TaskItem` & `Real-time Scheduler`):**
   - Tạo task ôn tập cần làm (tiêu đề, hạn chót `dueDate`, mức độ ưu tiên `low`/`medium`/`high`, gắn tùy chọn với một bộ đề).
   - **Lên lịch Real-time (`StudySchedule`):** Cho phép chọn khung giờ ôn trong ngày và các ngày lặp lại trong tuần (T2–CN). Hệ thống đồng bộ với đồng hồ thực của thiết bị, lên lịch Local Notification nhắc đúng giờ và đánh dấu bộ đề ưu tiên khi đến khung giờ học. Do giới hạn iOS không có APNs push nền trong phạm vi \$0, Local Notification phát đúng giờ đã hẹn; còn thao tác ưu tiên bộ đề lên snapshot Lock Screen và xoay theme theo `autoRotateTheme` được thực thi khi người dùng mở LockIn trong khung giờ lịch (tối đa 2 giờ sau giờ hẹn), nhấn Bắt đầu phiên lịch ở Tab 1, hoặc chạy iOS Shortcuts *Theo giờ trong ngày (Time of Day)*.
5. **Điểm mở rộng kiến trúc (Extension Points):**
   - Thiết kế sẵn các protocol trừu tượng (`SchedulingEngineProtocol`, `StudyTimerProtocol`, `CardImporterProtocol`) để sau MVP có thể gắn thêm Spaced Repetition (SM-2), đồng hồ Pomodoro hoặc OCR/PDF mà không phá vỡ cấu trúc tab hiện tại.

### Tab 2: Giao diện & Nhắc nhở (`ThemesTabView`)
1. **Bộ sưu tập Theme tối giản cài sẵn (6 Themes chuẩn):**
   Mỗi theme định nghĩa rõ: màu nền (`backgroundHex`), màu thẻ (`cardHex`), màu chữ chính/phụ (`textPrimaryHex`, `textSecondaryHex`), màu nhấn (`accentHex`), kiểu font hệ thống (`default`, `rounded`, `monospaced`, `serif`), đảm bảo độ tương phản tối thiểu đạt chuẩn dễ đọc lướt trên màn hình khóa:
   - `Minimal Paper`: Nền giấy trắng ngà, chữ than chì, nhấn xanh cobalt.
   - `Dark Focus`: Nền đen OLED, chữ trắng tinh, nhấn xanh ngọc.
   - `Pastel Matcha`: Nền xanh trà nhẹ, chữ xanh rêu đậm, nhấn xanh lá.
   - `Exam High-Contrast`: Nền đen tuyền, chữ trắng/vàng chanh tương phản cực cao (ưu tiên đọc ban đêm / đọc lướt nhanh).
   - `Midnight Ink`: Nền xanh navy trầm, chữ kem sáng, nhấn vàng hổ phách.
   - `Warm Sand`: Nền cát ấm, chữ nâu đậm, nhấn cam đất.
2. **Chế độ Theme Ngẫu nhiên (`Shuffle Pool`):**
   - Người dùng có thể bật công tắc **Xoay vòng ngẫu nhiên (Shuffle Mode)** và tích chọn danh sách các theme yêu thích đưa vào `Shuffle Pool` (tối thiểu 2 theme).
   - Hỗ trợ các cơ chế kích hoạt đổi theme (`ThemeRotationTrigger`):
     - **Khi mở app:** Tự động đổi sang theme khác trong pool mỗi lần app chuyển sang trạng thái active (`scenePhase == .active`).
     - **Theo lịch real-time / Phiên học mới:** Đổi theme khi bắt đầu phiên ôn mới hoặc qua mốc thời gian đã cấu hình.
     - **Qua iOS Shortcuts Automation (các trigger thực tế của iOS):** Cung cấp `RotateLockInThemeIntent` (`AppIntent`) để người dùng gắn vào Automation hợp lệ trên iPhone — ví dụ: *Theo giờ trong ngày (Time of Day)*, *Chế độ Tập trung (Focus Mode, như Study Focus)*, *Khi mở/đóng app (App Opened/Closed)*, hoặc *Khi cắm/rút sạc (Charger)* — tự động xoay theme trên Live Activity/Widget (iOS Shortcuts **không** có trigger khóa/mở màn hình trực tiếp).
3. **Pop-up & Thông báo nhắc việc (`Reminder Popup & Local Notifications`):**
   - Khi mở app, nếu phát hiện có `TaskItem` quá hạn / sắp đến hạn trong ngày hoặc `StudyDeck` chưa hoàn thành mục tiêu hôm nay, hiển thị **Pop-up / Modal nhắc việc** (`PendingReminderPopupView`) tóm tắt số việc còn tồn đọng kèm nút hành động nhanh (*Ôn ngay*, *Đưa lên Lock Screen*, *Nhắc lại sau*).
   - Tùy chỉnh bật/tắt pop-up khi mở app và tần suất nhắc bằng Local Notification.

### Tab 3: Cài đặt & Kết nối Thiết bị (`SettingsTabView`)
1. **Trình hướng dẫn Kết nối Màn hình khóa (`Lock Screen Bridge Setup Wizard`):**
   - Bảng kiểm tra trạng thái thời gian thực (mỗi mục có đèn trạng thái Đạt / Chưa đạt + nút thao tác ngay):
     - Trạng thái quyền **Live Activities** (`ActivityAuthorizationInfo().areActivitiesEnabled`).
     - Trạng thái quyền **Thông báo** (`UNUserNotificationCenter`).
     - Trạng thái phiên **Live Activity** đang chạy (nút Bật / Làm mới / Dừng phiên ngay).
     - Kiểm tra đồng bộ **Shared App Group**.
   - **Hướng dẫn thiết lập iOS Shortcuts:** Hướng dẫn trực quan từng bước cách tạo Automation bằng các trigger có thật trên iPhone: *Theo giờ trong ngày (Time of Day)*, *Chế độ Tập trung (Focus Mode)*, *Khi mở/đóng app (App Opened/Closed)*, hoặc *Khi cắm/rút sạc (Charger)* → gọi `Rotate LockIn Theme` hoặc mở app chạy `Start Study Activity` khi phiên hết hạn.
2. **Tùy chỉnh hiển thị Lock Screen:**
   - Cỡ chữ trên Lock Screen (`Compact` / `Standard` / `Large`).
   - Chế độ mặc định khi hiện thẻ mới: **Chỉ hiện câu hỏi (chạm để lật đáp án)** hoặc **Hiện cả câu hỏi & đáp án**.
   - Bật/tắt **Privacy Mode** trên Lock Screen.
   - Tạo & lưu **ảnh Wallpaper tóm tắt bài ôn** (3–5 dòng) vào Thư viện ảnh (Photos) để người dùng tự đặt làm hình nền thủ công.
3. **Tài khoản cục bộ, Bảo mật & Sao lưu:**
   - Thông tin hồ sơ đang đăng nhập, nút chuyển tài khoản / đăng xuất.
   - Bật/tắt khóa ứng dụng bằng **Face ID / Touch ID** + đặt/đổi **mã PIN 6 số** dự phòng.
   - **Export Backup (`.lockinbackup`):** Nhập passphrase để xuất toàn bộ dữ liệu học tập của user hiện tại thành file JSON đã mã hóa AES-GCM.
   - **Import Backup:** Chọn file `.lockinbackup`, nhập đúng passphrase để khôi phục dữ liệu (hỗ trợ gộp hoặc ghi đè theo lựa chọn).
   - Xóa toàn bộ dữ liệu cá nhân của hồ sơ hiện tại (có hộp thoại xác nhận 2 bước).

---

## 4. Đặc tả cơ chế Lock Screen (`LockScreenBridge`)

### 4.1. Interactive Live Activity (`StudySessionAttributes`) — Cơ chế chính
- **Mục tiêu trải nghiệm:** Thẻ ôn nằm cố định trên Lock Screen ngay dưới đồng hồ (và trên Dynamic Island ở các dòng iPhone hỗ trợ). Người dùng đọc ngay nội dung thẻ khi bật sáng màn hình (nếu tắt Privacy Mode); khi chạm vào các nút tương tác trên Live Activity / Widget, iOS yêu cầu **xác thực / mở khóa thiết bị (Face ID / Touch ID / mật mã)** trước khi thực thi `LiveActivityIntent` / `AppIntent`, sau đó cập nhật trực tiếp trên Lock Screen và **không bị nhảy vào trong app (`openAppWhenRun = false`)**.
- **Giao diện trên Lock Screen:**
  - Header nhỏ: Tên bộ đề + vị trí thẻ (`3/15`) + thanh Progress Bar.
  - Body: Nội dung câu hỏi (hoặc đáp án khi đã bấm lật), font rõ ràng, màu sắc lấy theo `ThemePalette` đang hoạt động.
  - Thanh nút tương tác (`LiveActivityIntent` buttons — `openAppWhenRun = false`):
    1. `Trước` (`PrevCardIntent`)
    2. `Lật đáp án` / `Ẩn đáp án` (`FlipCardIntent`)
    3. `Đã thuộc` (`MarkMasteredIntent` — đánh dấu `mastered`, tăng `DailyProgress` và tự chuyển thẻ kế)
    4. `Tiếp` (`NextCardIntent`)
- **Ràng buộc kỹ thuật, Cross-Target & Tối ưu payload:**
  - `ActivityKit` giới hạn kích thước dữ liệu `ContentState` không vượt quá **4KB**.
  - Do đó, `StudySessionAttributes.ContentState` **chỉ chứa thông tin của 1 thẻ đang hiển thị**: `deckId`, `deckTitle`, `currentCardId`, `questionText` (cắt gọn an toàn tối đa 220 ký tự kèm dấu `...` nếu quá dài), `answerText` (tối đa 220 ký tự), `isAnswerVisible`, `currentIndex`, `totalCards`, `masteredCount`, `activeThemeId`, `privacyModeEnabled`, `fontScaleRaw`.
  - **Biên dịch xuyên target & `LiveActivityIntent`:** Cả 4 Intent (`FlipCardIntent`, `NextCardIntent`, `PrevCardIntent`, `MarkMasteredIntent`) bắt buộc conform **`LiveActivityIntent`** (`openAppWhenRun = false`), được đặt trong `Shared/Intents/` và **biên dịch vào cả 2 targets** (`LockInApp` + `LockInWidgetsExtension`). Các Intent này **chỉ gọi xuống `Shared/ExtensionCore/SharedCardNavigationEngine.swift`** (tuyệt đối không phụ thuộc `Backend/`) để đọc/ghi `SharedStoreContainer`, gọi `Activity.update(...)`, `WidgetCenter.shared.reloadAllTimelines()`, tăng `snapshotVersion` và phát Darwin Notification qua `CrossProcessNotifier` giúp `LockInApp` đang mở ở foreground cũng cập nhật tức thì.
  - **Khởi động lại phiên sau 8–12 giờ (`StartStudyActivityIntent`):** Hệ điều hành iOS tự kết thúc Live Activity sau tối đa ~8 giờ hiển thị (tối đa 12 giờ tổng thời gian). Vì `Activity.request(...)` **bắt buộc ứng dụng phải ở foreground** (trừ khi dùng push-to-start qua APNs — vốn không khả dụng ở Phase 1 \$0), nên **`StartStudyActivityIntent` BẮT BUỘC đặt `static var openAppWhenRun: Bool = true`**. Khi Live Activity hết hạn, người dùng phải mở app (chạm trực tiếp icon/widget hoặc chạy Shortcut đưa app lên foreground) để khởi động lại phiên mới; UI trong app hiển thị rõ trạng thái phiên để chạm 1 lần bật lại.

### 4.2. Interactive Lock Screen Widgets (`WidgetKit`)
- **`accessoryCircular`:** Vòng tròn tiến độ (`Gauge`) hiển thị % hoàn thành mục tiêu trong ngày và biểu tượng streak.
- **`accessoryRectangular`:** Hiển thị nhanh 1 thẻ đến hạn hoặc 1 `TaskItem` ưu tiên cao nhất kèm nút tương tác `CompleteNextTaskIntent` / `NextCardIntent` (xử lý qua `Shared/ExtensionCore/` + `CrossProcessNotifier`).

### 4.3. Study Wallpaper Generator *(Đã chốt hạ cấp cho Phase 1)*
- **Quyết định phạm vi Phase 1 (đã chốt ở Wave 0):** Thay cho tự động đổi hình nền qua Shortcuts (bỏ `GenerateStudyWallpaperIntent` khỏi Phase 1 để tập trung 100% độ ổn định vào Interactive Live Activity & Lock Screen Widgets).
- **Cơ chế thay thế nhẹ trong App:** Cung cấp tùy chọn render ảnh PNG tóm tắt 3–5 gạch đầu dòng cần ôn theo Theme hiện tại thông qua `SwiftUI.ImageRenderer` (chừa khoảng trống phía trên cho đồng hồ/widget iOS và phía dưới cho đèn pin/camera), cho phép người dùng bấm **Lưu vào Ảnh (Photos)** hoặc **Chia sẻ** để tự đặt làm hình nền Lock Screen thủ công khi muốn. Chỉ yêu cầu quyền `NSPhotoLibraryAddUsageDescription` đúng lúc người dùng bấm nút lưu ảnh.

---

## 5. Đăng nhập Cục bộ & Bảo mật (Authentication & Security)

1. **Đăng nhập User Cục bộ & Cô lập Dữ liệu (`Local-First Multi-Profile`):**
   - Cho phép tạo nhiều tài khoản cục bộ trên cùng một thiết bị (`username`, `displayName`, `password`).
   - Chuẩn hóa `username` (lowercase, trim khoảng trắng, chỉ cho phép ký tự hợp lệ, độ dài 3–32 ký tự).
   - Mọi bản ghi `StudyDeck`, `TaskItem`, `StudySchedule`, `ThemePreference`, `DailyProgress` đều gắn `ownerUserId: UUID` và bắt buộc lọc theo `activeUserId` đang đăng nhập.
2. **Bảo vệ Mật khẩu, Phiên làm việc & Phân vùng Lưu trữ An toàn:**
   - Mật khẩu người dùng đặt **tuyệt đối không lưu plain-text**.
   - Sử dụng **PBKDF2-HMAC-SHA256** với **`600,000` vòng lặp** (theo khuyến nghị OWASP hiện hành) kết hợp **16-byte random salt** sinh từ `SecRandomCopyBytes` cho mỗi tài khoản; lưu `passwordHash` và `salt` (dạng Data/Hex), đối chiếu bằng hàm so sánh constant-time.
   - **Phân tách rõ 3 vùng lưu trữ theo mức độ nhạy cảm và ngữ cảnh thực thi:**
     1. *Khóa bảo vệ App Lock (`biometricUnlockSecret`):* Lưu trong Keychain gắn **`.biometryCurrentSet`**, **CHỈ đọc khi mở khóa app ở foreground**.
     2. *Session token (`activeUserId` / phiên đăng nhập) & bản băm PIN 6 số dự phòng:* Lưu trong **iOS Keychain** với cờ `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (**KHÔNG gắn `.biometryCurrentSet`**).
     3. *Snapshot hiển thị Lock Screen không nhạy cảm (`activeUserId`, thẻ hiện tại, `snapshotVersion`, `activeThemeId`):* Lưu trong **Shared App Group** (`AppGroupSnapshotStore` / `SharedStoreContainer`) để `LiveActivityIntent` / `AppIntent` / Widget thực thi ngoài foreground (khi hệ thống làm mới timeline nền hoặc sau khi iOS xác thực thiết bị cho thao tác bấm nút) đọc ghi bình thường; toàn bộ snapshot này phải **xóa sạch khi đăng xuất**.
3. **Khóa Sinh trắc học & Mã PIN dự phòng (`App Lock Gate`):**
   - **Bảo vệ sinh trắc học thật ở tầng Keychain (khoanh vùng đúng phạm vi):** Lưu bí mật mở khóa sinh trắc học (`biometricUnlockSecret`) của **App Lock** trong iOS Keychain bằng **`SecAccessControlCreateWithFlags`** với cờ **`.biometryCurrentSet`** và mức truy cập **`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`**. Việc đọc item này buộc iOS xác thực phần cứng Secure Enclave cho Face ID / Touch ID hiện tại ở foreground; nếu sinh trắc học trên máy bị thêm/xóa/thay đổi, item tự động vô hiệu hóa để ngăn qua mặt.
   - **Cấm áp dụng `.biometryCurrentSet` đại trà:** **TUYỆT ĐỐI KHÔNG** gắn `.biometryCurrentSet` lên `session token`, bản băm PIN 6 số, hay bất kỳ dữ liệu nào mà `LiveActivityIntent` / `AppIntent` / Widget chạy nền ngoài app cần truy cập — vì các mục gắn sinh trắc sẽ đòi Face ID ở lớp dữ liệu nền hoặc trả lỗi khi hệ thống làm mới timeline ngoài foreground.
   - Yêu cầu thiết lập mã **PIN 6 số** dự phòng (băm bằng **PBKDF2-HMAC-SHA256 `600,000` vòng** + 16-byte random salt, lưu tách biệt trong Keychain không gắn `.biometryCurrentSet`). Sau 5 lần nhập sai PIN liên tiếp, áp dụng khóa tạm thời (cooldown 30 giây → tăng dần). Khi `.biometryCurrentSet` bị vô hiệu hóa do đổi Face ID/Touch ID, người dùng mở khóa bằng **mật khẩu tài khoản hoặc mã PIN 6 số** để hệ thống cấp lại item sinh trắc học mới.
4. **Privacy Mode trên Lock Screen:**
   - Cung cấp tùy chọn **Privacy Mode** trong Settings.
   - Khi **Tắt (Mặc định cho ôn thi):** Câu hỏi/đáp án hiển thị rõ ngay cả khi iPhone đang khóa để đúng công dụng đọc lướt không cần mở máy.
   - Khi **Bật:** Áp dụng `.privacySensitive()` của SwiftUI lên nội dung câu hỏi/đáp án trong Live Activity và Widget — iOS sẽ tự động che nội dung thành placeholder (hoặc chỉ hiện *"Còn X thẻ ôn thi"*) cho đến khi chủ máy nhìn vào máy để quét Face ID.
5. **Sao lưu Dữ liệu có Mã hóa (`Encrypted Backup`):**
   - Khi Export, người dùng nhập `passphrase` (tối thiểu 8 ký tự).
   - Tạo khóa AES-256 từ passphrase bằng **PBKDF2-HMAC-SHA256 `600,000` vòng** + 16-byte random salt, sau đó mã hóa payload JSON bằng **`CryptoKit.AES.GCM`**.
   - File xuất có phần mở rộng `.lockinbackup` kèm metadata phiên bản schema (`schemaVersion`, `salt`, `sealedBoxCombined`) để xác thực tính toàn vẹn (tag GCM) khi Import — nếu sai passphrase hoặc file bị chỉnh sửa, từ chối giải mã và giữ nguyên dữ liệu hiện có.
6. **Kiểm soát đầu vào & Quyền tối thiểu (Input Validation & Least Privilege):**
   - Giới hạn kích thước đầu vào cho Quick Import (ví dụ tối đa 500 dòng/lần, tối đa 500 ký tự/trường) và giới hạn dung lượng file `.lockinbackup` (ví dụ tối đa 10 MB) để tránh tràn bộ nhớ.
   - Chỉ yêu cầu quyền `UserNotifications`, `Face ID` và hướng dẫn bật `Live Activities` đúng lúc người dùng kích hoạt tính năng tương ứng trong Settings/Wizard.

---

## 6. Đồ họa, UI/UX & Quy tắc tài nguyên (Design & Assets Policy)

- **Ngôn ngữ thiết kế:** Minimalist / Flat Vector, tối ưu khả năng đọc nhanh (High Scannability), ưu tiên nền sạch, thẻ bo góc, thanh tiến độ rõ ràng, thao tác một tay trên màn hình dọc (**Portrait-only**).
- **Icon & Typography mặc định:**
  - Sử dụng 100% **SF Symbols** tích hợp sẵn trong iOS cho toàn bộ icon trong app, Live Activity và Widgets.
  - Sử dụng bộ font hệ thống **San Francisco** (`SF Pro`, `SF Pro Rounded`, `SF Mono`) hỗ trợ Dynamic Type.
  - Không nhúng ảnh, Lottie hay font bên thứ 3 trong Phase 1 để giữ app siêu nhẹ và không vướng bản quyền.
- **Quy tắc bắt buộc về Tài nguyên & Đồ họa ngoài (Asset Reporting Rule):**
  - Trong quá trình phát triển, nếu cần tìm kiếm hoặc thêm bất kỳ tài nguyên đồ họa/âm thanh/font ngoài nào (từ web, kho repo, MCP server, hay bộ icon bên thứ 3), Agent **BẮT BUỘC phải dừng lại và báo cáo cho người dùng** đầy đủ 4 thông tin trước khi tải hoặc đưa vào code:
    1. Tên tài nguyên & loại file.
    2. Nguồn gốc cụ thể (Repo / URL / công cụ MCP đã dùng).
    3. Giấy phép sử dụng (License: MIT, Apache-2.0, CC0, v.v.).
    4. Mục đích sử dụng trong app.
  - Chỉ được tích hợp sau khi người dùng xác nhận đồng ý.

---

## 7. Mô hình dữ liệu (SwiftData Schema)

Tất cả các `@Model` dưới đây được lưu trong `ModelContainer` gắn **Shared App Group (`group.com.lockin.shared`)** để cả `LockInApp` và `LockInWidgetsExtension` cùng truy cập nhất quán:

| Model / Entity | Các trường dữ liệu cốt lõi | Ghi chú & Quan hệ |
|---|---|---|
| **`UserProfile`** | `id: UUID` (Unique), `username: String` (Unique), `displayName: String`, `passwordHash: Data`, `passwordSalt: Data`, `isBiometricEnabled: Bool`, `createdAt: Date`, `lastLoginAt: Date?` | Hồ sơ người dùng cục bộ; cô lập dữ liệu qua `ownerUserId`. |
| **`StudyDeck`** | `id: UUID`, `ownerUserId: UUID`, `title: String`, `subjectTag: String`, `accentHex: String`, `examDate: Date?`, `dailyGoal: Int`, `createdAt: Date`, `updatedAt: Date` | Quan hệ `1-N` với `StudyCard` (`deleteRule: .cascade`). |
| **`StudyCard`** | `id: UUID`, `ownerUserId: UUID`, `deck: StudyDeck?`, `question: String`, `answer: String`, `hintOrNote: String`, `statusRaw: String` (`new` \| `learning` \| `mastered`), `reviewCount: Int`, `lastReviewedAt: Date?`, `sortOrder: Int` | Thuộc một `StudyDeck`; hỗ trợ mở rộng thêm trường `easeFactor`, `intervalDays`, `nextReviewDate` cho SM-2 ở Phase 2. |
| **`TaskItem`** | `id: UUID`, `ownerUserId: UUID`, `title: String`, `notes: String`, `dueDate: Date?`, `priorityRaw: Int` (`0: low`, `1: medium`, `2: high`), `isCompleted: Bool`, `completedAt: Date?`, `linkedDeckId: UUID?` | Quản lý công việc ôn tập cần làm trong `StudyHubTabView` (`TasksAndSchedule`) và Widget. |
| **`StudySchedule`** | `id: UUID`, `ownerUserId: UUID`, `deckId: UUID`, `title: String`, `hour: Int`, `minute: Int`, `weekdaysMask: Int` (bitmask T2–CN), `isEnabled: Bool`, `autoRotateTheme: Bool` | Lịch học real-time gắn với `UNCalendarNotificationTrigger`. |
| **`ThemePreference`** | `id: UUID`, `ownerUserId: UUID` (Unique), `activeThemeId: String`, `isShuffleEnabled: Bool`, `shufflePoolIds: [String]`, `rotateOnAppOpen: Bool`, `rotateOnShortcutTrigger: Bool`, `lockScreenFontScale: String`, `hideAnswerByDefault: Bool`, `privacyModeEnabled: Bool`, `showPopupOnOpen: Bool` | Lưu cấu hình theme, Shuffle Pool và tùy chọn hiển thị Lock Screen cho từng user. |
| **`DailyProgress`** | `id: UUID`, `ownerUserId: UUID`, `dateKey: String` (`yyyy-MM-dd`), `cardsReviewed: Int`, `cardsMastered: Int`, `tasksCompleted: Int`, `dailyTargetCount: Int`, `streakCount: Int` | Phục vụ Progress Bar, Streak và Widget vòng tròn tiến độ. |

---

## 8. Chiến lược Build, CI/CD & Phân phối (Windows Dev → iPhone)

Vì môi trường phát triển chính trên **Windows**, mọi bước biên dịch Xcode sẽ chạy tự động trên **GitHub Actions (`macos-latest`)**:

### 8.1. Luồng Phase 1 — Miễn phí \$0 (Mặc định)
1. Lập trình, chỉnh sửa code Swift/SwiftUI và cấu hình `project.yml` trên Windows, push lên GitHub.
2. GitHub Actions workflow `.github/workflows/ios-free-ipa.yml` chạy tự động khi push hoặc kích hoạt thủ công:
   - Cài đặt `xcodegen` (qua Homebrew).
   - Chạy `xcodegen generate` tạo `LockIn.xcodeproj`.
   - Chạy Unit Tests: `xcodebuild test -project LockIn.xcodeproj -scheme LockInApp -destination 'platform=iOS Simulator,name=iPhone 15'` (hoặc simulator khả dụng mới nhất trên runner).
   - Build bản Release không ký (`CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`).
   - Đóng gói `LockInApp.app` (kèm `PlugIns/LockInWidgetsExtension.appex`) vào thư mục `Payload/` và nén thành **`LockIn-unsigned.ipa`**.
   - Xuất file `.ipa` lên **GitHub Actions Artifacts**.
3. Người dùng tải `LockIn-unsigned.ipa` trên Windows và cài lên iPhone bằng **Sideloadly**, **AltStore**, hoặc **SideStore** với Apple ID miễn phí (tự động gia hạn mỗi 7 ngày).

### 8.2. Luồng Phase 2 — Nâng cấp TestFlight (Khi có Apple Developer \$99/năm)
- Bổ sung workflow `.github/workflows/ios-testflight.yml`:
  - Sử dụng Apple Distribution Certificate (`.p12`), 2 Provisioning Profiles (cho `LockInApp` và `LockInWidgetsExtension` có App Group capability), và App Store Connect API Key lưu trong GitHub Secrets.
  - Chạy `xcodebuild archive` + `xcodebuild -exportArchive` (ExportOptions `app-store-connect`) và upload trực tiếp lên **TestFlight** cho bạn bè cài đặt với hạn 90 ngày/bản build.

---

## 9. Tiêu chí nghiệm thu MVP (Acceptance Criteria)

Phase 1 được coi là hoàn thành khi đạt **100%** các tiêu chí sau:

- [ ] **Cấu trúc & Build CI:** `project.yml` sinh thành công `LockIn.xcodeproj` qua `xcodegen` (biên dịch `Shared/**` ở cả `LockInApp` và `LockInWidgetsExtension`); GitHub Actions chạy pass toàn bộ **8 bộ test trong `LockInTests`** (bao gồm Auth và Scheduler) và xuất ra file `LockIn-unsigned.ipa` hợp lệ (chứa đủ `LockInWidgetsExtension.appex`).
- [ ] **Đăng nhập & Bảo mật Cục bộ:**
  - Tạo mới và đăng nhập được ít nhất 2 user cục bộ trên cùng thiết bị; dữ liệu bộ đề, task, progress, theme của user A hoàn toàn tách biệt khỏi user B.
  - Mật khẩu, PIN 6 số và khóa backup đều dùng **PBKDF2-HMAC-SHA256 (`600,000` vòng)** + random salt; phiên lưu trong Keychain; mở khóa sinh trắc học được bảo vệ ở tầng Keychain bằng **`.biometryCurrentSet`** + `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` (fallback an toàn bằng PIN/password khi đổi sinh trắc học).
  - Export ra file `.lockinbackup` mã hóa AES-GCM và Import khôi phục thành công khi nhập đúng passphrase; từ chối giải mã khi sai passphrase.
- [ ] **Tab 1 (`StudyHubTabView`):**
  - Tạo/sửa/xóa được bộ đề, thẻ ôn và task; Quick Import tách và lưu đúng danh sách thẻ từ văn bản `Câu hỏi | Đáp án`.
  - Lên lịch real-time kích hoạt đúng Local Notification; thanh Progress Bar và Streak cập nhật chính xác khi hoàn thành thẻ hoặc task.
- [ ] **Tab 2 (`ThemesTabView`):**
  - Chuyển đổi mượt giữa 6 theme cài sẵn; Shuffle Pool xoay ngẫu nhiên giữa các theme đã chọn khi mở app hoặc khi kích hoạt `RotateLockInThemeIntent` qua các trigger hợp lệ của iOS Shortcuts (*Giờ trong ngày / Focus Mode / Mở-Đóng app / Sạc*).
  - Hiển thị Pop-up nhắc việc khi mở app nếu còn task hoặc thẻ đến hạn.
- [ ] **Tab 3 (`SettingsTabView`) & `LockScreenModule`:**
  - Setup Wizard hiển thị đúng trạng thái quyền Live Activities, Notifications và hướng dẫn cài iOS Shortcut (theo các trigger hợp lệ của iOS); hỗ trợ xuất/lưu ảnh tóm tắt bài ôn vào Photos để đặt hình nền thủ công.
  - Bật Live Activity từ trong app (`Activity.request` khi foreground) hiển thị thẻ rõ nét trên Lock Screen; kiểm thử **cả trước và sau xác thực thiết bị**: khi máy còn khóa, chạm nút trên Live Activity/Widget sẽ yêu cầu xác thực (Face ID / Touch ID / mật mã) theo chính sách iOS; sau khi xác thực, 4 nút `LiveActivityIntent` (`Trước` / `Lật đáp án` / `Đã thuộc` / `Tiếp`, `openAppWhenRun = false`) cập nhật tức thì trên Lock Screen qua `Shared/ExtensionCore/` mà **không nhảy vào app**, đồng thời đồng bộ hai chiều với `LockInApp` cả khi ở foreground (qua Darwin Notification) lẫn khi trở lại từ background (`scenePhase == .active`).
  - `StartStudyActivityIntent` đặt `openAppWhenRun = true` mở app lên foreground để khởi động lại phiên mới sau khi hết hạn 8–12 giờ.
  - Bật Privacy Mode ẩn nội dung thẻ khi chưa quét Face ID; tắt Privacy Mode hiển thị rõ nội dung để ôn trực tiếp.
  - Lock Screen Widgets (`accessoryCircular`, `accessoryRectangular`) hiển thị đúng tiến độ/task và tương tác được.
- [ ] **Tuân thủ Đồ họa & Quy tắc Tài nguyên:**
  - Giao diện khóa hướng dọc (Portrait-only), dùng SF Symbols mặc định, không có tài nguyên ngoài chưa được báo cáo và xác nhận.
