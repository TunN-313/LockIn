// AppModuleProtocols.swift — Định nghĩa toàn bộ Domain DTOs, Domain Errors và Protocols cho 8 Backend modules.
// Là ranh giới giao tiếp duy nhất từ Frontend/ViewModels xuống Backend/, tách biệt hoàn toàn khỏi SwiftData và Keychain.

import Foundation

// MARK: - Domain DTOs (Sendable, thuần Foundation)

public struct UserProfileDTO: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let username: String
    public let displayName: String
    public let isBiometricEnabled: Bool
    public let createdAt: Date
    public let lastLoginAt: Date?

    public init(
        id: UUID,
        username: String,
        displayName: String,
        isBiometricEnabled: Bool,
        createdAt: Date,
        lastLoginAt: Date?
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.isBiometricEnabled = isBiometricEnabled
        self.createdAt = createdAt
        self.lastLoginAt = lastLoginAt
    }
}

public struct StudyDeckDTO: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let ownerUserId: UUID
    public let title: String
    public let subjectTag: String
    public let accentHex: String
    public let examDate: Date?
    public let dailyGoal: Int
    public let totalCards: Int
    public let masteredCards: Int
    public let createdAt: Date
    public let updatedAt: Date

    public var masteryRatio: Double {
        guard totalCards > 0 else { return 0 }
        return Double(masteredCards) / Double(totalCards)
    }

    public init(
        id: UUID,
        ownerUserId: UUID,
        title: String,
        subjectTag: String,
        accentHex: String,
        examDate: Date?,
        dailyGoal: Int,
        totalCards: Int,
        masteredCards: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.ownerUserId = ownerUserId
        self.title = title
        self.subjectTag = subjectTag
        self.accentHex = accentHex
        self.examDate = examDate
        self.dailyGoal = dailyGoal
        self.totalCards = totalCards
        self.masteredCards = masteredCards
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct StudyCardDTO: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let ownerUserId: UUID
    public let deckId: UUID
    public let question: String
    public let answer: String
    public let hintOrNote: String
    public let status: StudyCardStatus
    public let reviewCount: Int
    public let lastReviewedAt: Date?
    public let sortOrder: Int

    public init(
        id: UUID,
        ownerUserId: UUID,
        deckId: UUID,
        question: String,
        answer: String,
        hintOrNote: String,
        status: StudyCardStatus,
        reviewCount: Int,
        lastReviewedAt: Date?,
        sortOrder: Int
    ) {
        self.id = id
        self.ownerUserId = ownerUserId
        self.deckId = deckId
        self.question = question
        self.answer = answer
        self.hintOrNote = hintOrNote
        self.status = status
        self.reviewCount = reviewCount
        self.lastReviewedAt = lastReviewedAt
        self.sortOrder = sortOrder
    }
}

public struct TaskItemDTO: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let ownerUserId: UUID
    public let title: String
    public let notes: String
    public let dueDate: Date?
    public let priority: TaskPriority
    public let isCompleted: Bool
    public let completedAt: Date?
    public let linkedDeckId: UUID?

    public init(
        id: UUID,
        ownerUserId: UUID,
        title: String,
        notes: String,
        dueDate: Date?,
        priority: TaskPriority,
        isCompleted: Bool,
        completedAt: Date?,
        linkedDeckId: UUID?
    ) {
        self.id = id
        self.ownerUserId = ownerUserId
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.linkedDeckId = linkedDeckId
    }
}

public struct StudyScheduleDTO: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let ownerUserId: UUID
    public let deckId: UUID
    public let title: String
    public let hour: Int
    public let minute: Int
    public let weekdaysMask: Int
    public let isEnabled: Bool
    public let autoRotateTheme: Bool

    public init(
        id: UUID,
        ownerUserId: UUID,
        deckId: UUID,
        title: String,
        hour: Int,
        minute: Int,
        weekdaysMask: Int,
        isEnabled: Bool,
        autoRotateTheme: Bool
    ) {
        self.id = id
        self.ownerUserId = ownerUserId
        self.deckId = deckId
        self.title = title
        self.hour = hour
        self.minute = minute
        self.weekdaysMask = weekdaysMask
        self.isEnabled = isEnabled
        self.autoRotateTheme = autoRotateTheme
    }
}

public struct ThemePreferenceDTO: Equatable, Codable, Sendable {
    public let id: UUID
    public let ownerUserId: UUID
    public let activeThemeId: String
    public let isShuffleEnabled: Bool
    public let shufflePoolIds: [String]
    public let rotateOnAppOpen: Bool
    public let rotateOnShortcutTrigger: Bool
    public let lockScreenFontScale: LockScreenFontScale
    public let hideAnswerByDefault: Bool
    public let privacyModeEnabled: Bool
    public let showPopupOnOpen: Bool

    public init(
        id: UUID,
        ownerUserId: UUID,
        activeThemeId: String,
        isShuffleEnabled: Bool,
        shufflePoolIds: [String],
        rotateOnAppOpen: Bool,
        rotateOnShortcutTrigger: Bool,
        lockScreenFontScale: LockScreenFontScale,
        hideAnswerByDefault: Bool,
        privacyModeEnabled: Bool,
        showPopupOnOpen: Bool
    ) {
        self.id = id
        self.ownerUserId = ownerUserId
        self.activeThemeId = activeThemeId
        self.isShuffleEnabled = isShuffleEnabled
        self.shufflePoolIds = shufflePoolIds
        self.rotateOnAppOpen = rotateOnAppOpen
        self.rotateOnShortcutTrigger = rotateOnShortcutTrigger
        self.lockScreenFontScale = lockScreenFontScale
        self.hideAnswerByDefault = hideAnswerByDefault
        self.privacyModeEnabled = privacyModeEnabled
        self.showPopupOnOpen = showPopupOnOpen
    }
}

public struct DailyProgressDTO: Equatable, Codable, Sendable {
    public let dateKey: String
    public let cardsReviewed: Int
    public let cardsMastered: Int
    public let tasksCompleted: Int
    public let dailyTargetCount: Int
    public let streakCount: Int

    public var completionRatio: Double {
        guard dailyTargetCount > 0 else { return 0 }
        let completedUnits = cardsReviewed + tasksCompleted
        return min(1.0, Double(completedUnits) / Double(dailyTargetCount))
    }

    public init(
        dateKey: String,
        cardsReviewed: Int,
        cardsMastered: Int,
        tasksCompleted: Int,
        dailyTargetCount: Int,
        streakCount: Int
    ) {
        self.dateKey = dateKey
        self.cardsReviewed = cardsReviewed
        self.cardsMastered = cardsMastered
        self.tasksCompleted = tasksCompleted
        self.dailyTargetCount = dailyTargetCount
        self.streakCount = streakCount
    }
}

public struct QuickImportCandidate: Equatable, Sendable {
    public let question: String
    public let answer: String
    public let hintOrNote: String

    public init(question: String, answer: String, hintOrNote: String = "") {
        self.question = question
        self.answer = answer
        self.hintOrNote = hintOrNote
    }
}

public struct QuickImportLineError: Identifiable, Equatable, Sendable {
    public let id: Int
    public let lineNumber: Int
    public let rawLine: String
    public let reason: String

    public init(lineNumber: Int, rawLine: String, reason: String) {
        self.id = lineNumber
        self.lineNumber = lineNumber
        self.rawLine = rawLine
        self.reason = reason
    }
}

public struct QuickImportPreview: Equatable, Sendable {
    public let candidates: [QuickImportCandidate]
    public let errors: [QuickImportLineError]
    public let truncatedOverLimit: Bool

    public init(
        candidates: [QuickImportCandidate],
        errors: [QuickImportLineError],
        truncatedOverLimit: Bool
    ) {
        self.candidates = candidates
        self.errors = errors
        self.truncatedOverLimit = truncatedOverLimit
    }
}

public struct PendingReminderSummary: Equatable, Sendable {
    public let overdueTasksCount: Int
    public let dueTodayTasksCount: Int
    public let remainingDailyGoalCount: Int
    public let suggestedDeckId: UUID?
    public let suggestedDeckTitle: String?

    public var hasPendingItems: Bool {
        overdueTasksCount > 0 || dueTodayTasksCount > 0 || remainingDailyGoalCount > 0
    }

    public init(
        overdueTasksCount: Int,
        dueTodayTasksCount: Int,
        remainingDailyGoalCount: Int,
        suggestedDeckId: UUID?,
        suggestedDeckTitle: String?
    ) {
        self.overdueTasksCount = overdueTasksCount
        self.dueTodayTasksCount = dueTodayTasksCount
        self.remainingDailyGoalCount = remainingDailyGoalCount
        self.suggestedDeckId = suggestedDeckId
        self.suggestedDeckTitle = suggestedDeckTitle
    }
}

public struct LockScreenBridgeStatus: Equatable, Sendable {
    public let areLiveActivitiesEnabled: Bool
    public let isNotificationAuthorized: Bool
    public let isAppGroupAvailable: Bool
    public let isLiveActivityActive: Bool
    public let activeDeckId: UUID?
    public let activeDeckTitle: String?

    public init(
        areLiveActivitiesEnabled: Bool,
        isNotificationAuthorized: Bool,
        isAppGroupAvailable: Bool,
        isLiveActivityActive: Bool,
        activeDeckId: UUID?,
        activeDeckTitle: String?
    ) {
        self.areLiveActivitiesEnabled = areLiveActivitiesEnabled
        self.isNotificationAuthorized = isNotificationAuthorized
        self.isAppGroupAvailable = isAppGroupAvailable
        self.isLiveActivityActive = isLiveActivityActive
        self.activeDeckId = activeDeckId
        self.activeDeckTitle = activeDeckTitle
    }
}

public enum BackupRestoreMode: String, Codable, CaseIterable, Sendable {
    case merge
    case overwrite
}

public enum ReminderNotificationFrequency: String, Codable, CaseIterable, Sendable {
    case off
    case daily
    case twiceDaily
    case every4Hours

    public var displayName: String {
        switch self {
        case .off:
            return "Tắt thông báo định kỳ"
        case .daily:
            return "Mỗi ngày 1 lần (20:00)"
        case .twiceDaily:
            return "2 lần mỗi ngày (09:00 & 20:00)"
        case .every4Hours:
            return "Mỗi 4 giờ (08:00–20:00)"
        }
    }

    public var scheduledHours: [Int] {
        switch self {
        case .off:
            return []
        case .daily:
            return [20]
        case .twiceDaily:
            return [9, 20]
        case .every4Hours:
            return [8, 12, 16, 20]
        }
    }
}

public struct ScheduledSessionActivationResult: Equatable, Sendable {
    public let schedule: StudyScheduleDTO
    public let prioritizedDeckId: UUID
    public let prioritizedDeckTitle: String
    public let didRotateTheme: Bool
    public let activeThemeId: String

    public init(
        schedule: StudyScheduleDTO,
        prioritizedDeckId: UUID,
        prioritizedDeckTitle: String,
        didRotateTheme: Bool,
        activeThemeId: String
    ) {
        self.schedule = schedule
        self.prioritizedDeckId = prioritizedDeckId
        self.prioritizedDeckTitle = prioritizedDeckTitle
        self.didRotateTheme = didRotateTheme
        self.activeThemeId = activeThemeId
    }
}

public struct WallpaperRenderPayload: Equatable, Sendable {
    public let deckTitle: String
    public let pngData: Data

    public init(deckTitle: String, pngData: Data) {
        self.deckTitle = deckTitle
        self.pngData = pngData
    }
}

public enum LockInDomainError: Error, LocalizedError, Equatable, Sendable {
    case unauthenticated
    case invalidUsername(String)
    case invalidPassword(String)
    case duplicateUsername
    case invalidCredentials
    case biometricUnavailable
    case biometricInvalidatedRequiresFallback
    case pinLockedCooldown(remainingSeconds: Int)
    case pinCooldownStateUnverifiableRequiresPassword
    case invalidPinFormat
    case validationFailed(String)
    case entityNotFound
    case backupCorruptedOrWrongPassphrase
    case backupExceedsMaxSize
    case liveActivitiesDisabled
    case payloadExceedsLimit(bytes: Int)
    case persistenceFailure(String)

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Bạn cần đăng nhập để thực hiện thao tác này."
        case .invalidUsername(let reason), .invalidPassword(let reason), .validationFailed(let reason):
            return reason
        case .duplicateUsername:
            return "Tên đăng nhập đã tồn tại trên thiết bị."
        case .invalidCredentials:
            return "Tên đăng nhập hoặc mật khẩu không chính xác."
        case .biometricUnavailable:
            return "Face ID / Touch ID hiện không khả dụng trên thiết bị."
        case .biometricInvalidatedRequiresFallback:
            return "Dữ liệu sinh trắc học đã thay đổi. Vui lòng nhập mật khẩu hoặc mã PIN 6 số để mở khóa."
        case .pinLockedCooldown(let seconds):
            return "Nhập sai PIN quá nhiều lần. Vui lòng thử lại sau \(seconds) giây."
        case .pinCooldownStateUnverifiableRequiresPassword:
            return "Không thể xác minh trạng thái bảo vệ mã PIN. Vui lòng xác thực bằng mật khẩu tài khoản để khôi phục an toàn."
        case .invalidPinFormat:
            return "Mã PIN dự phòng phải gồm đúng 6 chữ số."
        case .entityNotFound:
            return "Không tìm thấy dữ liệu được yêu cầu."
        case .backupCorruptedOrWrongPassphrase:
            return "Sai mật khẩu giải mã hoặc tệp sao lưu không hợp lệ."
        case .backupExceedsMaxSize:
            return "Tệp sao lưu vượt quá dung lượng cho phép (10 MB)."
        case .liveActivitiesDisabled:
            return "Live Activities đang tắt trong Cài đặt iOS."
        case .payloadExceedsLimit(let bytes):
            return "Dữ liệu Live Activity (\(bytes) bytes) vượt giới hạn 4KB."
        case .persistenceFailure(let detail):
            return "Lỗi lưu trữ dữ liệu: \(detail)"
        }
    }
}

// MARK: - Module Protocols

public protocol AuthModuleProtocol: Sendable {
    func register(username: String, displayName: String, password: String) async throws -> UserProfileDTO
    func login(username: String, password: String) async throws -> UserProfileDTO
    func logout() async throws
    func currentActiveUser() async -> UserProfileDTO?
    func listProfiles() async throws -> [UserProfileDTO]
    func switchProfile(userId: UUID, password: String) async throws -> UserProfileDTO
}

/// Quản lý bảo mật Keychain & App Lock.
/// Lưu ý: .biometryCurrentSet CHỈ dùng cho khóa bảo vệ App Lock ở foreground, tuyệt đối không gắn lên session token hay dữ liệu Extension.
public protocol SecurityModuleProtocol: Sendable {
    func isAppLockRequired() async -> Bool
    func setFallbackPin(_ pin: String) async throws
    func hasFallbackPin() async -> Bool
    func verifyFallbackPin(_ pin: String) async throws -> Bool
    func remainingPinCooldownSeconds() async -> Int
    func enableBiometricLock(reason: String) async throws
    func disableBiometricLock() async throws
    func unlockWithBiometric(reason: String) async throws
    func recoverBiometricLockAfterInvalidation(usingPassword password: String) async throws
    func recoverBiometricLockAfterInvalidation(usingPin pin: String) async throws
    func unlockAndResetPinCooldown(usingPassword password: String) async throws
}

public protocol StudyModuleProtocol: Sendable {
    func fetchDecks() async throws -> [StudyDeckDTO]
    func createDeck(title: String, subjectTag: String, accentHex: String, examDate: Date?, dailyGoal: Int) async throws -> StudyDeckDTO
    func updateDeck(deckId: UUID, title: String, subjectTag: String, accentHex: String, examDate: Date?, dailyGoal: Int) async throws -> StudyDeckDTO
    func deleteDeck(deckId: UUID) async throws

    func fetchCards(deckId: UUID) async throws -> [StudyCardDTO]
    func upsertCard(cardId: UUID?, deckId: UUID, question: String, answer: String, hintOrNote: String, status: StudyCardStatus) async throws -> StudyCardDTO
    func deleteCard(cardId: UUID) async throws
    func previewQuickImport(rawText: String) -> QuickImportPreview
    func commitQuickImport(deckId: UUID, candidates: [QuickImportCandidate]) async throws -> [StudyCardDTO]

    func fetchTasks() async throws -> [TaskItemDTO]
    func createTask(title: String, notes: String, dueDate: Date?, priority: TaskPriority, linkedDeckId: UUID?) async throws -> TaskItemDTO
    func updateTask(taskId: UUID, title: String, notes: String, dueDate: Date?, priority: TaskPriority, linkedDeckId: UUID?) async throws -> TaskItemDTO
    func toggleTaskCompletion(taskId: UUID) async throws -> TaskItemDTO
    func deleteTask(taskId: UUID) async throws

    func fetchTodayProgress() async throws -> DailyProgressDTO
    func fetchPendingReminderSummary() async throws -> PendingReminderSummary
}

public protocol SchedulerModuleProtocol: Sendable {
    func fetchSchedules() async throws -> [StudyScheduleDTO]
    func saveSchedule(scheduleId: UUID?, deckId: UUID, title: String, hour: Int, minute: Int, weekdaysMask: Int, isEnabled: Bool, autoRotateTheme: Bool) async throws -> StudyScheduleDTO
    func deleteSchedule(scheduleId: UUID) async throws
    func nextScheduledDate(for schedule: StudyScheduleDTO, after referenceDate: Date) -> Date?
    func requestNotificationPermission() async throws -> Bool
    func syncLocalNotifications() async throws
    func fetchReminderFrequency() async throws -> ReminderNotificationFrequency
    func updateReminderFrequency(_ frequency: ReminderNotificationFrequency) async throws -> ReminderNotificationFrequency
    func scheduleSnoozeReminder(afterMinutes: Int, suggestedDeckTitle: String?) async throws -> Date
    func activeOrDueSchedule(at referenceDate: Date) async throws -> StudyScheduleDTO?
    func activateScheduledSession(scheduleId: UUID) async throws -> ScheduledSessionActivationResult
    func applyDueScheduleIfNeeded(at referenceDate: Date) async throws -> ScheduledSessionActivationResult?
}

public protocol ThemeModuleProtocol: Sendable {
    func builtInThemes() -> [ThemePalette]
    func fetchPreference() async throws -> ThemePreferenceDTO
    func selectTheme(themeId: String) async throws -> ThemePreferenceDTO
    func updateShuffleConfiguration(isEnabled: Bool, poolIds: [String], rotateOnAppOpen: Bool, rotateOnShortcutTrigger: Bool) async throws -> ThemePreferenceDTO
    func updateLockScreenDisplayOptions(fontScale: LockScreenFontScale, hideAnswerByDefault: Bool, privacyModeEnabled: Bool, showPopupOnOpen: Bool) async throws -> ThemePreferenceDTO
    func rotateThemeIfNeeded(triggerOnAppOpen: Bool) async throws -> ThemePalette
    func rotateThemeForScheduledSession() async throws -> ThemePalette
}

public protocol LockScreenModuleProtocol: Sendable {
    func checkBridgeStatus() async -> LockScreenBridgeStatus
    func startOrUpdateLiveActivity(forDeckId deckId: UUID) async throws
    func stopActiveLiveActivity() async
    func syncSnapshotFromStore() async throws
    /// Render ảnh PNG tóm tắt bài ôn (3–5 dòng) theo theme để lưu vào Photos đặt hình nền thủ công.
    func renderStudyWallpaperPNG(deckId: UUID?, maxLines: Int) async throws -> WallpaperRenderPayload
    func requestNotificationPermissionForWizard() async throws -> Bool
    func saveWallpaperPNGToPhotos(_ pngData: Data) async throws
}

public protocol BackupModuleProtocol: Sendable {
    func exportEncryptedBackup(passphrase: String) async throws -> Data
    func readBoundedBackupFile(at url: URL) throws -> Data
    func importEncryptedBackup(_ data: Data, passphrase: String, mode: BackupRestoreMode) async throws
}

public protocol StorageMaintenanceProtocol: Sendable {
    func purgeCurrentUserStudyData() async throws
}

// MARK: - Phase 2 Extension Points (Đặt sẵn theo mục 3 Tab 1 của spec.md)

public protocol SchedulingEngineProtocol: Sendable {
    func nextReviewDate(for card: StudyCardDTO, qualityScore: Int, from date: Date) -> Date
}

public protocol StudyTimerProtocol: Sendable {
    func startFocusInterval(minutes: Int) async
    func stopFocusInterval() async
}

public protocol CardImporterProtocol: Sendable {
    func extractCandidates(from rawData: Data) async throws -> [QuickImportCandidate]
}
