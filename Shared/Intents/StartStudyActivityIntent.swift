// StartStudyActivityIntent.swift — AppIntent mở app lên foreground để khởi tạo lại Live Activity khi hết hạn 8–12h.
// Bắt buộc đặt openAppWhenRun = true vì Activity.request yêu cầu app ở foreground (không dùng APNs push-to-start).

import ActivityKit
import AppIntents
import Foundation

public enum StartStudyActivityError: Error, LocalizedError {
    case liveActivitiesDisabled
    case noActiveStudyDeck

    public var errorDescription: String? {
        switch self {
        case .liveActivitiesDisabled:
            return "Live Activities đang tắt trong Cài đặt iOS."
        case .noActiveStudyDeck:
            return "Chưa có bộ đề ôn tập nào được chọn để đưa lên màn hình khóa."
        }
    }
}

public struct StartStudyActivityIntent: AppIntent {
    public static var title: LocalizedStringResource = "Khởi động lại phiên ôn trên Lock Screen"
    public static var description = IntentDescription("Mở LockIn lên foreground để khởi tạo lại Live Activity sau khi hết vòng đời 8–12 giờ.")
    public static var openAppWhenRun: Bool = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw StartStudyActivityError.liveActivitiesDisabled
        }
        let engine = try SharedCardNavigationEngine.makeShared()
        guard let contentState = try await engine.loadCurrentContentState() else {
            throw StartStudyActivityError.noActiveStudyDeck
        }
        for existing in Activity<StudySessionAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        let attributes = StudySessionAttributes()
        let content = ActivityContent(state: contentState, staleDate: nil)
        _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        return .result()
    }
}
