// BiometricPinLockService.swift — Quản lý App Lock bằng Keychain .biometryCurrentSet và mã PIN 6 số (PBKDF2 600k).
// Triển khai SecurityModuleProtocol dạng actor; tuần tự hóa kiểm tra PIN theo hồ sơ và fail-closed khi lỗi cooldown.

import Foundation
import LocalAuthentication
import SwiftData

private struct AuthProfileSnapshot: Sendable {
    let id: UUID
    let passwordHash: Data
    let passwordSalt: Data
    let isBiometricEnabled: Bool
}

private struct PinCooldownState: Codable, Equatable {
    var failedAttempts: Int
    var lockedUntil: Date?
}

public actor BiometricPinLockService: SecurityModuleProtocol {
    private let studyStore: SwiftDataStudyStore
    private let isolationGuard: UserDataIsolationGuardProtocol
    private let keychain: KeychainStorageProtocol
    private let crypto: PasswordCryptoServiceProtocol
    private let syncEventBus: SyncEventBus?
    private let nowProvider: @Sendable () -> Date

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        studyStore: SwiftDataStudyStore,
        isolationGuard: UserDataIsolationGuardProtocol,
        keychain: KeychainStorageProtocol,
        crypto: PasswordCryptoServiceProtocol,
        syncEventBus: SyncEventBus? = nil,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.studyStore = studyStore
        self.isolationGuard = isolationGuard
        self.keychain = keychain
        self.crypto = crypto
        self.syncEventBus = syncEventBus
        self.nowProvider = nowProvider
    }

    public func isAppLockRequired() async -> Bool {
        guard let userId = isolationGuard.currentUserId() else { return false }
        let biometricEnabled = (try? await fetchUserProfile(userId: userId)?.isBiometricEnabled) ?? false
        let pinExists = await hasFallbackPin()
        return biometricEnabled || pinExists
    }

    public func setFallbackPin(_ pin: String) async throws {
        let userId = try isolationGuard.requireActiveUserId()
        guard Self.isValidPinFormat(pin) else {
            throw LockInDomainError.invalidPinFormat
        }
        let salt = try crypto.generateRandomSalt(byteCount: AppConstants.saltByteCount)
        let hash = try crypto.deriveKeyPBKDF2(
            secret: pin,
            salt: salt,
            iterations: AppConstants.pbkdf2Iterations,
            keyByteCount: 32
        )
        try keychain.saveStandardData(hash, account: KeychainAccountKeys.pinHash(for: userId))
        try keychain.saveStandardData(salt, account: KeychainAccountKeys.pinSalt(for: userId))
        try keychain.deleteStandardData(account: KeychainAccountKeys.pinCooldown(for: userId))
        await notifyAppLockPolicyChanged()
    }

    public func hasFallbackPin() async -> Bool {
        guard let userId = isolationGuard.currentUserId() else { return false }
        do {
            let hash = try keychain.loadStandardData(account: KeychainAccountKeys.pinHash(for: userId))
            let salt = try keychain.loadStandardData(account: KeychainAccountKeys.pinSalt(for: userId))
            return hash != nil && salt != nil
        } catch {
            // Fail-closed: nếu Keychain trả lỗi khi kiểm tra PIN, vẫn coi là có cấu hình khóa bảo vệ.
            return true
        }
    }

    public func remainingPinCooldownSeconds() async -> Int {
        guard let userId = isolationGuard.currentUserId() else { return 0 }
        do {
            let state = try loadCooldownStateStrict(for: userId)
            guard let lockedUntil = state.lockedUntil else { return 0 }
            let remaining = Int(ceil(lockedUntil.timeIntervalSince(nowProvider())))
            return max(0, remaining)
        } catch {
            return Int(AppConstants.pinBaseCooldownSeconds)
        }
    }

    public func verifyFallbackPin(_ pin: String) async throws -> Bool {
        try verifyFallbackPinSynchronized(pin)
    }

    public func enableBiometricLock(reason: String) async throws {
        let userId = try isolationGuard.requireActiveUserId()
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            throw LockInDomainError.biometricUnavailable
        }

        let secret = try crypto.generateRandomSalt(byteCount: 32)
        let account = KeychainAccountKeys.biometricAppLockSecret(for: userId)
        try keychain.saveBiometricAppLockSecret(secret, account: account)

        let readResult = try keychain.readBiometricAppLockSecret(account: account, promptReason: reason)
        switch readResult {
        case .found:
            try await setBiometricEnabledFlag(true, for: userId)
            await notifyAppLockPolicyChanged()
        case .notFoundOrInvalidated, .authFailedOrCanceled:
            try? keychain.deleteBiometricAppLockSecret(account: account)
            throw LockInDomainError.biometricUnavailable
        }
    }

    public func disableBiometricLock() async throws {
        let userId = try isolationGuard.requireActiveUserId()
        try keychain.deleteBiometricAppLockSecret(account: KeychainAccountKeys.biometricAppLockSecret(for: userId))
        try await setBiometricEnabledFlag(false, for: userId)
        await notifyAppLockPolicyChanged()
    }

    public func unlockWithBiometric(reason: String) async throws {
        let userId = try isolationGuard.requireActiveUserId()
        let profile = try await fetchUserProfile(userId: userId)
        guard profile?.isBiometricEnabled == true else {
            throw LockInDomainError.biometricUnavailable
        }

        let account = KeychainAccountKeys.biometricAppLockSecret(for: userId)
        guard keychain.hasBiometricAppLockSecret(account: account) else {
            throw LockInDomainError.biometricInvalidatedRequiresFallback
        }

        let result = try keychain.readBiometricAppLockSecret(account: account, promptReason: reason)
        switch result {
        case .found:
            return
        case .notFoundOrInvalidated:
            throw LockInDomainError.biometricInvalidatedRequiresFallback
        case .authFailedOrCanceled:
            throw LockInDomainError.biometricUnavailable
        }
    }

    public func recoverBiometricLockAfterInvalidation(usingPassword password: String) async throws {
        let userId = try await verifyAccountPasswordAndClearPinCooldown(password)
        try await reEnrollBiometricItem(for: userId)
        await notifyAppLockPolicyChanged()
    }

    public func recoverBiometricLockAfterInvalidation(usingPin pin: String) async throws {
        let userId = try isolationGuard.requireActiveUserId()
        let verified = try verifyFallbackPinSynchronized(pin)
        guard verified else {
            throw LockInDomainError.invalidCredentials
        }
        try await reEnrollBiometricItem(for: userId)
        await notifyAppLockPolicyChanged()
    }

    private func notifyAppLockPolicyChanged() async {
        guard let syncEventBus else { return }
        let required = await isAppLockRequired()
        await MainActor.run {
            syncEventBus.publish(.appLockPolicyChanged(isRequired: required))
        }
    }

    public func unlockAndResetPinCooldown(usingPassword password: String) async throws {
        _ = try await verifyAccountPasswordAndClearPinCooldown(password)
    }

    // Thực thi đồng bộ hoàn toàn bên trong actor (không có `await` xen giữa) để tuần tự hóa kiểm tra PIN và bộ đếm cooldown.
    private func verifyFallbackPinSynchronized(_ pin: String) throws -> Bool {
        let userId = try isolationGuard.requireActiveUserId()
        var state = try loadCooldownStateStrict(for: userId)
        if let lockedUntil = state.lockedUntil {
            let remaining = Int(ceil(lockedUntil.timeIntervalSince(nowProvider())))
            if remaining > 0 {
                throw LockInDomainError.pinLockedCooldown(remainingSeconds: remaining)
            }
        }

        guard Self.isValidPinFormat(pin) else {
            throw LockInDomainError.invalidPinFormat
        }
        guard let expectedHash = try keychain.loadStandardData(account: KeychainAccountKeys.pinHash(for: userId)),
              let salt = try keychain.loadStandardData(account: KeychainAccountKeys.pinSalt(for: userId)) else {
            throw LockInDomainError.entityNotFound
        }

        let isValid = try crypto.verifySecret(
            pin,
            salt: salt,
            expectedHash: expectedHash,
            iterations: AppConstants.pbkdf2Iterations
        )

        if isValid {
            do {
                try keychain.deleteStandardData(account: KeychainAccountKeys.pinCooldown(for: userId))
            } catch {
                throw LockInDomainError.pinCooldownStateUnverifiableRequiresPassword
            }
            return true
        }

        state.failedAttempts += 1
        if state.failedAttempts >= AppConstants.maxPinFailedAttempts {
            let exponent = state.failedAttempts - AppConstants.maxPinFailedAttempts
            let multiplier = pow(2.0, Double(min(6, exponent)))
            let cooldownSeconds = AppConstants.pinBaseCooldownSeconds * multiplier
            state.lockedUntil = nowProvider().addingTimeInterval(cooldownSeconds)
            try saveCooldownStateStrict(state, for: userId)
            throw LockInDomainError.pinLockedCooldown(remainingSeconds: Int(ceil(cooldownSeconds)))
        }
        try saveCooldownStateStrict(state, for: userId)
        return false
    }

    private func verifyAccountPasswordAndClearPinCooldown(_ password: String) async throws -> UUID {
        let userId = try isolationGuard.requireActiveUserId()
        guard !password.isEmpty else {
            throw LockInDomainError.invalidCredentials
        }
        guard let profile = try await fetchUserProfile(userId: userId) else {
            throw LockInDomainError.unauthenticated
        }
        let verified = try crypto.verifySecret(
            password,
            salt: profile.passwordSalt,
            expectedHash: profile.passwordHash,
            iterations: AppConstants.pbkdf2Iterations
        )
        guard verified else {
            throw LockInDomainError.invalidCredentials
        }
        try keychain.deleteStandardData(account: KeychainAccountKeys.pinCooldown(for: userId))
        return userId
    }

    private func reEnrollBiometricItem(for userId: UUID) async throws {
        let account = KeychainAccountKeys.biometricAppLockSecret(for: userId)
        let context = LAContext()
        var authError: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) {
            let newSecret = try crypto.generateRandomSalt(byteCount: 32)
            try keychain.saveBiometricAppLockSecret(newSecret, account: account)
            try await setBiometricEnabledFlag(true, for: userId)
        } else {
            try keychain.deleteBiometricAppLockSecret(account: account)
            try await setBiometricEnabledFlag(false, for: userId)
        }
    }

    private func fetchUserProfile(userId: UUID) async throws -> AuthProfileSnapshot? {
        try await studyStore.perform { context in
            let uid = userId
            let descriptor = FetchDescriptor<UserProfile>(
                predicate: #Predicate<UserProfile> { $0.id == uid }
            )
            return try context.fetch(descriptor).first.map {
                AuthProfileSnapshot(
                    id: $0.id,
                    passwordHash: $0.passwordHash,
                    passwordSalt: $0.passwordSalt,
                    isBiometricEnabled: $0.isBiometricEnabled
                )
            }
        }
    }

    private func setBiometricEnabledFlag(_ enabled: Bool, for userId: UUID) async throws {
        try await studyStore.perform { context in
            let uid = userId
            let descriptor = FetchDescriptor<UserProfile>(
                predicate: #Predicate<UserProfile> { $0.id == uid }
            )
            guard let profile = try context.fetch(descriptor).first else {
                throw LockInDomainError.unauthenticated
            }
            profile.isBiometricEnabled = enabled
            try context.save()
        }
    }

    private func loadCooldownStateStrict(for userId: UUID) throws -> PinCooldownState {
        let rawData: Data?
        do {
            rawData = try keychain.loadStandardData(account: KeychainAccountKeys.pinCooldown(for: userId))
        } catch {
            throw LockInDomainError.pinCooldownStateUnverifiableRequiresPassword
        }

        guard let data = rawData else {
            // Chưa từng có bản ghi lỗi PIN nào được lưu trước đó.
            return PinCooldownState(failedAttempts: 0, lockedUntil: nil)
        }

        do {
            let decoded = try decoder.decode(PinCooldownState.self, from: data)
            guard decoded.failedAttempts >= 0 else {
                throw LockInDomainError.pinCooldownStateUnverifiableRequiresPassword
            }
            return decoded
        } catch {
            throw LockInDomainError.pinCooldownStateUnverifiableRequiresPassword
        }
    }

    private func saveCooldownStateStrict(_ state: PinCooldownState, for userId: UUID) throws {
        do {
            let data = try encoder.encode(state)
            try keychain.saveStandardData(data, account: KeychainAccountKeys.pinCooldown(for: userId))
        } catch {
            throw LockInDomainError.pinCooldownStateUnverifiableRequiresPassword
        }
    }

    public static func isValidPinFormat(_ pin: String) -> Bool {
        pin.count == AppConstants.pinLength && pin.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
