// NextCardIntent.swift — LiveActivityIntent chuyển sang thẻ kế tiếp ngay trên Lock Screen.
// Chỉ phụ thuộc Shared/ExtensionCore/SharedCardNavigationEngine; openAppWhenRun = false.

import AppIntents
import Foundation

public struct NextCardIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Thẻ ôn tiếp theo"
    public static var description = IntentDescription("Chuyển sang thẻ kế tiếp ngay trên Live Activity mà không cần mở ứng dụng.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        let engine = try SharedCardNavigationEngine.makeShared()
        _ = try await engine.perform(action: .next)
        return .result()
    }
}
