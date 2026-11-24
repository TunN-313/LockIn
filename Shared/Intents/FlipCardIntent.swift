// FlipCardIntent.swift — LiveActivityIntent lật giữa câu hỏi và đáp án ngay trên Lock Screen.
// Chỉ phụ thuộc Shared/ExtensionCore/SharedCardNavigationEngine; openAppWhenRun = false.

import AppIntents
import Foundation

public struct FlipCardIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Lật đáp án thẻ ôn"
    public static var description = IntentDescription("Lật giữa câu hỏi và đáp án ngay trên Live Activity mà không cần mở ứng dụng.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        let engine = try SharedCardNavigationEngine.makeShared()
        _ = try await engine.perform(action: .flip)
        return .result()
    }
}
