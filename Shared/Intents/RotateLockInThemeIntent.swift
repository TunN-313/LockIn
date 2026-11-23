// RotateLockInThemeIntent.swift — AppIntent xoay sang theme tiếp theo trong Shuffle Pool cho iOS Shortcuts.
// Chỉ phụ thuộc Shared/ExtensionCore/SharedThemeRotationEngine; chạy với trigger hợp lệ của iOS Shortcuts.

import AppIntents
import Foundation

public struct RotateLockInThemeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Xoay Theme LockIn"
    public static var description = IntentDescription("Đổi sang theme tiếp theo trong Shuffle Pool và cập nhật Lock Screen.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        let engine = try SharedThemeRotationEngine.makeShared()
        _ = try await engine.rotateThemeInSharedStore()
        return .result()
    }
}
