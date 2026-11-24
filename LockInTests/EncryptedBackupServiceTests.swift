// EncryptedBackupServiceTests.swift — Kiểm thử sao lưu mã hóa AES-GCM + PBKDF2 600k, overwrite/merge và cô lập UUID.
// Thuộc LockInTests (M4b); xác minh chống hỏng file, chống sai passphrase, rollback giao dịch và import chéo hồ sơ an toàn.

import XCTest
@testable import LockInApp

final class EncryptedBackupServiceTests: XCTestCase {
    @MainActor
    func testExportValidationWrongPassphraseTamperAndMaxSizeRejection() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "BackupAuth#2026"
        let backupPhrase = "BackupPhrase#2026"

        _ = try await env.container.auth.register(
            username: "backup_valid_owner",
            displayName: "Backup Owner",
            password: userCredential
        )
        _ = try await env.container.study.createDeck(
            title: "Algorithms",
            subjectTag: "CS",
            accentHex: "#2563EB",
            examDate: nil,
            dailyGoal: 15
        )

        do {
            _ = try await env.container.backup.exportEncryptedBackup(passphrase: "short")
            XCTFail("Mật khẩu sao lưu ngắn hơn 8 ký tự phải bị từ chối.")
        } catch let error as LockInDomainError {
            guard case .invalidPassword = error else {
                return XCTFail("Kỳ vọng invalidPassword, nhận: \(error)")
            }
        }

        let exportedData = try await env.container.backup.exportEncryptedBackup(passphrase: backupPhrase)
        XCTAssertGreaterThan(exportedData.count, 40)

        do {
            try await env.container.backup.importEncryptedBackup(
                exportedData,
                passphrase: "WrongBackupPhrase#99",
                mode: .merge
            )
            XCTFail("Giải mã bằng sai mật khẩu phải thất bại.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .backupCorruptedOrWrongPassphrase)
        }

        var corrupted = exportedData
        corrupted[corrupted.count - 5] ^= 0xFF
        do {
            try await env.container.backup.importEncryptedBackup(
                corrupted,
                passphrase: backupPhrase,
                mode: .merge
            )
            XCTFail("Tệp sao lưu bị sửa đổi byte phải bị từ chối.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .backupCorruptedOrWrongPassphrase)
        }

        let oversizedData = Data(count: AppConstants.maxBackupFileBytes + 1)
        do {
            try await env.container.backup.importEncryptedBackup(
                oversizedData,
                passphrase: backupPhrase,
                mode: .merge
            )
            XCTFail("Tệp vượt 10 MB phải bị từ chối.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .backupExceedsMaxSize)
        }
    }

    @MainActor
    func testOverwriteRestoreRecoversCompleteUserDataAndRemovesTempRecords() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "RestoreOwner#2026"
        let backupPhrase = "RestoreSecretPhrase#2026"

        _ = try await env.container.auth.register(
            username: "restore_owner",
            displayName: "Restore Owner",
            password: userCredential
        )
        let bioDeck = try await env.container.study.createDeck(
            title: "Bio 101",
            subjectTag: "Biology",
            accentHex: "#16A34A",
            examDate: nil,
            dailyGoal: 20
        )
        _ = try await env.container.study.upsertCard(
            cardId: nil,
            deckId: bioDeck.id,
            question: "ATP là gì?",
            answer: "Đồng tiền năng lượng tế bào",
            hintOrNote: "Chương 2",
            status: .learning
        )
        let originalTask = try await env.container.study.createTask(
            title: "Đọc chương Di truyền",
            notes: "Trang 40-55",
            dueDate: Date().addingTimeInterval(3600),
            priority: .high,
            linkedDeckId: bioDeck.id
        )
        _ = try await env.container.scheduler.saveSchedule(
            scheduleId: nil,
            deckId: bioDeck.id,
            title: "Ôn Sinh tối",
            hour: 20,
            minute: 15,
            weekdaysMask: 0b1111111,
            isEnabled: true,
            autoRotateTheme: true
        )
        _ = try await env.container.theme.selectTheme(themeId: ThemePalette.pastelMatcha.id)

        let backupData = try await env.container.backup.exportEncryptedBackup(passphrase: backupPhrase)

        try await env.container.study.deleteDeck(deckId: bioDeck.id)
        try await env.container.study.deleteTask(taskId: originalTask.id)
        _ = try await env.container.study.createDeck(
            title: "Temp Deck Should Vanish",
            subjectTag: "Temp",
            accentHex: "#2563EB",
            examDate: nil,
            dailyGoal: 5
        )

        // Nếu overwrite thất bại do sai mật khẩu, dữ liệu hiện tại vẫn phải còn nguyên (không xóa trước khi xác thực).
        do {
            try await env.container.backup.importEncryptedBackup(
                backupData,
                passphrase: "InvalidOverwritePass#1",
                mode: .overwrite
            )
            XCTFail("Sai passphrase trong chế độ overwrite phải báo lỗi.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .backupCorruptedOrWrongPassphrase)
        }
        let tempStillPresent = try await env.container.study.fetchDecks()
        XCTAssertEqual(tempStillPresent.map(\.title), ["Temp Deck Should Vanish"])

        try await env.container.backup.importEncryptedBackup(
            backupData,
            passphrase: backupPhrase,
            mode: .overwrite
        )

        let restoredDecks = try await env.container.study.fetchDecks()
        XCTAssertEqual(restoredDecks.map(\.title), ["Bio 101"])
        let restoredCards = try await env.container.study.fetchCards(deckId: bioDeck.id)
        XCTAssertEqual(restoredCards.map(\.question), ["ATP là gì?"])
        let restoredTasks = try await env.container.study.fetchTasks()
        XCTAssertEqual(restoredTasks.map(\.title), ["Đọc chương Di truyền"])
        let restoredSchedules = try await env.container.scheduler.fetchSchedules()
        XCTAssertEqual(restoredSchedules.map(\.title), ["Ôn Sinh tối"])
        let restoredPref = try await env.container.theme.fetchPreference()
        XCTAssertEqual(restoredPref.activeThemeId, ThemePalette.pastelMatcha.id)
    }

    @MainActor
    func testCrossUserImportRemapsUUIDsWithoutOverwritingSourceProfile() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let credentialA = "CrossUserA#2026"
        let credentialB = "CrossUserB#2026"
        let backupPhrase = "SharedCourseBackup#2026"

        let userA = try await env.container.auth.register(
            username: "backup_source_a",
            displayName: "Source A",
            password: credentialA
        )
        let deckA = try await env.container.study.createDeck(
            title: "IELTS Vocab",
            subjectTag: "English",
            accentHex: "#2563EB",
            examDate: nil,
            dailyGoal: 25
        )
        let cardA = try await env.container.study.upsertCard(
            cardId: nil,
            deckId: deckA.id,
            question: "Ubiquitous",
            answer: "Có mặt khắp nơi",
            hintOrNote: "Adj",
            status: .mastered
        )
        let taskA = try await env.container.study.createTask(
            title: "Ôn 10 từ IELTS",
            notes: "",
            dueDate: nil,
            priority: .high,
            linkedDeckId: deckA.id
        )
        let scheduleA = try await env.container.scheduler.saveSchedule(
            scheduleId: nil,
            deckId: deckA.id,
            title: "Lịch sáng IELTS",
            hour: 8,
            minute: 0,
            weekdaysMask: 0b0101010,
            isEnabled: true,
            autoRotateTheme: false
        )

        let backupData = try await env.container.backup.exportEncryptedBackup(passphrase: backupPhrase)
        try await env.container.auth.logout()

        let userB = try await env.container.auth.register(
            username: "backup_target_b",
            displayName: "Target B",
            password: credentialB
        )
        try await env.container.backup.importEncryptedBackup(
            backupData,
            passphrase: backupPhrase,
            mode: .merge
        )

        let decksB = try await env.container.study.fetchDecks()
        XCTAssertEqual(decksB.count, 1)
        let remappedDeckB = try XCTUnwrap(decksB.first)
        XCTAssertEqual(remappedDeckB.title, "IELTS Vocab")
        XCTAssertEqual(remappedDeckB.ownerUserId, userB.id)
        XCTAssertNotEqual(remappedDeckB.id, deckA.id)

        let cardsB = try await env.container.study.fetchCards(deckId: remappedDeckB.id)
        XCTAssertEqual(cardsB.count, 1)
        XCTAssertEqual(cardsB.first?.question, "Ubiquitous")
        XCTAssertNotEqual(cardsB.first?.id, cardA.id)

        let tasksB = try await env.container.study.fetchTasks()
        XCTAssertEqual(tasksB.count, 1)
        XCTAssertEqual(tasksB.first?.linkedDeckId, remappedDeckB.id)
        XCTAssertNotEqual(tasksB.first?.id, taskA.id)

        let schedulesB = try await env.container.scheduler.fetchSchedules()
        XCTAssertEqual(schedulesB.count, 1)
        XCTAssertEqual(schedulesB.first?.deckId, remappedDeckB.id)
        XCTAssertNotEqual(schedulesB.first?.id, scheduleA.id)

        // Xác minh hồ sơ gốc User A vẫn giữ nguyên vẹn bản ghi và UUID ban đầu.
        _ = try await env.container.auth.switchProfile(userId: userA.id, password: credentialA)
        let decksA = try await env.container.study.fetchDecks()
        XCTAssertEqual(decksA.map(\.id), [deckA.id])
        let cardsA = try await env.container.study.fetchCards(deckId: deckA.id)
        XCTAssertEqual(cardsA.map(\.id), [cardA.id])

        // Re-import chế độ merge trên chính chủ sở hữu không tạo bản sao trùng lặp.
        try await env.container.backup.importEncryptedBackup(
            backupData,
            passphrase: backupPhrase,
            mode: .merge
        )
        let finalDecksA = try await env.container.study.fetchDecks()
        let finalCardsA = try await env.container.study.fetchCards(deckId: deckA.id)
        XCTAssertEqual(finalDecksA.count, 1)
        XCTAssertEqual(finalCardsA.count, 1)
    }

    @MainActor
    func testReadBoundedBackupFileRejectsOversizedAndReadsValidFile() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "BoundedAuth#2026"
        let backupPhrase = "BoundedPass#2026"

        _ = try await env.container.auth.register(
            username: "bounded_backup_user",
            displayName: "Bounded User",
            password: userCredential
        )
        let deck = try await env.container.study.createDeck(
            title: "Bounded Deck",
            subjectTag: "Security",
            accentHex: "#2563EB",
            examDate: nil,
            dailyGoal: 10
        )

        let oversizedURL = env.tempDirectoryURL.appendingPathComponent("oversized.lockinbackup")
        let oversizedData = Data(count: AppConstants.maxBackupFileBytes + 2_048)
        try oversizedData.write(to: oversizedURL)

        XCTAssertThrowsError(try env.container.backup.readBoundedBackupFile(at: oversizedURL)) { error in
            XCTAssertEqual(error as? LockInDomainError, .backupExceedsMaxSize)
        }

        let exportedData = try await env.container.backup.exportEncryptedBackup(passphrase: backupPhrase)
        let validURL = env.tempDirectoryURL.appendingPathComponent("valid.lockinbackup")
        try exportedData.write(to: validURL)

        let readData = try env.container.backup.readBoundedBackupFile(at: validURL)
        XCTAssertEqual(readData, exportedData)

        try await env.container.study.deleteDeck(deckId: deck.id)
        try await env.container.backup.importEncryptedBackup(readData, passphrase: backupPhrase, mode: .overwrite)
        let restoredDecks = try await env.container.study.fetchDecks()
        XCTAssertEqual(restoredDecks.map(\.title), ["Bounded Deck"])
    }
}
