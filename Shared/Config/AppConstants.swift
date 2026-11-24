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
        func sanitizedIdentifier(_ raw: String?) -> String? {
            guard let raw else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("$("), !trimmed.contains("*") else { return nil }
            return trimmed
        }

        func sanitizedAppGroup(_ raw: String?) -> String? {
            guard let clean = sanitizedIdentifier(raw), clean.hasPrefix("group.") else { return nil }
            return clean
        }

        let configuredInfoGroup = sanitizedAppGroup(infoPlistGroupId)
        let baseBundleId = sanitizedIdentifier(bundleIdentifier).map { bundleId in
            bundleId.hasSuffix(".widgets")
                ? String(bundleId.dropLast(".widgets".count))
                : bundleId
        }
        let bundleDerivedGroup = baseBundleId.map { "group.\($0)" }
        let bundleDerivedSharedGroup = baseBundleId.map { "group.\($0).shared" }
        let configuredSuffix = configuredInfoGroup.map { String($0.dropFirst("group.".count)) }
        let defaultSuffix = String(defaultAppGroupIdentifier.dropFirst("group.".count))

        func lockInMatchRank(for candidate: String) -> Int? {
            if let configuredInfoGroup {
                if candidate == configuredInfoGroup { return 0 }
                if candidate.hasPrefix("\(configuredInfoGroup).") { return 1 }
            }
            if candidate == defaultAppGroupIdentifier { return 2 }
            if candidate.hasPrefix("\(defaultAppGroupIdentifier).") { return 3 }
            if let bundleDerivedSharedGroup, candidate == bundleDerivedSharedGroup { return 4 }
            if let bundleDerivedGroup, candidate == bundleDerivedGroup { return 5 }
            if let bundleDerivedGroup, candidate.hasPrefix("\(bundleDerivedGroup).") { return 6 }
            if let configuredSuffix, candidate.hasSuffix(".\(configuredSuffix)") { return 7 }
            if candidate.hasSuffix(".\(defaultSuffix)") { return 8 }
            return nil
        }

        var orderedCandidates: [String] = []
        var seen: Set<String> = []
        func appendCandidate(_ candidate: String?) {
            guard let clean = sanitizedAppGroup(candidate), !seen.contains(clean) else { return }
            seen.insert(clean)
            orderedCandidates.append(clean)
        }

        // Ưu tiên cấu hình tường minh (Xcode / TestFlight) nếu container khả dụng.
        appendCandidate(configuredInfoGroup)

        // Lọc và sắp xếp tất định chỉ các App Group thuộc phạm vi LockIn trong mobileprovision,
        // loại bỏ hoàn toàn App Group không liên quan và không phụ thuộc thứ tự trong profile.
        var matchedProvisionByGroup: [String: Int] = [:]
        for rawGroup in mobileProvisionGroups {
            guard let clean = sanitizedAppGroup(rawGroup),
                  let rank = lockInMatchRank(for: clean) else {
                continue
            }
            if let existing = matchedProvisionByGroup[clean] {
                matchedProvisionByGroup[clean] = min(existing, rank)
            } else {
                matchedProvisionByGroup[clean] = rank
            }
        }
        let matchedProvisionCandidates = matchedProvisionByGroup
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value < rhs.value
                }
                return lhs.key < rhs.key
            }
            .map(\.key)

        for candidate in matchedProvisionCandidates {
            appendCandidate(candidate)
        }

        appendCandidate(defaultAppGroupIdentifier)
        appendCandidate(bundleDerivedSharedGroup)
        appendCandidate(bundleDerivedGroup)

        for candidate in orderedCandidates where isContainerAvailable(candidate) {
            return candidate
        }

        if let configuredInfoGroup {
            return configuredInfoGroup
        }
        if let firstMatchedProvision = matchedProvisionCandidates.first {
            return firstMatchedProvision
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
