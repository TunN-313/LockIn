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
        pendingIdentifiers.removeAll { $0.hasPrefix(LocalNotificationService.lockInNotificationPrefix) }
        deliveredIdentifiers.removeAll { $0.hasPrefix(LocalNotificationService.lockInNotificationPrefix) }
    }

    public func resyncNotifications(
        forUserId userId: UUID,
        schedules: [StudyScheduleDTO],
        deckTitlesById: [UUID: String]
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
    }

    public func seedDeliveredNotification(identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        deliveredIdentifiers.append(identifier)
    }
}

@MainActor
public final class LockInTestEnvironment {
    public let tempDirectoryURL: URL
    public let modelContainer: ModelContainer
    public let snapshotStore: AppGroupSnapshotStore
    public let keychain: InMemoryKeychainStorage
    public let notificationService: InMemoryLocalNotificationService
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
        self.container = DependencyContainer.makeForTesting(
            modelContainer: modelContainer,
            snapshotStore: snapshotStore,
            keychain: keychain,
            notificationService: notificationService,
            enableDarwinObserver: false
        )
    }

    public func cleanup() {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
    }
}
