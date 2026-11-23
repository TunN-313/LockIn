// DevicePermissionChecker.swift — Kiểm tra trạng thái quyền Live Activities, Thông báo, App Group và phiên hiện tại.
// Cung cấp dữ liệu cho Setup Wizard trong LockScreenModule.

import ActivityKit
import Foundation
import UserNotifications

public protocol DevicePermissionCheckerProtocol: Sendable {
    func checkBridgeStatus(activeDeckId: UUID?, activeDeckTitle: String?) async -> LockScreenBridgeStatus
}

public final class DevicePermissionChecker: DevicePermissionCheckerProtocol {
    private let appGroupId: String

    public init(appGroupId: String = AppConstants.resolvedAppGroupIdentifier) {
        self.appGroupId = appGroupId
    }

    public func checkBridgeStatus(activeDeckId: UUID?, activeDeckTitle: String?) async -> LockScreenBridgeStatus {
        let activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let notificationAuthorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationAuthorized = true
        default:
            notificationAuthorized = false
        }
        let appGroupAvailable = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) != nil
        let activeActivities = Activity<StudySessionAttributes>.activities
        let firstActiveState = activeActivities.first?.content.state

        return LockScreenBridgeStatus(
            areLiveActivitiesEnabled: activitiesEnabled,
            isNotificationAuthorized: notificationAuthorized,
            isAppGroupAvailable: appGroupAvailable,
            isLiveActivityActive: !activeActivities.isEmpty,
            activeDeckId: firstActiveState?.deckId ?? activeDeckId,
            activeDeckTitle: firstActiveState?.deckTitle ?? activeDeckTitle
        )
    }
}
