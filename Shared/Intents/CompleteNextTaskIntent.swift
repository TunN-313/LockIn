// CompleteNextTaskIntent.swift — AppIntent đánh dấu hoàn thành nhanh task ưu tiên trên Lock Screen Widget.
// Chỉ phụ thuộc Shared/ExtensionCore/SharedTaskQuickActionEngine; openAppWhenRun = false.

import AppIntents
import Foundation

public struct CompleteNextTaskIntent: AppIntent {
    public static var title: LocalizedStringResource = "Hoàn thành việc tiếp theo"
    public static var description = IntentDescription("Đánh dấu hoàn thành tác vụ ưu tiên đang hiển thị trên Lock Screen Widget.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        let engine = try SharedTaskQuickActionEngine.makeShared()
        _ = try await engine.completeNextPendingTask()
        return .result()
    }
}
