// AppConstants.swift — Chứa hằng số cấu hình tập trung, giới hạn dữ liệu và chuẩn bảo mật OWASP.
// Cung cấp cấu hình dùng chung cho cả Shared/, Backend/, LockInWidgetsExtension/ và tương thích sideload $0.

import Foundation

public enum AppConstants {
    // MARK: - Bundle & App Group (Sideload-friendly)
    public static let defaultBundleIdentifier = "com.lockin.app"
    public static let defaultAppGroupIdentifier = "group.com.lockin.shared"

    private static let cachedResolvedAppGroupIdentifier: String = {
        resolveAppGroupIdentifier(
            infoPlistGroupId: Bundle.main.object(forInfoDictionaryKey: "LockInAppGroupIdentifier") as? String,
            mobileProvisionGroups: loadAppGroupsFromEmbeddedProvision(),
            bundleIdentifier: Bundle.main.bundleIdentifier,
            isContainerAvailable: { groupId in
                FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) != nil
            }
        )
    }()

    public static var resolvedAppGroupIdentifier: String {
        cachedResolvedAppGroupIdentifier
    }

    public static func resolveAppGroupIdentifier(
        infoPlistGroupId: String?,
        mobileProvisionGroups: [String],
        bundleIdentifier: String?,
        isContainerAvailable: (String) -> Bool
    ) -> String {
        func sanitized(_ raw: String?) -> String? {
            guard let raw else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
            return trimmed
        }

        var orderedCandidates: [String] = []
        var seen: Set<String> = []
        func appendCandidate(_ candidate: String?) {
            guard let clean = sanitized(candidate), !seen.contains(clean) else { return }
            seen.insert(clean)
            orderedCandidates.append(clean)
        }

        for group in mobileProvisionGroups {
            appendCandidate(group)
        }
        appendCandidate(infoPlistGroupId)

        if let bundleId = sanitized(bundleIdentifier) {
            let baseBundleId = bundleId.hasSuffix(".widgets")
                ? String(bundleId.dropLast(".widgets".count))
                : bundleId
            appendCandidate("group.\(baseBundleId)")
            appendCandidate("group.\(baseBundleId).shared")
        }

        appendCandidate(defaultAppGroupIdentifier)

        for candidate in orderedCandidates where isContainerAvailable(candidate) {
            return candidate
        }

        if let firstProvisioned = mobileProvisionGroups.compactMap(sanitized).first {
            return firstProvisioned
        }
        if let configuredInfo = sanitized(infoPlistGroupId) {
            return configuredInfo
        }
        return defaultAppGroupIdentifier
    }

    public static func extractAppGroups(fromMobileProvisionData data: Data) -> [String] {
        guard let rawText = String(data: data, encoding: .isoLatin1),
              let plistStart = rawText.range(of: "<plist"),
              let plistEnd = rawText.range(of: "</plist>", range: plistStart.lowerBound..<rawText.endIndex) else {
            return []
        }

        let plistSnippet = String(rawText[plistStart.lowerBound..<plistEnd.upperBound])
        guard let plistData = plistSnippet.data(using: .utf8),
              let plistObject = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let rootDict = plistObject as? [String: Any],
              let entitlements = rootDict["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else {
            return []
        }

        return groups
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func loadAppGroupsFromEmbeddedProvision() -> [String] {
        guard let provisionURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let provisionData = try? Data(contentsOf: provisionURL) else {
            return []
        }
        return extractAppGroups(fromMobileProvisionData: provisionData)
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
