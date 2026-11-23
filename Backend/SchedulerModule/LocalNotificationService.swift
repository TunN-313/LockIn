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
        deckTitlesById: [UUID: String]
    ) async throws
}

public final class LocalNotificationService: LocalNotificationServiceProtocol {
    public static let lockInNotificationPrefix = "lockin.schedule."

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
            .filter { $0.hasPrefix(Self.lockInNotificationPrefix) }
        if !pendingIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingIds)
        }

        let deliveredNotifications = await center.deliveredNotifications()
        let deliveredIds = deliveredNotifications
            .map { $0.request.identifier }
            .filter { $0.hasPrefix(Self.lockInNotificationPrefix) }
        if !deliveredIds.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredIds)
        }
    }

    public func resyncNotifications(
        forUserId userId: UUID,
        schedules: [StudyScheduleDTO],
        deckTitlesById: [UUID: String]
    ) async throws {
        await cancelAllLockInNotifications()

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
    }
}
