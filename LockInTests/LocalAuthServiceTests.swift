// LocalAuthServiceTests.swift — Kiểm thử đăng ký, đăng nhập, chuyển hồ sơ, PIN cooldown và khôi phục sinh trắc học.
// Thuộc LockInTests (M4b); chạy cô lập trên SwiftData in-memory, AppGroupSnapshotStore tạm và InMemoryKeychainStorage.

import SwiftData
import XCTest
@testable import LockInApp

final class LocalAuthServiceTests: XCTestCase {
    @MainActor
    func testRegisterValidationLoginLogoutAndSessionEpochRotation() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "AlphaPass#2026"

        do {
            _ = try await env.container.auth.register(
                username: "ab",
                displayName: "Short",
                password: userCredential
            )
            XCTFail("Tên đăng nhập quá ngắn phải bị từ chối.")
        } catch let error as LockInDomainError {
            guard case .invalidUsername = error else {
                return XCTFail("Kỳ vọng invalidUsername, nhận: \(error)")
            }
        }

        do {
            _ = try await env.container.auth.register(
                username: "valid_user_01",
                displayName: "Weak Pass",
                password: "123"
            )
            XCTFail("Mật khẩu ngắn phải bị từ chối.")
        } catch let error as LockInDomainError {
            guard case .invalidPassword = error else {
                return XCTFail("Kỳ vọng invalidPassword, nhận: \(error)")
            }
        }

        let created = try await env.container.auth.register(
            username: "Alice_01",
            displayName: "Alice",
            password: userCredential
        )
        XCTAssertEqual(created.username, "alice_01")

        let active = await env.container.auth.currentActiveUser()
        XCTAssertEqual(active?.id, created.id)

        let firstSnapshot = try env.snapshotStore.loadSnapshot()
        XCTAssertEqual(firstSnapshot.activeUserId, created.id)
        let firstEpoch = try XCTUnwrap(firstSnapshot.sessionEpoch)
        XCTAssertEqual(firstSnapshot.activeThemeId, ThemePalette.minimalPaper.id)

        do {
            _ = try await env.container.auth.register(
                username: "  alice_01 ",
                displayName: "Duplicate",
                password: userCredential
            )
            XCTFail("Không được phép trùng tên đăng nhập.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .duplicateUsername)
        }

        try await env.container.auth.logout()
        let userAfterLogout = await env.container.auth.currentActiveUser()
        XCTAssertNil(userAfterLogout)
        let loggedOutSnapshot = try env.snapshotStore.loadSnapshot()
        XCTAssertNil(loggedOutSnapshot.activeUserId)
        XCTAssertNil(loggedOutSnapshot.sessionEpoch)

        do {
            _ = try await env.container.auth.login(username: "alice_01", password: "WrongPass#2026")
            XCTFail("Sai mật khẩu phải ném invalidCredentials.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .invalidCredentials)
        }

        let loggedIn = try await env.container.auth.login(username: "alice_01", password: userCredential)
        XCTAssertEqual(loggedIn.id, created.id)
        let reloginSnapshot = try env.snapshotStore.loadSnapshot()
        XCTAssertEqual(reloginSnapshot.activeUserId, created.id)
        XCTAssertNotEqual(reloginSnapshot.sessionEpoch, firstEpoch)
    }

    @MainActor
    func testSwitchProfileIsolatesDataAndPreservesSessionOnFailure() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let credentialA = "UserAlpha#2026"
        let credentialB = "UserBeta#2026"

        let userA = try await env.container.auth.register(
            username: "profile_alpha",
            displayName: "Profile Alpha",
            password: credentialA
        )
        _ = try await env.container.study.createDeck(
            title: "Alpha Deck",
            subjectTag: "OS",
            accentHex: "#2563EB",
            examDate: nil,
            dailyGoal: 10
        )
        try await env.container.auth.logout()

        let userB = try await env.container.auth.register(
            username: "profile_beta",
            displayName: "Profile Beta",
            password: credentialB
        )
        _ = try await env.container.study.createDeck(
            title: "Beta Deck",
            subjectTag: "DB",
            accentHex: "#16A34A",
            examDate: nil,
            dailyGoal: 15
        )

        let profiles = try await env.container.auth.listProfiles()
        XCTAssertEqual(profiles.count, 2)

        do {
            _ = try await env.container.auth.switchProfile(userId: userA.id, password: "BadCredential#99")
            XCTFail("Đổi hồ sơ với sai mật khẩu phải thất bại.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .invalidCredentials)
        }

        let stillUserB = await env.container.auth.currentActiveUser()
        XCTAssertEqual(stillUserB?.id, userB.id)

        let switchedToA = try await env.container.auth.switchProfile(userId: userA.id, password: credentialA)
        XCTAssertEqual(switchedToA.id, userA.id)

        let decksForA = try await env.container.study.fetchDecks()
        XCTAssertEqual(decksForA.map(\.title), ["Alpha Deck"])
        XCTAssertEqual(try env.snapshotStore.loadSnapshot().activeUserId, userA.id)
    }

    @MainActor
    func testPinCooldownLockoutFailClosedAndPasswordReset() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "PinOwner#2026"

        let user = try await env.container.auth.register(
            username: "pin_tester",
            displayName: "Pin Tester",
            password: userCredential
        )

        do {
            try await env.container.security.setFallbackPin("12AB56")
            XCTFail("PIN chứa chữ cái phải bị từ chối.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .invalidPinFormat)
        }

        try await env.container.security.setFallbackPin("135790")
        let hasPin = await env.container.security.hasFallbackPin()
        XCTAssertTrue(hasPin)
        let lockRequired = await env.container.security.isAppLockRequired()
        XCTAssertTrue(lockRequired)

        let cooldownAccount = KeychainAccountKeys.pinCooldown(for: user.id)
        env.keychain.failingReadAccounts = [cooldownAccount]
        do {
            _ = try await env.container.security.verifyFallbackPin("135790")
            XCTFail("Khi lỗi đọc trạng thái cooldown phải fail-closed.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .pinCooldownStateUnverifiableRequiresPassword)
        }
        env.keychain.failingReadAccounts = []

        try env.keychain.saveStandardData(Data("corrupted-json".utf8), account: cooldownAccount)
        do {
            _ = try await env.container.security.verifyFallbackPin("135790")
            XCTFail("Dữ liệu cooldown bị hỏng phải fail-closed.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .pinCooldownStateUnverifiableRequiresPassword)
        }
        try await env.container.security.unlockAndResetPinCooldown(usingPassword: userCredential)

        for attempt in 1..<AppConstants.maxPinFailedAttempts {
            let result = try await env.container.security.verifyFallbackPin("000000")
            XCTAssertFalse(result, "Lần sai thứ \(attempt) không được vượt qua.")
        }

        do {
            _ = try await env.container.security.verifyFallbackPin("000000")
            XCTFail("Lần sai thứ \(AppConstants.maxPinFailedAttempts) phải kích hoạt cooldown.")
        } catch let error as LockInDomainError {
            guard case .pinLockedCooldown(let remaining) = error else {
                return XCTFail("Kỳ vọng pinLockedCooldown, nhận: \(error)")
            }
            XCTAssertGreaterThan(remaining, 0)
        }

        let cooldownRemaining = await env.container.security.remainingPinCooldownSeconds()
        XCTAssertGreaterThan(cooldownRemaining, 0)

        do {
            _ = try await env.container.security.verifyFallbackPin("135790")
            XCTFail("Trong thời gian cooldown không thể mở bằng PIN đúng.")
        } catch let error as LockInDomainError {
            guard case .pinLockedCooldown = error else {
                return XCTFail("Kỳ vọng pinLockedCooldown, nhận: \(error)")
            }
        }

        do {
            try await env.container.security.unlockAndResetPinCooldown(usingPassword: "WrongCredential")
            XCTFail("Sai mật khẩu tài khoản không thể xóa cooldown.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .invalidCredentials)
        }

        try await env.container.security.unlockAndResetPinCooldown(usingPassword: userCredential)
        let remainingAfterReset = await env.container.security.remainingPinCooldownSeconds()
        XCTAssertEqual(remainingAfterReset, 0)

        let verifiedAfterReset = try await env.container.security.verifyFallbackPin("135790")
        XCTAssertTrue(verifiedAfterReset)
    }

    @MainActor
    func testBiometricInvalidationRequiresFallbackAndRecoversViaPin() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "BioOwner#2026"

        let user = try await env.container.auth.register(
            username: "bio_tester",
            displayName: "Bio Tester",
            password: userCredential
        )
        try await env.container.security.setFallbackPin("246810")

        // Nạp trạng thái đã bật khóa sinh trắc học trong hồ sơ + secret Keychain giả lập (vì Simulator không có phần cứng Face ID).
        let context = ModelContext(env.modelContainer)
        let uid = user.id
        if let profile = try context.fetch(
            FetchDescriptor<UserProfile>(predicate: #Predicate<UserProfile> { $0.id == uid })
        ).first {
            profile.isBiometricEnabled = true
            try context.save()
        }
        try env.keychain.saveBiometricAppLockSecret(
            Data(repeating: 0x5A, count: 32),
            account: KeychainAccountKeys.biometricAppLockSecret(for: user.id)
        )

        let appLockRequired = await env.container.security.isAppLockRequired()
        XCTAssertTrue(appLockRequired)

        try await env.container.security.unlockWithBiometric(reason: "Mở khóa kiểm thử")

        env.keychain.simulateBiometricAuthCancel = true
        do {
            try await env.container.security.unlockWithBiometric(reason: "Mở khóa khi hủy")
            XCTFail("Khi người dùng hủy sinh trắc học phải ném biometricUnavailable.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .biometricUnavailable)
        }
        env.keychain.simulateBiometricAuthCancel = false

        env.keychain.simulateBiometricInvalidation = true
        do {
            try await env.container.security.unlockWithBiometric(reason: "Mở khóa khi đổi Face ID")
            XCTFail("Khi .biometryCurrentSet bị vô hiệu hóa phải yêu cầu PIN/Mật khẩu dự phòng.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .biometricInvalidatedRequiresFallback)
        }

        do {
            try await env.container.security.recoverBiometricLockAfterInvalidation(usingPin: "999999")
            XCTFail("PIN dự phòng sai phải bị từ chối.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .invalidCredentials)
        }

        try await env.container.security.recoverBiometricLockAfterInvalidation(usingPin: "246810")
        env.keychain.simulateBiometricInvalidation = false

        let stillProtectedByPin = await env.container.security.isAppLockRequired()
        XCTAssertTrue(stillProtectedByPin)
    }
}
