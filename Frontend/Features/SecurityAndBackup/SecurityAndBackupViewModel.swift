// SecurityAndBackupViewModel.swift — Quản lý hồ sơ cục bộ, khóa sinh trắc học/PIN, Backup AES-GCM và xóa dữ liệu cá nhân.
// Thuộc Frontend/Features/SecurityAndBackup; chỉ phụ thuộc SecurityModuleProtocol, AuthModuleProtocol, BackupModuleProtocol, StorageMaintenanceProtocol.

import Foundation
import Observation

@MainActor
@Observable
public final class SecurityAndBackupViewModel {
    private let securityModule: SecurityModuleProtocol
    private let authModule: AuthModuleProtocol
    private let backupModule: BackupModuleProtocol
    private let storageMaintenance: StorageMaintenanceProtocol

    public var activeUser: UserProfileDTO?
    public var allProfiles: [UserProfileDTO] = []
    public var hasFallbackPin: Bool = false
    public var isBiometricEnabled: Bool = false
    public var statusMessage: String?
    public var errorMessage: String?

    public init(
        securityModule: SecurityModuleProtocol,
        authModule: AuthModuleProtocol,
        backupModule: BackupModuleProtocol,
        storageMaintenance: StorageMaintenanceProtocol
    ) {
        self.securityModule = securityModule
        self.authModule = authModule
        self.backupModule = backupModule
        self.storageMaintenance = storageMaintenance
    }

    public func refresh() async {
        activeUser = await authModule.currentActiveUser()
        isBiometricEnabled = activeUser?.isBiometricEnabled ?? false
        hasFallbackPin = await securityModule.hasFallbackPin()
        do {
            allProfiles = try await authModule.listProfiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setFallbackPin(_ pin: String) async -> Bool {
        errorMessage = nil
        do {
            try await securityModule.setFallbackPin(pin)
            hasFallbackPin = true
            statusMessage = "Đã lưu mã PIN 6 số dự phòng."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func setBiometricEnabled(_ enabled: Bool) async {
        errorMessage = nil
        do {
            if enabled {
                try await securityModule.enableBiometricLock(reason: "Kích hoạt khóa ứng dụng bằng Face ID / Touch ID")
                statusMessage = "Đã bật khóa sinh trắc học (Keychain .biometryCurrentSet)."
            } else {
                try await securityModule.disableBiometricLock()
                statusMessage = "Đã tắt khóa sinh trắc học."
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            await refresh()
        }
    }

    public func switchProfile(userId: UUID, password: String) async -> Bool {
        errorMessage = nil
        do {
            _ = try await authModule.switchProfile(userId: userId, password: password)
            await refresh()
            statusMessage = "Đã chuyển sang hồ sơ mới."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func logout() async {
        errorMessage = nil
        do {
            try await authModule.logout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func exportEncryptedBackup(passphrase: String) async -> Data? {
        errorMessage = nil
        do {
            let data = try await backupModule.exportEncryptedBackup(passphrase: passphrase)
            statusMessage = "Đã tạo tệp sao lưu mã hóa AES-GCM."
            return data
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func readBackupFileForImport(at url: URL) -> Data? {
        errorMessage = nil
        do {
            return try backupModule.readBoundedBackupFile(at: url)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func importEncryptedBackup(data: Data, passphrase: String, mode: BackupRestoreMode) async -> Bool {
        errorMessage = nil
        do {
            try await backupModule.importEncryptedBackup(data, passphrase: passphrase, mode: mode)
            statusMessage = "Đã khôi phục dữ liệu từ tệp sao lưu."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func purgeCurrentUserStudyData() async {
        errorMessage = nil
        do {
            try await storageMaintenance.purgeCurrentUserStudyData()
            statusMessage = "Đã xóa toàn bộ dữ liệu học tập của hồ sơ hiện tại."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
