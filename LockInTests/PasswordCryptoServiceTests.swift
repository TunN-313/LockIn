// PasswordCryptoServiceTests.swift — Kiểm thử dẫn xuất khóa PBKDF2-HMAC-SHA256 (600,000 vòng) và AES-GCM.
// Thuộc LockInTests (M4b); xác minh random salt, kiểm chứng bí mật, từ chối tham số sai và phát hiện sửa đổi ciphertext.

import XCTest
@testable import LockInApp

final class PasswordCryptoServiceTests: XCTestCase {
    func testGenerateRandomSaltLengthAndUniqueness() throws {
        let crypto = PasswordCryptoService()

        let saltA = try crypto.generateRandomSalt()
        let saltB = try crypto.generateRandomSalt()
        let customSalt = try crypto.generateRandomSalt(byteCount: 32)

        XCTAssertEqual(saltA.count, AppConstants.saltByteCount)
        XCTAssertEqual(saltB.count, AppConstants.saltByteCount)
        XCTAssertEqual(customSalt.count, 32)
        XCTAssertNotEqual(saltA, saltB)

        XCTAssertThrowsError(try crypto.generateRandomSalt(byteCount: 0)) { error in
            guard case LockInDomainError.validationFailed = error else {
                return XCTFail("Kỳ vọng validationFailed khi byteCount <= 0, nhận: \(error)")
            }
        }
    }

    func testDeriveKeyPBKDF2DeterminismAndVerifySecret() throws {
        let crypto = PasswordCryptoService()
        let salt1 = try crypto.generateRandomSalt()
        let salt2 = try crypto.generateRandomSalt()
        let credentialInput = "LockIn-Strong-Credential-2026"

        let hash1 = try crypto.deriveKeyPBKDF2(secret: credentialInput, salt: salt1)
        let hash1Repeat = try crypto.deriveKeyPBKDF2(secret: credentialInput, salt: salt1)
        let hashDifferentSalt = try crypto.deriveKeyPBKDF2(secret: credentialInput, salt: salt2)

        XCTAssertEqual(hash1.count, 32)
        XCTAssertEqual(hash1, hash1Repeat)
        XCTAssertNotEqual(hash1, hashDifferentSalt)
        XCTAssertTrue(try crypto.verifySecret(credentialInput, salt: salt1, expectedHash: hash1))
        XCTAssertFalse(try crypto.verifySecret("Wrong-Credential-2026", salt: salt1, expectedHash: hash1))
    }

    func testDeriveKeyRejectsInvalidParameters() throws {
        let crypto = PasswordCryptoService()
        let validSalt = try crypto.generateRandomSalt()
        let shortSalt = Data([0x01, 0x02, 0x03])

        XCTAssertThrowsError(
            try crypto.deriveKeyPBKDF2(
                secret: "Credential-1234",
                salt: shortSalt,
                iterations: AppConstants.pbkdf2Iterations,
                keyByteCount: 32
            )
        ) { error in
            guard case LockInDomainError.validationFailed = error else {
                return XCTFail("Kỳ vọng validationFailed với salt ngắn, nhận: \(error)")
            }
        }

        XCTAssertThrowsError(
            try crypto.deriveKeyPBKDF2(
                secret: "Credential-1234",
                salt: validSalt,
                iterations: 0,
                keyByteCount: 32
            )
        ) { error in
            guard case LockInDomainError.validationFailed = error else {
                return XCTFail("Kỳ vọng validationFailed khi iterations = 0, nhận: \(error)")
            }
        }

        XCTAssertThrowsError(
            try crypto.deriveKeyPBKDF2(
                secret: "Credential-1234",
                salt: validSalt,
                iterations: AppConstants.maxPbkdf2Iterations + 1,
                keyByteCount: 32
            )
        ) { error in
            guard case LockInDomainError.validationFailed = error else {
                return XCTFail("Kỳ vọng validationFailed khi vượt ngưỡng maxPbkdf2Iterations, nhận: \(error)")
            }
        }
    }

    func testAESGCMRoundTripWrongKeyAndTamperDetection() throws {
        let crypto = PasswordCryptoService()
        let salt = try crypto.generateRandomSalt()
        let key = try crypto.deriveKeyPBKDF2(secret: "Backup-Key-Alpha-2026", salt: salt)
        let wrongKey = try crypto.deriveKeyPBKDF2(secret: "Backup-Key-Beta-2026", salt: salt)
        let plaintext = Data("{\"deck\":\"SwiftUI Concurrency\"}".utf8)

        let sealed = try crypto.encryptAESGCM(plaintext: plaintext, keyData: key)
        let decrypted = try crypto.decryptAESGCM(combined: sealed, keyData: key)
        XCTAssertEqual(decrypted, plaintext)

        XCTAssertThrowsError(try crypto.decryptAESGCM(combined: sealed, keyData: wrongKey)) { error in
            XCTAssertEqual(error as? LockInDomainError, .backupCorruptedOrWrongPassphrase)
        }

        var tampered = sealed
        let middleIndex = tampered.count / 2
        tampered[middleIndex] ^= 0xFF
        XCTAssertThrowsError(try crypto.decryptAESGCM(combined: tampered, keyData: key)) { error in
            XCTAssertEqual(error as? LockInDomainError, .backupCorruptedOrWrongPassphrase)
        }

        XCTAssertThrowsError(try crypto.encryptAESGCM(plaintext: plaintext, keyData: Data([1, 2, 3]))) { error in
            guard case LockInDomainError.validationFailed = error else {
                return XCTFail("Kỳ vọng validationFailed khi keyData không đủ 32 bytes, nhận: \(error)")
            }
        }
    }
}
