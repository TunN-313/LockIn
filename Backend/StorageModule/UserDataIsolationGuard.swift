// UserDataIsolationGuard.swift — Ép buộc mọi truy vấn và thao tác Backend lọc chặt theo activeUserId.
// Ngăn chặn truy cập chéo dữ liệu giữa các hồ sơ người dùng cục bộ (StorageModule).

import Foundation

public enum KeychainAccountKeys {
    public static let activeUserId = "lockin.session.active_user_id"
    public static let activeSessionEpoch = "lockin.session.active_epoch"

    public static func pinHash(for userId: UUID) -> String {
        "lockin.pin.hash.\(userId.uuidString)"
    }

    public static func pinSalt(for userId: UUID) -> String {
        "lockin.pin.salt.\(userId.uuidString)"
    }

    public static func pinCooldown(for userId: UUID) -> String {
        "lockin.pin.cooldown.\(userId.uuidString)"
    }

    public static func biometricAppLockSecret(for userId: UUID) -> String {
        "lockin.applock.biometric.\(userId.uuidString)"
    }
}

public protocol UserDataIsolationGuardProtocol: Sendable {
    func currentUserId() -> UUID?
    func currentSessionEpoch() -> UUID?
    func requireActiveUserId() throws -> UUID
    func requireActiveSession() throws -> (userId: UUID, sessionEpoch: UUID)
    func verifyOwnership(recordOwnerId: UUID, activeUserId: UUID) throws
    func filterOwned<T>(_ items: [T], ownerIdKeyPath: KeyPath<T, UUID>, activeUserId: UUID) -> [T]
}

public final class UserDataIsolationGuard: UserDataIsolationGuardProtocol, @unchecked Sendable {
    private let keychain: KeychainStorageProtocol

    public init(keychain: KeychainStorageProtocol) {
        self.keychain = keychain
    }

    public func currentUserId() -> UUID? {
        guard let data = try? keychain.loadStandardData(account: KeychainAccountKeys.activeUserId),
              let raw = String(data: data, encoding: .utf8),
              let uuid = UUID(uuidString: raw) else {
            return nil
        }
        return uuid
    }

    public func currentSessionEpoch() -> UUID? {
        guard let data = try? keychain.loadStandardData(account: KeychainAccountKeys.activeSessionEpoch),
              let raw = String(data: data, encoding: .utf8),
              let uuid = UUID(uuidString: raw) else {
            return nil
        }
        return uuid
    }

    public func requireActiveUserId() throws -> UUID {
        guard let userId = currentUserId() else {
            throw LockInDomainError.unauthenticated
        }
        return userId
    }

    public func requireActiveSession() throws -> (userId: UUID, sessionEpoch: UUID) {
        guard let userId = currentUserId(), let sessionEpoch = currentSessionEpoch() else {
            throw LockInDomainError.unauthenticated
        }
        return (userId, sessionEpoch)
    }

    public func verifyOwnership(recordOwnerId: UUID, activeUserId: UUID) throws {
        guard recordOwnerId == activeUserId else {
            throw LockInDomainError.entityNotFound
        }
    }

    public func filterOwned<T>(_ items: [T], ownerIdKeyPath: KeyPath<T, UUID>, activeUserId: UUID) -> [T] {
        items.filter { $0[keyPath: ownerIdKeyPath] == activeUserId }
    }
}
