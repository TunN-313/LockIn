// TestFixtures.swift — Cung cấp InMemoryKeychainStorage, InMemoryLocalNotificationService và LockInTestEnvironment cho 8 bộ test Wave 2 (M4b).
// Sử dụng SharedStoreContainer.makeInMemoryForTesting() và AppGroupSnapshotStore.makeForTesting(directoryURL:).

import Foundation
import SwiftData
import XCTest
@testable import LockInApp

public final class InMemoryKeychainStorage: KeychainStorageProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var standardStorage: [String: Data] = [:]
    private var biometricStorage: [String: Data] = [:]
    public var simulateBiometricInvalidation = false
    public var simulateBiometricAuthCancel = false
    public var simulateStandardReadFailure = false
    public var simulateStandardWriteFailure = false
    public var failingReadAccounts: Set<String> = []

    public init() {}

    public func saveStandardData(_ data: Data, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if simulateStandardWriteFailure {
            throw LockInDomainError.persistenceFailure("Simulated Keychain write failure.")
        }
        standardStorage[account] = data
    }

    public func loadStandardData(account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if simulateStandardReadFailure || failingReadAccounts.contains(account) {
            throw LockInDomainError.persistenceFailure("Simulated Keychain read failure.")
        }
        return standardStorage[account]
    }

    public func deleteStandardData(account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        standardStorage.removeValue(forKey: account)
    }

    public func saveBiometricAppLockSecret(_ data: Data, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        simulateBiometricInvalidation = false
        biometricStorage[account] = data
    }

    public func readBiometricAppLockSecret(account: String, promptReason: String) throws -> KeychainBiometricReadResult {
        lock.lock()
        defer { lock.unlock() }
        if simulateBiometricInvalidation {
            biometricStorage.removeValue(forKey: account)
            return .notFoundOrInvalidated
        }
        if simulateBiometricAuthCancel {
            return .authFailedOrCanceled
        }
        guard let data = biometricStorage[account] else {
            return .notFoundOrInvalidated
        }
        return .found(data)
    }

    public func hasBiometricAppLockSecret(account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if simulateBiometricInvalidation {
            return false
        }
        return biometricStorage[account] != nil
    }

    public func deleteBiometricAppLockSecret(account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        biometricStorage.removeValue(forKey: account)
    }
}

public final class InMemoryLocalNotificationService: LocalNotificationServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    public var authorized = true
    public var pendingIdentifiers: [String] = []
    public var deliveredIdentifiers: [String] = []
    public var snoozeIdentifiers: [String] = []
    public var cancelAllCallCount = 0

    public init() {}

    public func requestAuthorization() async throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return authorized
    }

    public func isAuthorized() async -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return authorized
    }

    public func cancelAllLockInNotifications() async {
        lock.lock()
        defer { lock.unlock() }
        cancelAllCallCount += 1
        pendingIdentifiers.removeAll { $0.hasPrefix(LocalNotificationService.lockInAllPrefix) }
        deliveredIdentifiers.removeAll { $0.hasPrefix(LocalNotificationService.lockInAllPrefix) }
        snoozeIdentifiers.removeAll { $0.hasPrefix(LocalNotificationService.lockInAllPrefix) }
    }

    public func resyncNotifications(
        forUserId userId: UUID,
        schedules: [StudyScheduleDTO],
        deckTitlesById: [UUID: String],
        reminderFrequency: ReminderNotificationFrequency
    ) async throws {
        await cancelAllLockInNotifications()
        lock.lock()
        defer { lock.unlock() }
        guard authorized else { return }
        let userPrefix = "\(LocalNotificationService.lockInNotificationPrefix)\(userId.uuidString)."
        for schedule in schedules where schedule.isEnabled && schedule.ownerUserId == userId {
            for weekday in 1...7 where (schedule.weekdaysMask & (1 << (weekday - 1))) != 0 {
                pendingIdentifiers.append("\(userPrefix)\(schedule.id.uuidString).\(weekday)")
            }
        }
        if reminderFrequency != .off {
            for hour in reminderFrequency.scheduledHours {
                pendingIdentifiers.append("\(LocalNotificationService.periodicReminderPrefix)\(userId.uuidString).\(hour)")
            }
        }
    }

    public func scheduleOneTimeSnooze(
        forUserId userId: UUID,
        afterMinutes: Int,
        title: String,
        body: String
    ) async throws -> Date {
        lock.lock()
        defer { lock.unlock() }
        let identifier = "\(LocalNotificationService.snoozeReminderPrefix)\(userId.uuidString)"
        snoozeIdentifiers.removeAll { $0 == identifier }
        snoozeIdentifiers.append(identifier)
        let interval = TimeInterval(max(60, afterMinutes * 60))
        return Date().addingTimeInterval(interval)
    }

    public func seedDeliveredNotification(identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        deliveredIdentifiers.append(identifier)
    }
}

public final class InMemoryPhotoLibrarySaver: PhotoLibrarySaverProtocol, @unchecked Sendable {
    private let lock = NSLock()
    public var allowSave = true
    public var savedPayloads: [Data] = []

    public init() {}

    public func savePNGDataToPhotos(_ pngData: Data) async throws {
        lock.lock()
        defer { lock.unlock() }
        guard allowSave else {
            throw LockInDomainError.validationFailed("Ứng dụng chưa được cấp quyền Thêm vào Ảnh (Photos) trong Cài đặt.")
        }
        savedPayloads.append(pngData)
    }
}

@MainActor
public final class LockInTestEnvironment {
    public let tempDirectoryURL: URL
    public let modelContainer: ModelContainer
    public let snapshotStore: AppGroupSnapshotStore
    public let keychain: InMemoryKeychainStorage
    public let notificationService: InMemoryLocalNotificationService
    public let photoLibrarySaver: InMemoryPhotoLibrarySaver
    public let container: DependencyContainer

    public init() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LockInTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        self.tempDirectoryURL = tempDir
        self.modelContainer = try SharedStoreContainer.makeInMemoryForTesting()
        self.snapshotStore = try AppGroupSnapshotStore.makeForTesting(directoryURL: tempDir)
        self.keychain = InMemoryKeychainStorage()
        self.notificationService = InMemoryLocalNotificationService()
        self.photoLibrarySaver = InMemoryPhotoLibrarySaver()
        self.container = DependencyContainer.makeForTesting(
            modelContainer: modelContainer,
            snapshotStore: snapshotStore,
            keychain: keychain,
            notificationService: notificationService,
            enableDarwinObserver: false,
            settingsDirectoryURL: tempDir,
            photoLibrarySaver: photoLibrarySaver
        )
    }

    public func cleanup() {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
    }
}
