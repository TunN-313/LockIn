// UserDataIsolationGuardTests.swift — Kiểm thử cô lập dữ liệu hoàn toàn giữa các hồ sơ người dùng cục bộ.
// Thuộc LockInTests (M4b); xác minh chặn truy vấn chéo ownerUserId và thao tác purge chỉ xóa dữ liệu hồ sơ hiện tại.

import XCTest
@testable import LockInApp

final class UserDataIsolationGuardTests: XCTestCase {
    func testGuardRequiresSessionFiltersOwnedAndChecksOwnership() throws {
        let keychain = InMemoryKeychainStorage()
        let isolation = UserDataIsolationGuard(keychain: keychain)

        XCTAssertNil(isolation.currentUserId())
        XCTAssertNil(isolation.currentSessionEpoch())

        XCTAssertThrowsError(try isolation.requireActiveUserId()) { error in
            XCTAssertEqual(error as? LockInDomainError, .unauthenticated)
        }
        XCTAssertThrowsError(try isolation.requireActiveSession()) { error in
            XCTAssertEqual(error as? LockInDomainError, .unauthenticated)
        }

        let ownerA = UUID()
        let ownerB = UUID()
        try isolation.verifyOwnership(recordOwnerId: ownerA, activeUserId: ownerA)
        XCTAssertThrowsError(try isolation.verifyOwnership(recordOwnerId: ownerA, activeUserId: ownerB)) { error in
            XCTAssertEqual(error as? LockInDomainError, .entityNotFound)
        }

        struct OwnedStub {
            let ownerId: UUID
            let label: String
        }
        let mixed = [
            OwnedStub(ownerId: ownerA, label: "A1"),
            OwnedStub(ownerId: ownerB, label: "B1"),
            OwnedStub(ownerId: ownerA, label: "A2")
        ]
        let onlyA = isolation.filterOwned(mixed, ownerIdKeyPath: \.ownerId, activeUserId: ownerA)
        XCTAssertEqual(onlyA.map(\.label), ["A1", "A2"])
    }

    @MainActor
    func testCrossUserOperationsRejectedAcrossDecksCardsTasksSchedulesAndThemes() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "IsolationPass#2026"

        _ = try await env.container.auth.register(
            username: "isolated_user_a",
            displayName: "User A",
            password: userCredential
        )
        let deckA = try await env.container.study.createDeck(
            title: "User A Deck",
            subjectTag: "Math",
            accentHex: "#2563EB",
            examDate: nil,
            dailyGoal: 12
        )
        let cardA = try await env.container.study.upsertCard(
            cardId: nil,
            deckId: deckA.id,
            question: "2 + 2 = ?",
            answer: "4",
            hintOrNote: "Arithmetic",
            status: .new
        )
        let taskA = try await env.container.study.createTask(
            title: "User A Task",
            notes: "Private",
            dueDate: nil,
            priority: .high,
            linkedDeckId: deckA.id
        )
        let scheduleA = try await env.container.scheduler.saveSchedule(
            scheduleId: nil,
            deckId: deckA.id,
            title: "User A Morning",
            hour: 7,
            minute: 30,
            weekdaysMask: 0b1111111,
            isEnabled: true,
            autoRotateTheme: false
        )
        _ = try await env.container.theme.selectTheme(themeId: ThemePalette.midnightInk.id)
        try await env.container.auth.logout()

        _ = try await env.container.auth.register(
            username: "isolated_user_b",
            displayName: "User B",
            password: userCredential
        )

        let decksB = try await env.container.study.fetchDecks()
        let tasksB = try await env.container.study.fetchTasks()
        let schedulesB = try await env.container.scheduler.fetchSchedules()
        XCTAssertTrue(decksB.isEmpty)
        XCTAssertTrue(tasksB.isEmpty)
        XCTAssertTrue(schedulesB.isEmpty)
        let prefB = try await env.container.theme.fetchPreference()
        XCTAssertEqual(prefB.activeThemeId, ThemePalette.minimalPaper.id)

        do {
            _ = try await env.container.study.fetchCards(deckId: deckA.id)
            XCTFail("User B không được phép đọc thẻ thuộc User A.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .entityNotFound)
        }

        do {
            _ = try await env.container.study.upsertCard(
                cardId: cardA.id,
                deckId: deckA.id,
                question: "Hijack",
                answer: "Hijack",
                hintOrNote: "",
                status: .mastered
            )
            XCTFail("User B không được phép sửa thẻ thuộc User A.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .entityNotFound)
        }

        do {
            _ = try await env.container.study.toggleTaskCompletion(taskId: taskA.id)
            XCTFail("User B không được phép thao tác task thuộc User A.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .entityNotFound)
        }

        do {
            try await env.container.scheduler.deleteSchedule(scheduleId: scheduleA.id)
            XCTFail("User B không được phép xóa lịch học thuộc User A.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .entityNotFound)
        }

        do {
            _ = try await env.container.study.createTask(
                title: "Cross-link Attempt",
                notes: "",
                dueDate: nil,
                priority: .low,
                linkedDeckId: deckA.id
            )
            XCTFail("User B không được gắn task vào bộ đề của User A.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .entityNotFound)
        }
    }

    @MainActor
    func testPurgeCurrentUserStudyDataKeepsOtherUsersIntact() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "PurgePass#2026"

        let userA = try await env.container.auth.register(
            username: "purge_keep_a",
            displayName: "Keep A",
            password: userCredential
        )
        let deckA = try await env.container.study.createDeck(
            title: "Keep Deck A",
            subjectTag: "Physics",
            accentHex: "#16A34A",
            examDate: nil,
            dailyGoal: 10
        )
        _ = try await env.container.study.upsertCard(
            cardId: nil,
            deckId: deckA.id,
            question: "F = ?",
            answer: "m * a",
            hintOrNote: "",
            status: .learning
        )
        try await env.container.auth.logout()

        _ = try await env.container.auth.register(
            username: "purge_wipe_b",
            displayName: "Wipe B",
            password: userCredential
        )
        _ = try await env.container.study.createDeck(
            title: "Wipe Deck B",
            subjectTag: "Chem",
            accentHex: "#FACC15",
            examDate: nil,
            dailyGoal: 10
        )
        _ = try await env.container.study.createTask(
            title: "Wipe Task B",
            notes: "",
            dueDate: nil,
            priority: .medium,
            linkedDeckId: nil
        )

        try await env.container.storageMaintenance.purgeCurrentUserStudyData()
        let purgedDecksB = try await env.container.study.fetchDecks()
        let purgedTasksB = try await env.container.study.fetchTasks()
        XCTAssertTrue(purgedDecksB.isEmpty)
        XCTAssertTrue(purgedTasksB.isEmpty)

        _ = try await env.container.auth.switchProfile(userId: userA.id, password: userCredential)
        let decksA = try await env.container.study.fetchDecks()
        XCTAssertEqual(decksA.map(\.title), ["Keep Deck A"])
        let cardsA = try await env.container.study.fetchCards(deckId: deckA.id)
        XCTAssertEqual(cardsA.count, 1)
    }

    func testAppGroupResolutionSupportsMobileProvisionSideloadAndFallbacks() throws {
        let syntheticPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Entitlements</key>
            <dict>
                <key>com.apple.security.application-groups</key>
                <array>
                    <string>group.com.lockin.shared.TEAM999</string>
                </array>
            </dict>
        </dict>
        </plist>
        """
        var cmsWrappedData = Data([0x30, 0x82, 0x01, 0x00, 0xFF, 0x00])
        cmsWrappedData.append(Data(syntheticPlist.utf8))
        cmsWrappedData.append(Data([0x01, 0x02, 0x03]))

        let extracted = AppConstants.extractAppGroups(fromMobileProvisionData: cmsWrappedData)
        XCTAssertEqual(extracted, ["group.com.lockin.shared.TEAM999"])
        XCTAssertTrue(AppConstants.extractAppGroups(fromMobileProvisionData: Data([0xDE, 0xAD, 0xBE, 0xEF])).isEmpty)

        // 1. Sideloaded iPhone (AltStore/SideStore/Sideloadly đổi App Group trong mobileprovision).
        let sideloadResolved = AppConstants.resolveAppGroupIdentifier(
            infoPlistGroupId: AppConstants.defaultAppGroupIdentifier,
            mobileProvisionGroups: extracted,
            bundleIdentifier: "com.lockin.app.TEAM999",
            isContainerAvailable: { $0 == "group.com.lockin.shared.TEAM999" }
        )
        XCTAssertEqual(sideloadResolved, "group.com.lockin.shared.TEAM999")

        // 2. Widget Extension bundle fallback khi thiếu mobileprovision hoặc Info.plist chưa khớp.
        let extensionFallback = AppConstants.resolveAppGroupIdentifier(
            infoPlistGroupId: nil,
            mobileProvisionGroups: [],
            bundleIdentifier: "com.custom.lockin.widgets",
            isContainerAvailable: { $0 == "group.com.custom.lockin" }
        )
        XCTAssertEqual(extensionFallback, "group.com.custom.lockin")

        // 3. TestFlight / chuẩn Xcode dùng Info.plist App Group.
        let standardResolved = AppConstants.resolveAppGroupIdentifier(
            infoPlistGroupId: AppConstants.defaultAppGroupIdentifier,
            mobileProvisionGroups: [],
            bundleIdentifier: AppConstants.defaultBundleIdentifier,
            isContainerAvailable: { $0 == AppConstants.defaultAppGroupIdentifier }
        )
        XCTAssertEqual(standardResolved, AppConstants.defaultAppGroupIdentifier)

        // 4. Simulator / Unit Test host (không có container) vẫn trả về mặc định an toàn.
        let hostFallback = AppConstants.resolveAppGroupIdentifier(
            infoPlistGroupId: "$(LOCKIN_APP_GROUP_ID)",
            mobileProvisionGroups: [],
            bundleIdentifier: AppConstants.defaultBundleIdentifier,
            isContainerAvailable: { _ in false }
        )
        XCTAssertEqual(hostFallback, AppConstants.defaultAppGroupIdentifier)
    }
}
