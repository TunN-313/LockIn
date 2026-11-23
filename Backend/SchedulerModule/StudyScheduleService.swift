// StudyScheduleService.swift — Quản lý lịch học real-time (StudySchedule) cô lập theo ownerUserId.
// Triển khai SchedulerModuleProtocol, tính mốc thời gian học kế tiếp và đồng bộ LocalNotificationService.

import Foundation
import SwiftData

public final class StudyScheduleService: SchedulerModuleProtocol, @unchecked Sendable {
    private let studyStore: SwiftDataStudyStore
    private let isolationGuard: UserDataIsolationGuardProtocol
    private let notificationService: LocalNotificationServiceProtocol
    private let calendar: Calendar

    public init(
        studyStore: SwiftDataStudyStore,
        isolationGuard: UserDataIsolationGuardProtocol,
        notificationService: LocalNotificationServiceProtocol,
        calendar: Calendar = .current
    ) {
        self.studyStore = studyStore
        self.isolationGuard = isolationGuard
        self.notificationService = notificationService
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

        try await notificationService.resyncNotifications(
            forUserId: userId,
            schedules: payload.schedules,
            deckTitlesById: payload.deckTitles
        )
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
