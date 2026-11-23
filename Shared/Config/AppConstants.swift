// AppConstants.swift — Chứa hằng số cấu hình tập trung, giới hạn dữ liệu và chuẩn bảo mật OWASP.
// Cung cấp cấu hình dùng chung cho cả Shared/, Backend/, LockInWidgetsExtension/ và tương thích sideload $0.

import Foundation

public enum AppConstants {
    // MARK: - Bundle & App Group (Sideload-friendly)
    public static let defaultBundleIdentifier = "com.lockin.app"
    public static let defaultAppGroupIdentifier = "group.com.lockin.shared"

    public static var resolvedAppGroupIdentifier: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "LockInAppGroupIdentifier") as? String,
           !configured.isEmpty,
           !configured.contains("$(") {
            return configured
        }
        return defaultAppGroupIdentifier
    }

    public static var keychainServiceIdentifier: String {
        let rawBundleId = Bundle.main.bundleIdentifier ?? defaultBundleIdentifier
        let baseBundleId: String
        if rawBundleId.hasSuffix(".widgets") {
            baseBundleId = String(rawBundleId.dropLast(".widgets".count))
        } else {
            baseBundleId = rawBundleId
        }
        return "\(baseBundleId).keychain"
    }

    // MARK: - Cross-Process Darwin IPC
    public static var darwinStateDidChangeNotificationName: String {
        "\(resolvedAppGroupIdentifier).ipc.stateDidChange"
    }

    // MARK: - OWASP Security Constants
    public static let pbkdf2Iterations: Int = 600_000
    public static let maxPbkdf2Iterations: Int = 2_000_000
    public static let saltByteCount: Int = 16
    public static let minPasswordLength: Int = 6
    public static let minUsernameLength: Int = 3
    public static let maxUsernameLength: Int = 32
    public static let minBackupPassphraseLength: Int = 8
    public static let pinLength: Int = 6
    public static let maxPinFailedAttempts: Int = 5
    public static let pinBaseCooldownSeconds: TimeInterval = 30

    // MARK: - Payload & Input Limits
    public static let maxLiveActivityDeckTitleLength: Int = 80
    public static let maxLiveActivityTextLength: Int = 220
    public static let maxLiveActivityContentStateBytes: Int = 4_096
    public static let maxQuickImportLines: Int = 500
    public static let maxFieldCharacterLength: Int = 500
    public static let maxBackupFileBytes: Int = 10 * 1_024 * 1_024
    public static let backupFileExtension: String = "lockinbackup"
    public static let backupSchemaVersion: Int = 1
}
