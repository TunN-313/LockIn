// StudyScheduleService.swift — Quản lý lịch học real-time (StudySchedule) cô lập theo ownerUserId.
// Triển khai SchedulerModuleProtocol, tính mốc thời gian học kế tiếp và đồng bộ LocalNotificationService.

import ActivityKit
import Foundation
import SwiftData
import WidgetKit

public final class SchedulerPreferencesFileStore: @unchecked Sendable {
    private struct StoredPreferencesPayload: Codable {
        var reminderFrequencyByUserId: [String: ReminderNotificationFrequency] = [:]
        var appliedSchedulesByUserAndDate: [String: [String]] = [:]
    }

    private let lock = NSLock()
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directoryURL: URL, fileName: String = "scheduler_preferences.json") {
        self.fileURL = directoryURL.appendingPathComponent(fileName)
    }

    public func reminderFrequency(for userId: UUID) -> ReminderNotificationFrequency {
        lock.lock()
        defer { lock.unlock() }
        return readPayloadLocked().reminderFrequencyByUserId[userId.uuidString] ?? .off
    }

    public func setReminderFrequency(_ frequency: ReminderNotificationFrequency, for userId: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        var payload = readPayloadLocked()
        payload.reminderFrequencyByUserId[userId.uuidString] = frequency
        try writePayloadLocked(payload)
    }

    public func hasAppliedSchedule(_ scheduleId: UUID, for userId: UUID, onDateKey dateKey: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(userId.uuidString)|\(dateKey)"
        let applied = readPayloadLocked().appliedSchedulesByUserAndDate[key] ?? []
        return applied.contains(scheduleId.uuidString)
    }

    public func markScheduleApplied(_ scheduleId: UUID, for userId: UUID, onDateKey dateKey: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var payload = readPayloadLocked()
        let userPrefix = "\(userId.uuidString)|"
        let currentKey = "\(userPrefix)\(dateKey)"
        var existing = payload.appliedSchedulesByUserAndDate[currentKey] ?? []
        if !existing.contains(scheduleId.uuidString) {
            existing.append(scheduleId.uuidString)
            payload.appliedSchedulesByUserAndDate[currentKey] = existing
        }
        // Giữ tối đa 2 khóa ngày gần nhất cho mỗi hồ sơ để không làm mất khóa ngày hôm qua khi qua nửa đêm (vd: 23:30 -> 00:15).
        let staleKeys = payload.appliedSchedulesByUserAndDate.keys
            .filter { $0.hasPrefix(userPrefix) }
            .sorted(by: >)
            .dropFirst(2)
        for staleKey in staleKeys {
            payload.appliedSchedulesByUserAndDate.removeValue(forKey: staleKey)
        }
        try writePayloadLocked(payload)
    }

    private func readPayloadLocked() -> StoredPreferencesPayload {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode(StoredPreferencesPayload.self, from: data) else {
            return StoredPreferencesPayload()
        }
        return decoded
    }

    private func writePayloadLocked(_ payload: StoredPreferencesPayload) throws {
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: [.atomic])
    }
}

public final class StudyScheduleService: SchedulerModuleProtocol, @unchecked Sendable {
    private let studyStore: SwiftDataStudyStore
    private let isolationGuard: UserDataIsolationGuardProtocol
    private let notificationService: LocalNotificationServiceProtocol
    private let snapshotStore: AppGroupSnapshotStoreProtocol
    private let themeModule: ThemeModuleProtocol
    private let syncEventBus: SyncEventBus
    private let preferencesStore: SchedulerPreferencesFileStore
    private let calendar: Calendar

    public init(
        studyStore: SwiftDataStudyStore,
        isolationGuard: UserDataIsolationGuardProtocol,
        notificationService: LocalNotificationServiceProtocol,
        snapshotStore: AppGroupSnapshotStoreProtocol,
        themeModule: ThemeModuleProtocol,
        syncEventBus: SyncEventBus,
        preferencesStore: SchedulerPreferencesFileStore,
        calendar: Calendar = .current
    ) {
        self.studyStore = studyStore
        self.isolationGuard = isolationGuard
        self.notificationService = notificationService
        self.snapshotStore = snapshotStore
        self.themeModule = themeModule
        self.syncEventBus = syncEventBus
        self.preferencesStore = preferencesStore
        self.calendar = calendar
    }

    public func fetchSchedules() async throws -> [StudyScheduleDTO] {
        let userId = try isolationGuard.requireActiveUserId()
        return try await studyStore.perform { context in
            let uid = userId
            let descriptor = FetchDescriptor<StudySchedule>(
                predicate: #Predicate<StudySchedule> { $0.ownerUserId == uid }
            )
            return try context.fetch(descriptor)
                .sorted { ($0.hour, $0.minute, $0.id.uuidString) < ($1.hour, $1.minute, $1.id.uuidString) }
                .map(Self.toDTO)
        }
    }

    public func saveSchedule(
        scheduleId: UUID?,
        deckId: UUID,
        title: String,
        hour: Int,
        minute: Int,
        weekdaysMask: Int,
        isEnabled: Bool,
        autoRotateTheme: Bool
    ) async throws -> StudyScheduleDTO {
        let userId = try isolationGuard.requireActiveUserId()
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, cleanTitle.count <= AppConstants.maxFieldCharacterLength else {
            throw LockInDomainError.validationFailed("Tên lịch ôn tập phải từ 1 đến \(AppConstants.maxFieldCharacterLength) ký tự.")
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw LockInDomainError.validationFailed("Giờ hoặc phút của lịch học không hợp lệ.")
        }
        guard (weekdaysMask & 0b1111111) != 0 else {
            throw LockInDomainError.validationFailed("Vui lòng chọn ít nhất một ngày lặp lại trong tuần.")
        }

        let savedDTO = try await studyStore.perform { context in
            let uid = userId
            let targetDeckId = deckId
            let deckExists = try !context.fetch(
                FetchDescriptor<StudyDeck>(predicate: #Predicate<StudyDeck> { $0.id == targetDeckId && $0.ownerUserId == uid })
            ).isEmpty
            guard deckExists else {
                throw LockInDomainError.entityNotFound
            }

            let targetSchedule: StudySchedule
            if let existingId = scheduleId {
                let sid = existingId
                guard let found = try context.fetch(
                    FetchDescriptor<StudySchedule>(predicate: #Predicate<StudySchedule> { $0.id == sid && $0.ownerUserId == uid })
                ).first else {
                    throw LockInDomainError.entityNotFound
                }
                found.deckId = deckId
                found.title = cleanTitle
                found.hour = hour
                found.minute = minute
                found.weekdaysMask = weekdaysMask & 0b1111111
                found.isEnabled = isEnabled
                found.autoRotateTheme = autoRotateTheme
                targetSchedule = found
            } else {
                let created = StudySchedule(
                    ownerUserId: uid,
                    deckId: deckId,
                    title: cleanTitle,
                    hour: hour,
                    minute: minute,
                    weekdaysMask: weekdaysMask & 0b1111111,
                    isEnabled: isEnabled,
                    autoRotateTheme: autoRotateTheme
                )
                context.insert(created)
                targetSchedule = created
            }
            try context.save()
            return Self.toDTO(targetSchedule)
        }

        try await syncLocalNotifications()
        return savedDTO
    }

    public func deleteSchedule(scheduleId: UUID) async throws {
        let userId = try isolationGuard.requireActiveUserId()
        try await studyStore.perform { context in
            let uid = userId
            let sid = scheduleId
            guard let found = try context.fetch(
                FetchDescriptor<StudySchedule>(predicate: #Predicate<StudySchedule> { $0.id == sid && $0.ownerUserId == uid })
            ).first else {
                throw LockInDomainError.entityNotFound
            }
            context.delete(found)
            try context.save()
        }
        try await syncLocalNotifications()
    }

    /// Tính thời điểm tiếp theo lịch sẽ kích hoạt sau `referenceDate` dựa trên `weekdaysMask` (bit 0 = Chủ Nhật ... bit 6 = Thứ Bảy).
    public func nextScheduledDate(for schedule: StudyScheduleDTO, after referenceDate: Date) -> Date? {
        let activeMask = schedule.weekdaysMask & 0b1111111
        guard schedule.isEnabled, activeMask != 0 else { return nil }
        guard (0...23).contains(schedule.hour), (0...59).contains(schedule.minute) else { return nil }

        let startOfRefDay = calendar.startOfDay(for: referenceDate)
        for dayOffset in 0...7 {
            guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: startOfRefDay) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: candidateDay)
            let bit = 1 << (weekday - 1)
            guard (activeMask & bit) != 0 else { continue }

            guard let candidateDate = calendar.date(
                bySettingHour: schedule.hour,
                minute: schedule.minute,
                second: 0,
                of: candidateDay
            ) else {
                continue
            }

            if candidateDate > referenceDate {
                return candidateDate
            }
        }
        return nil
    }

    public func requestNotificationPermission() async throws -> Bool {
        let granted = try await notificationService.requestAuthorization()
        if granted {
            try await syncLocalNotifications()
        }
        return granted
    }

    public func syncLocalNotifications() async throws {
        let userId = try isolationGuard.requireActiveUserId()
        let payload: (schedules: [StudyScheduleDTO], deckTitles: [UUID: String]) = try await studyStore.perform { context in
            let uid = userId
            let schedules = try context.fetch(
                FetchDescriptor<StudySchedule>(predicate: #Predicate<StudySchedule> { $0.ownerUserId == uid })
            ).map(Self.toDTO)

            let decks = try context.fetch(
                FetchDescriptor<StudyDeck>(predicate: #Predicate<StudyDeck> { $0.ownerUserId == uid })
            )
            var titles: [UUID: String] = [:]
            for deck in decks {
                titles[deck.id] = deck.title
            }
            return (schedules, titles)
        }

        let reminderFrequency = preferencesStore.reminderFrequency(for: userId)
        try await notificationService.resyncNotifications(
            forUserId: userId,
            schedules: payload.schedules,
            deckTitlesById: payload.deckTitles,
            reminderFrequency: reminderFrequency
        )
    }

    public func fetchReminderFrequency() async throws -> ReminderNotificationFrequency {
        let userId = try isolationGuard.requireActiveUserId()
        return preferencesStore.reminderFrequency(for: userId)
    }

    public func updateReminderFrequency(_ frequency: ReminderNotificationFrequency) async throws -> ReminderNotificationFrequency {
        let userId = try isolationGuard.requireActiveUserId()
        if frequency != .off {
            var allowed = await notificationService.isAuthorized()
            if !allowed {
                allowed = try await notificationService.requestAuthorization()
            }
            guard allowed else {
                throw LockInDomainError.validationFailed("Chưa được cấp quyền Thông báo trong Cài đặt iOS để đặt lịch nhắc định kỳ.")
            }
        }
        try preferencesStore.setReminderFrequency(frequency, for: userId)
        try await syncLocalNotifications()
        return frequency
    }

    public func scheduleSnoozeReminder(afterMinutes: Int, suggestedDeckTitle: String?) async throws -> Date {
        let userId = try isolationGuard.requireActiveUserId()
        guard (5...240).contains(afterMinutes) else {
            throw LockInDomainError.validationFailed("Thời gian nhắc lại sau phải nằm trong khoảng 5 đến 240 phút.")
        }
        var allowed = await notificationService.isAuthorized()
        if !allowed {
            allowed = try await notificationService.requestAuthorization()
        }
        guard allowed else {
            throw LockInDomainError.validationFailed("Chưa được cấp quyền Thông báo để hẹn nhắc lại sau.")
        }

        let deckLabel = (suggestedDeckTitle?.isEmpty == false) ? suggestedDeckTitle! : "bài học đang chờ"
        return try await notificationService.scheduleOneTimeSnooze(
            forUserId: userId,
            afterMinutes: afterMinutes,
            title: "Nhắc ôn thi LockIn",
            body: "Quay lại ôn \(deckLabel) để giữ vững chuỗi Streak hôm nay."
        )
    }

    public func activeOrDueSchedule(at referenceDate: Date) async throws -> StudyScheduleDTO? {
        try await activeOrDueScheduleOccurrence(at: referenceDate)?.schedule
    }

    private func activeOrDueScheduleOccurrence(at referenceDate: Date) async throws -> (schedule: StudyScheduleDTO, scheduledAt: Date)? {
        let userId = try isolationGuard.requireActiveUserId()
        let cal = calendar

        return try await studyStore.perform { context in
            guard let match = try SharedThemeRotationEngine.findDueSchedule(
                for: userId,
                at: referenceDate,
                windowBeforeSeconds: 0,
                windowAfterSeconds: 2 * 3600,
                in: context,
                calendar: cal
            ) else {
                return nil
            }
            return (Self.toDTO(match.schedule), match.scheduledAt)
        }
    }

    public func activateScheduledSession(scheduleId: UUID) async throws -> ScheduledSessionActivationResult {
        let session = try isolationGuard.requireActiveSession()
        let uid = session.userId
        let expectedEpoch = session.sessionEpoch

        for attempt in 0..<2 {
            let initialSnapshot = try snapshotStore.loadSnapshot()
            guard initialSnapshot.activeUserId == uid,
                  initialSnapshot.sessionEpoch == expectedEpoch else {
                throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
            }
            let expectedRevisionId = initialSnapshot.snapshotRevisionId

            let sessionData: (
                schedule: StudyScheduleDTO,
                deckTitle: String,
                firstCard: (id: UUID, question: String, answer: String)?,
                totalCards: Int,
                masteredCards: Int,
                hideAnswerByDefault: Bool,
                shufflePoolIds: [String],
                progressRatio: Double,
                streakCount: Int
            ) = try await studyStore.perform { context in
                guard self.isolationGuard.currentUserId() == uid,
                      self.isolationGuard.currentSessionEpoch() == expectedEpoch else {
                    throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
                }

                let sid = scheduleId
                guard let schedule = try context.fetch(
                    FetchDescriptor<StudySchedule>(predicate: #Predicate<StudySchedule> { $0.id == sid && $0.ownerUserId == uid })
                ).first else {
                    throw LockInDomainError.entityNotFound
                }

                let targetDeckId = schedule.deckId
                guard let deck = try context.fetch(
                    FetchDescriptor<StudyDeck>(predicate: #Predicate<StudyDeck> { $0.id == targetDeckId && $0.ownerUserId == uid })
                ).first else {
                    throw LockInDomainError.entityNotFound
                }

                let orderedCards = deck.cards
                    .filter { $0.ownerUserId == uid }
                    .sorted { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) }

                let pref = try ThemeCatalogService.fetchOrCreatePreference(for: uid, in: context)
                let progress = try SharedDailyProgressHelper.fetchOrCreateTodayProgress(for: uid, in: context)
                if context.hasChanges {
                    try context.save()
                }

                let first = orderedCards.first.map { ($0.id, $0.question, $0.answer) }
                let mastered = orderedCards.filter { $0.status == .mastered }.count

                return (
                    Self.toDTO(schedule),
                    deck.title,
                    first,
                    orderedCards.count,
                    mastered,
                    pref.hideAnswerByDefault,
                    pref.shufflePoolIds,
                    SharedDailyProgressHelper.completionRatio(for: progress),
                    progress.streakCount
                )
            }

            let effectiveThemeId: String = {
                if sessionData.schedule.autoRotateTheme {
                    return SharedThemeRotationEngine.selectNextThemeId(
                        currentThemeId: initialSnapshot.activeThemeId,
                        shufflePoolIds: sessionData.shufflePoolIds
                    )
                }
                return initialSnapshot.activeThemeId
            }()

            let updatedSnapshot: LockScreenSnapshot
            do {
                updatedSnapshot = try snapshotStore.mutateSnapshotIfSessionMatches(
                    expectedUserId: uid,
                    expectedSessionEpoch: expectedEpoch,
                    expectedRevisionId: expectedRevisionId
                ) { state in
                    // Chỉ cập nhật bộ đề, thẻ, tiến độ và theme (nếu bật xoay vòng).
                    // Luôn giữ nguyên privacyModeEnabled và fontScaleRaw mới nhất trong snapshot.
                    state.activeDeckId = sessionData.schedule.deckId
                    state.activeDeckTitle = sessionData.deckTitle
                    state.currentCardId = sessionData.firstCard?.id
                    state.currentCardQuestion = sessionData.firstCard?.question ?? "Bộ đề chưa có thẻ ôn."
                    state.currentCardAnswer = sessionData.firstCard?.answer ?? ""
                    state.currentCardIndex = 0
                    state.totalCardsInDeck = sessionData.totalCards
                    state.masteredCountInDeck = sessionData.masteredCards
                    state.isAnswerVisible = !sessionData.hideAnswerByDefault
                    if sessionData.schedule.autoRotateTheme {
                        state.activeThemeId = effectiveThemeId
                    }
                    state.dailyProgressRatio = sessionData.progressRatio
                    state.streakCount = sessionData.streakCount
                }
            } catch let error as AppGroupStorageError {
                if case .staleSnapshotRevision = error, attempt == 0 {
                    continue
                }
                throw error
            }

            if sessionData.schedule.autoRotateTheme {
                let targetThemeId = updatedSnapshot.activeThemeId
                try await studyStore.perform { context in
                    guard self.isolationGuard.currentUserId() == uid,
                          self.isolationGuard.currentSessionEpoch() == expectedEpoch else {
                        throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
                    }
                    let liveSnapshot = try self.snapshotStore.loadSnapshot()
                    guard liveSnapshot.activeUserId == uid,
                          liveSnapshot.sessionEpoch == expectedEpoch else {
                        throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
                    }
                    let pref = try ThemeCatalogService.fetchOrCreatePreference(for: uid, in: context)
                    pref.activeThemeId = targetThemeId
                    try context.save()
                }
            }

            let latestSnapshot = try snapshotStore.loadSnapshot()
            guard latestSnapshot.activeUserId == uid,
                  latestSnapshot.sessionEpoch == expectedEpoch else {
                throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
            }

            let contentState = SharedCardNavigationEngine.makeContentState(from: latestSnapshot)
            await SharedCardNavigationEngine.updateRunningLiveActivities(deckId: nil, state: contentState)
            WidgetCenter.shared.reloadAllTimelines()
            CrossProcessNotifier.postStateDidChange()

            let marker = SnapshotStateMarker(
                version: latestSnapshot.snapshotVersion,
                revisionId: latestSnapshot.snapshotRevisionId
            )
            let rotatedTheme = sessionData.schedule.autoRotateTheme
            let activeThemeId = latestSnapshot.activeThemeId
            let deckId = sessionData.schedule.deckId
            await MainActor.run {
                syncEventBus.publish(.cardsChanged(deckId: deckId), observedMarker: marker)
                if rotatedTheme {
                    syncEventBus.publish(.themeRotated(themeId: activeThemeId), observedMarker: marker)
                }
            }

            return ScheduledSessionActivationResult(
                schedule: sessionData.schedule,
                prioritizedDeckId: sessionData.schedule.deckId,
                prioritizedDeckTitle: sessionData.deckTitle,
                didRotateTheme: sessionData.schedule.autoRotateTheme,
                activeThemeId: activeThemeId
            )
        }

        throw AppGroupStorageError.storageIOFailure("Không thể kích hoạt lịch ôn tập do xung đột revision liên tiếp.")
    }

    public func applyDueScheduleIfNeeded(at referenceDate: Date) async throws -> ScheduledSessionActivationResult? {
        guard let userId = isolationGuard.currentUserId() else {
            return nil
        }
        guard let match = try await activeOrDueScheduleOccurrence(at: referenceDate) else {
            return nil
        }
        // Khóa theo ngày xảy ra mốc lịch (scheduledAt) để lịch 23:30 kích hoạt lúc 23:45 không bị lặp lại lúc 00:15.
        let dateKey = SharedDailyProgressHelper.dateKey(for: match.scheduledAt, calendar: calendar)
        if preferencesStore.hasAppliedSchedule(match.schedule.id, for: userId, onDateKey: dateKey) {
            return nil
        }
        let result = try await activateScheduledSession(scheduleId: match.schedule.id)
        try? preferencesStore.markScheduleApplied(match.schedule.id, for: userId, onDateKey: dateKey)
        return result
    }

    private static func toDTO(_ model: StudySchedule) -> StudyScheduleDTO {
        StudyScheduleDTO(
            id: model.id,
            ownerUserId: model.ownerUserId,
            deckId: model.deckId,
            title: model.title,
            hour: model.hour,
            minute: model.minute,
            weekdaysMask: model.weekdaysMask,
            isEnabled: model.isEnabled,
            autoRotateTheme: model.autoRotateTheme
        )
    }
}
