// KeychainStorageService.swift — Lưu/đọc Keychain tách biệt item thường và item App Lock (.biometryCurrentSet).
// Tuyệt đối CHỈ gắn .biometryCurrentSet lên biometricUnlockSecret của App Lock, không gắn lên session token hay PIN hash.

import Foundation
import LocalAuthentication
import Security

public enum KeychainBiometricReadResult: Equatable, Sendable {
    case found(Data)
    case notFoundOrInvalidated
    case authFailedOrCanceled
}

public protocol KeychainStorageProtocol: Sendable {
    // Standard items (kSecAttrAccessibleWhenUnlockedThisDeviceOnly — KHÔNG gắn .biometryCurrentSet)
    func saveStandardData(_ data: Data, account: String) throws
    func loadStandardData(account: String) throws -> Data?
    func deleteStandardData(account: String) throws

    // App Lock biometric item ONLY (.biometryCurrentSet + kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly)
    func saveBiometricAppLockSecret(_ data: Data, account: String) throws
    func readBiometricAppLockSecret(account: String, promptReason: String) throws -> KeychainBiometricReadResult
    func hasBiometricAppLockSecret(account: String) -> Bool
    func deleteBiometricAppLockSecret(account: String) throws
}

public final class KeychainStorageService: KeychainStorageProtocol {
    private let serviceIdentifier: String

    public init(serviceIdentifier: String = AppConstants.keychainServiceIdentifier) {
        self.serviceIdentifier = serviceIdentifier
    }

    public func saveStandardData(_ data: Data, account: String) throws {
        try deleteStandardData(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LockInDomainError.persistenceFailure("Keychain SecItemAdd thất bại (status: \(status)).")
        }
    }

    public func loadStandardData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw LockInDomainError.persistenceFailure("Keychain SecItemCopyMatching thất bại (status: \(status)).")
        }
    }

    public func deleteStandardData(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LockInDomainError.persistenceFailure("Keychain SecItemDelete thất bại (status: \(status)).")
        }
    }

    public func saveBiometricAppLockSecret(_ data: Data, account: String) throws {
        try deleteBiometricAppLockSecret(account: account)

        var accessError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &accessError
        ) else {
            let description = accessError?.takeRetainedValue().localizedDescription ?? "Không tạo được SecAccessControl."
            throw LockInDomainError.persistenceFailure(description)
        }

        // Lưu ý: khi dùng kSecAttrAccessControl, tuyệt đối không truyền kèm kSecAttrAccessible để tránh errSecParam.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecAttrAccessControl as String: accessControl,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LockInDomainError.persistenceFailure("Keychain biometric SecItemAdd thất bại (status: \(status)).")
        }
    }

    public func readBiometricAppLockSecret(account: String, promptReason: String) throws -> KeychainBiometricReadResult {
        let authContext = LAContext()
        authContext.localizedReason = promptReason

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: authContext
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            if let data = result as? Data {
                return .found(data)
            }
            return .notFoundOrInvalidated
        case errSecItemNotFound:
            return .notFoundOrInvalidated
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            return .authFailedOrCanceled
        default:
            throw LockInDomainError.persistenceFailure("Keychain biometric read thất bại (status: \(status)).")
        }
    }

    public func hasBiometricAppLockSecret(account: String) -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    public func deleteBiometricAppLockSecret(account: String) throws {
        try deleteStandardData(account: account)
    }
}
