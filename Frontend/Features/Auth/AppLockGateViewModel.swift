// AppLockGateViewModel.swift — Điều phối mở khóa ứng dụng qua Face ID/Touch ID, mã PIN 6 số hoặc mật khẩu khôi phục.
// Thuộc Frontend/Features/Auth; chỉ giao tiếp với Backend/SecurityModule thông qua SecurityModuleProtocol.

import Foundation
import Observation

@MainActor
@Observable
public final class AppLockGateViewModel {
    private let securityModule: SecurityModuleProtocol
    private let onUnlocked: () -> Void

    public var pinInput: String = ""
    public var passwordInput: String = ""
    public var hasPinConfigured: Bool = false
    public var cooldownSeconds: Int = 0
    public var requiresPasswordRecovery: Bool = false
    public var biometricInvalidatedMode: Bool = false
    public var isProcessing: Bool = false
    public var errorMessage: String?

    public init(
        securityModule: SecurityModuleProtocol,
        onUnlocked: @escaping () -> Void
    ) {
        self.securityModule = securityModule
        self.onUnlocked = onUnlocked
    }

    public func loadInitialState() async {
        hasPinConfigured = await securityModule.hasFallbackPin()
        cooldownSeconds = await securityModule.remainingPinCooldownSeconds()
        if cooldownSeconds > 0 {
            requiresPasswordRecovery = true
        }
        await attemptBiometricUnlock()
    }

    public func attemptBiometricUnlock() async {
        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await securityModule.unlockWithBiometric(reason: "Mở khóa ứng dụng học tập LockIn")
            onUnlocked()
        } catch let domainError as LockInDomainError {
            switch domainError {
            case .biometricInvalidatedRequiresFallback:
                biometricInvalidatedMode = true
                requiresPasswordRecovery = true
                errorMessage = domainError.localizedDescription
            case .biometricUnavailable:
                if !hasPinConfigured {
                    requiresPasswordRecovery = true
                }
            default:
                errorMessage = domainError.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func submitPin() async {
        errorMessage = nil
        let cleanPin = pinInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanPin.count == AppConstants.pinLength else {
            errorMessage = "Vui lòng nhập đủ 6 chữ số mã PIN."
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            let valid = try await securityModule.verifyFallbackPin(cleanPin)
            pinInput = ""
            if valid {
                onUnlocked()
            } else {
                cooldownSeconds = await securityModule.remainingPinCooldownSeconds()
                errorMessage = "Mã PIN chưa chính xác."
            }
        } catch let domainError as LockInDomainError {
            pinInput = ""
            switch domainError {
            case .pinLockedCooldown(let seconds):
                cooldownSeconds = seconds
                errorMessage = domainError.localizedDescription
            case .pinCooldownStateUnverifiableRequiresPassword:
                requiresPasswordRecovery = true
                errorMessage = domainError.localizedDescription
            default:
                errorMessage = domainError.localizedDescription
            }
        } catch {
            pinInput = ""
            errorMessage = error.localizedDescription
        }
    }

    public func submitPasswordRecovery() async {
        errorMessage = nil
        guard !passwordInput.isEmpty else {
            errorMessage = "Vui lòng nhập mật khẩu tài khoản để xác thực."
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            if biometricInvalidatedMode {
                try await securityModule.recoverBiometricLockAfterInvalidation(usingPassword: passwordInput)
            } else {
                try await securityModule.unlockAndResetPinCooldown(usingPassword: passwordInput)
            }
            passwordInput = ""
            onUnlocked()
        } catch {
            passwordInput = ""
            errorMessage = error.localizedDescription
        }
    }
}
