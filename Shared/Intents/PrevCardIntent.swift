// PrevCardIntent.swift — LiveActivityIntent quay lại thẻ trước ngay trên Lock Screen.
// Chỉ phụ thuộc Shared/ExtensionCore/SharedCardNavigationEngine; openAppWhenRun = false.

import AppIntents
import Foundation

public struct PrevCardIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Thẻ ôn trước đó"
    public static var description = IntentDescription("Quay lại thẻ trước ngay trên Live Activity mà không cần mở ứng dụng.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        let engine = try SharedCardNavigationEngine.makeShared()
        _ = try await engine.perform(action: .previous)
        return .result()
    }
}
