// RotateLockInThemeIntent.swift — AppIntent ưu tiên bộ đề theo lịch đến hạn và xoay theme trong Shuffle Pool cho iOS Shortcuts.
// Chỉ phụ thuộc Shared/ExtensionCore/SharedThemeRotationEngine; hỗ trợ trigger Time of Day, Focus Mode, App Opened/Closed và Charger.

import AppIntents
import Foundation

public struct RotateLockInThemeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Xoay Theme LockIn"
    public static var description = IntentDescription("Ưu tiên bộ đề theo lịch học đến hạn (nếu có) và xoay theme tiếp theo lên Lock Screen.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        let engine = try SharedThemeRotationEngine.makeShared()
        _ = try await engine.rotateThemeInSharedStore(referenceDate: Date(), calendar: .current)
        return .result()
    }
}
