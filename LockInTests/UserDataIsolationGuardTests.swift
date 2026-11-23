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

        XCTAssertTrue(try await env.container.study.fetchDecks().isEmpty)
        XCTAssertTrue(try await env.container.study.fetchTasks().isEmpty)
        XCTAssertTrue(try await env.container.scheduler.fetchSchedules().isEmpty)
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
        XCTAssertTrue(try await env.container.study.fetchDecks().isEmpty)
        XCTAssertTrue(try await env.container.study.fetchTasks().isEmpty)

        _ = try await env.container.auth.switchProfile(userId: userA.id, password: userCredential)
        let decksA = try await env.container.study.fetchDecks()
        XCTAssertEqual(decksA.map(\.title), ["Keep Deck A"])
        let cardsA = try await env.container.study.fetchCards(deckId: deckA.id)
        XCTAssertEqual(cardsA.count, 1)
    }
}
