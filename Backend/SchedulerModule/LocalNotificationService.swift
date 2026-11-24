// LocalNotificationService.swift — Quản lý xin quyền, hủy toàn bộ thông báo LockIn khi đổi phiên và lên lịch theo userId.
// Được dùng bởi SchedulerModule và LocalAuthService để bảo đảm không rò thông báo hồ sơ cũ ra Lock Screen.

import Foundation
import UserNotifications

public protocol LocalNotificationServiceProtocol: Sendable {
    func requestAuthorization() async throws -> Bool
    func isAuthorized() async -> Bool
    func cancelAllLockInNotifications() async
    func resyncNotifications(
        forUserId userId: UUID,
        schedules: [StudyScheduleDTO],
        deckTitlesById: [UUID: String],
        reminderFrequency: ReminderNotificationFrequency
    ) async throws
    func scheduleOneTimeSnooze(
        forUserId userId: UUID,
        afterMinutes: Int,
        title: String,
        body: String
    ) async throws -> Date
}

public extension LocalNotificationServiceProtocol {
    func resyncNotifications(
        forUserId userId: UUID,
        schedules: [StudyScheduleDTO],
        deckTitlesById: [UUID: String]
    ) async throws {
        try await resyncNotifications(
            forUserId: userId,
            schedules: schedules,
            deckTitlesById: deckTitlesById,
            reminderFrequency: .off
        )
    }
}

public final class LocalNotificationService: LocalNotificationServiceProtocol {
    public static let lockInAllPrefix = "lockin."
    public static let lockInNotificationPrefix = "lockin.schedule."
    public static let periodicReminderPrefix = "lockin.reminder.freq."
    public static let snoozeReminderPrefix = "lockin.reminder.snooze."

    public init() {}

    public func requestAuthorization() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        return try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    public func cancelAllLockInNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        let pendingIds = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.lockInAllPrefix) }
        if !pendingIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingIds)
        }

        let deliveredNotifications = await center.deliveredNotifications()
        let deliveredIds = deliveredNotifications
            .map { $0.request.identifier }
            .filter { $0.hasPrefix(Self.lockInAllPrefix) }
        if !deliveredIds.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredIds)
        }
    }

    private func cancelSchedulesAndPeriodicReminders(preservingSnoozeForUserId userId: UUID) async {
        let center = UNUserNotificationCenter.current()
        let preservedSnoozeId = "\(Self.snoozeReminderPrefix)\(userId.uuidString)"

        let pendingRequests = await center.pendingNotificationRequests()
        let pendingIds = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.lockInAllPrefix) && $0 != preservedSnoozeId }
        if !pendingIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingIds)
        }

        let deliveredNotifications = await center.deliveredNotifications()
        let deliveredIds = deliveredNotifications
            .map { $0.request.identifier }
            .filter { $0.hasPrefix(Self.lockInAllPrefix) && $0 != preservedSnoozeId }
        if !deliveredIds.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredIds)
        }
    }

    public func resyncNotifications(
        forUserId userId: UUID,
        schedules: [StudyScheduleDTO],
        deckTitlesById: [UUID: String],
        reminderFrequency: ReminderNotificationFrequency
    ) async throws {
        await cancelSchedulesAndPeriodicReminders(preservingSnoozeForUserId: userId)

        guard await isAuthorized() else { return }

        let center = UNUserNotificationCenter.current()
        let userPrefix = "\(Self.lockInNotificationPrefix)\(userId.uuidString)."

        for schedule in schedules where schedule.isEnabled && schedule.ownerUserId == userId {
            let deckName = deckTitlesById[schedule.deckId] ?? "Bộ thẻ ôn thi"
            for weekday in 1...7 {
                let bit = 1 << (weekday - 1)
                guard (schedule.weekdaysMask & bit) != 0 else { continue }

                let content = UNMutableNotificationContent()
                content.title = schedule.title.isEmpty ? "Đến giờ ôn thi LockIn" : schedule.title
                content.body = "Bộ đề: \(deckName). Mở LockIn để đưa thẻ lên Lock Screen."
                content.sound = .default

                var dateComponents = DateComponents()
                dateComponents.weekday = weekday
                dateComponents.hour = schedule.hour
                dateComponents.minute = schedule.minute

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let identifier = "\(userPrefix)\(schedule.id.uuidString).\(weekday)"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                try await center.add(request)
            }
        }

        if reminderFrequency != .off {
            for hour in reminderFrequency.scheduledHours {
                let content = UNMutableNotificationContent()
                content.title = "Nhắc nhở ôn tập LockIn"
                content.body = "Kiểm tra thẻ và tác vụ tồn đọng hôm nay ngay trên LockIn."
                content.sound = .default

                var dateComponents = DateComponents()
                dateComponents.hour = hour
                dateComponents.minute = 0

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let identifier = "\(Self.periodicReminderPrefix)\(userId.uuidString).\(hour)"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                try await center.add(request)
            }
        }
    }

    public func scheduleOneTimeSnooze(
        forUserId userId: UUID,
        afterMinutes: Int,
        title: String,
        body: String
    ) async throws -> Date {
        let center = UNUserNotificationCenter.current()
        let identifier = "\(Self.snoozeReminderPrefix)\(userId.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let interval = TimeInterval(max(60, afterMinutes * 60))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
        return Date().addingTimeInterval(interval)
    }
}
