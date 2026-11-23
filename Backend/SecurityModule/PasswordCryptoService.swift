// PasswordCryptoService.swift — Cung cấp PBKDF2-HMAC-SHA256 (600,000 vòng OWASP), random salt và AES-GCM.
// Dùng chung cho Password, 6-digit PIN và EncryptedBackupService (SecurityModule).

import CommonCrypto
import CryptoKit
import Foundation
import Security

public protocol PasswordCryptoServiceProtocol: Sendable {
    func generateRandomSalt(byteCount: Int) throws -> Data
    func deriveKeyPBKDF2(secret: String, salt: Data, iterations: Int, keyByteCount: Int) throws -> Data
    func verifySecret(_ secret: String, salt: Data, expectedHash: Data, iterations: Int) throws -> Bool
    func encryptAESGCM(plaintext: Data, keyData: Data) throws -> Data
    func decryptAESGCM(combined: Data, keyData: Data) throws -> Data
}

public extension PasswordCryptoServiceProtocol {
    func generateRandomSalt() throws -> Data {
        try generateRandomSalt(byteCount: AppConstants.saltByteCount)
    }

    func deriveKeyPBKDF2(secret: String, salt: Data) throws -> Data {
        try deriveKeyPBKDF2(
            secret: secret,
            salt: salt,
            iterations: AppConstants.pbkdf2Iterations,
            keyByteCount: 32
        )
    }

    func verifySecret(_ secret: String, salt: Data, expectedHash: Data) throws -> Bool {
        try verifySecret(
            secret,
            salt: salt,
            expectedHash: expectedHash,
            iterations: AppConstants.pbkdf2Iterations
        )
    }
}

public final class PasswordCryptoService: PasswordCryptoServiceProtocol {
    public init() {}

    public func generateRandomSalt(byteCount: Int = AppConstants.saltByteCount) throws -> Data {
        guard byteCount > 0 else {
            throw LockInDomainError.validationFailed("Kích thước salt phải lớn hơn 0.")
        }
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw LockInDomainError.persistenceFailure("SecRandomCopyBytes thất bại (status: \(status)).")
        }
        return Data(bytes)
    }

    public func deriveKeyPBKDF2(
        secret: String,
        salt: Data,
        iterations: Int = AppConstants.pbkdf2Iterations,
        keyByteCount: Int = 32
    ) throws -> Data {
        guard let validIterations = UInt32(exactly: iterations),
              iterations >= 1,
              iterations <= AppConstants.maxPbkdf2Iterations,
              keyByteCount > 0,
              salt.count >= AppConstants.saltByteCount else {
            throw LockInDomainError.validationFailed("Tham số dẫn xuất khóa PBKDF2 không hợp lệ.")
        }
        guard let passwordData = secret.data(using: .utf8) else {
            throw LockInDomainError.validationFailed("Chuỗi bí mật không thể mã hóa UTF-8.")
        }

        var derivedKey = [UInt8](repeating: 0, count: keyByteCount)
        let status: Int32 = passwordData.withUnsafeBytes { passwordRawBuffer in
            let passwordPtr = passwordRawBuffer.bindMemory(to: Int8.self).baseAddress
            return salt.withUnsafeBytes { saltRawBuffer in
                let saltPtr = saltRawBuffer.bindMemory(to: UInt8.self).baseAddress
                return CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordPtr,
                    passwordData.count,
                    saltPtr,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    validIterations,
                    &derivedKey,
                    keyByteCount
                )
            }
        }

        guard status == kCCSuccess else {
            throw LockInDomainError.persistenceFailure("PBKDF2-HMAC-SHA256 thất bại (status: \(status)).")
        }
        return Data(derivedKey)
    }

    public func verifySecret(
        _ secret: String,
        salt: Data,
        expectedHash: Data,
        iterations: Int = AppConstants.pbkdf2Iterations
    ) throws -> Bool {
        let derived = try deriveKeyPBKDF2(
            secret: secret,
            salt: salt,
            iterations: iterations,
            keyByteCount: max(32, expectedHash.count)
        )
        guard derived.count == expectedHash.count else {
            return false
        }
        var diff: UInt8 = 0
        for (lhs, rhs) in zip(derived, expectedHash) {
            diff |= lhs ^ rhs
        }
        return diff == 0
    }

    public func encryptAESGCM(plaintext: Data, keyData: Data) throws -> Data {
        let key = SymmetricKey(data: keyData)
        do {
            let sealedBox = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealedBox.combined else {
                throw LockInDomainError.persistenceFailure("Không tạo được AES.GCM combined payload.")
            }
            return combined
        } catch let domainError as LockInDomainError {
            throw domainError
        } catch {
            throw LockInDomainError.persistenceFailure(error.localizedDescription)
        }
    }

    public func decryptAESGCM(combined: Data, keyData: Data) throws -> Data {
        let key = SymmetricKey(data: keyData)
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw LockInDomainError.backupCorruptedOrWrongPassphrase
        }
    }
}
