// MarkMasteredIntent.swift — LiveActivityIntent đánh dấu thẻ hiện tại đã thuộc và chuyển sang thẻ tiếp theo.
// Chỉ phụ thuộc Shared/ExtensionCore/SharedCardNavigationEngine; openAppWhenRun = false.

import AppIntents
import Foundation

public struct MarkMasteredIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Đánh dấu đã thuộc"
    public static var description = IntentDescription("Đánh dấu thẻ hiện tại là đã thuộc, cộng tiến độ ngày và sang thẻ mới.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        let engine = try SharedCardNavigationEngine.makeShared()
        _ = try await engine.perform(action: .markMastered)
        return .result()
    }
}
