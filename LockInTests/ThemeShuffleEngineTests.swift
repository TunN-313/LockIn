// ThemeShuffleEngineTests.swift — Kiểm thử xoay vòng theme Shuffle Pool, đồng bộ Store và giới hạn 4KB ActivityKit.
// Thuộc LockInTests (M4b); xác minh SharedThemeRotationEngine không nhân đôi logic và payload ContentState luôn < 4,096 bytes.

import XCTest
@testable import LockInApp

final class ThemeShuffleEngineTests: XCTestCase {
    @MainActor
    func testSelectNextThemeIdHandlesMultiSingleEmptyAndInvalidPools() throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }

        let sharedEngine = SharedThemeRotationEngine(
            modelContainer: env.modelContainer,
            snapshotStore: env.snapshotStore
        )

        let multiPool = [
            ThemePalette.minimalPaper.id,
            ThemePalette.darkFocus.id,
            ThemePalette.midnightInk.id,
            ThemePalette.darkFocus.id
        ]
        for _ in 0..<25 {
            let chosen = sharedEngine.selectNextThemeId(
                currentThemeId: ThemePalette.minimalPaper.id,
                shufflePoolIds: multiPool
            )
            XCTAssertNotEqual(chosen, ThemePalette.minimalPaper.id)
            XCTAssertTrue([ThemePalette.darkFocus.id, ThemePalette.midnightInk.id].contains(chosen))
        }

        let singleChoice = sharedEngine.selectNextThemeId(
            currentThemeId: ThemePalette.darkFocus.id,
            shufflePoolIds: [ThemePalette.darkFocus.id]
        )
        XCTAssertEqual(singleChoice, ThemePalette.darkFocus.id)

        let invalidPoolFallback = sharedEngine.selectNextThemeId(
            currentThemeId: ThemePalette.darkFocus.id,
            shufflePoolIds: ["non_existent_theme", "another_fake_id"]
        )
        XCTAssertEqual(invalidPoolFallback, ThemePalette.minimalPaper.id)
    }

    @MainActor
    func testRotateThemeIfNeededAndSharedEnginePersistAcrossStore() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "ThemeOwner#2026"

        _ = try await env.container.auth.register(
            username: "theme_shuffle_owner",
            displayName: "Theme Owner",
            password: userCredential
        )

        let builtIn = env.container.theme.builtInThemes()
        XCTAssertEqual(builtIn.count, 6)

        _ = try await env.container.theme.updateShuffleConfiguration(
            isEnabled: true,
            poolIds: [ThemePalette.minimalPaper.id, ThemePalette.midnightInk.id],
            rotateOnAppOpen: false,
            rotateOnShortcutTrigger: true
        )

        let blockedOnAppOpen = try await env.container.theme.rotateThemeIfNeeded(triggerOnAppOpen: true)
        XCTAssertEqual(blockedOnAppOpen.id, ThemePalette.minimalPaper.id)

        let rotatedOnShortcut = try await env.container.theme.rotateThemeIfNeeded(triggerOnAppOpen: false)
        XCTAssertEqual(rotatedOnShortcut.id, ThemePalette.midnightInk.id)
        XCTAssertEqual(try env.snapshotStore.loadSnapshot().activeThemeId, ThemePalette.midnightInk.id)

        // SharedThemeRotationEngine dùng chung trong Extension xoay vòng tiếp từ midnightInk về minimalPaper.
        let versionBeforeShared = try env.snapshotStore.loadSnapshot().snapshotVersion
        let sharedEngine = SharedThemeRotationEngine(
            modelContainer: env.modelContainer,
            snapshotStore: env.snapshotStore
        )
        let rotationResult = try await sharedEngine.rotateThemeInSharedStore()
        XCTAssertEqual(rotationResult.previousThemeId, ThemePalette.midnightInk.id)
        XCTAssertEqual(rotationResult.nextTheme.id, ThemePalette.minimalPaper.id)
        XCTAssertGreaterThan(rotationResult.snapshotVersion, versionBeforeShared)

        let updatedPref = try await env.container.theme.fetchPreference()
        XCTAssertEqual(updatedPref.activeThemeId, ThemePalette.minimalPaper.id)
    }

    func testLiveActivityContentStatePayloadNeverExceeds4KBLimit() throws {
        let longMultibyteQuestion = String(repeating: "📚", count: 250)
        let longMultibyteAnswer = String(repeating: "🧠", count: 250)
        let longTitle = String(repeating: "🌟Lớp-Ôn-Thi-Cuối-Kỳ-", count: 20)

        let safeState = StudySessionAttributes.ContentState.makeSafe(
            deckId: UUID(),
            deckTitle: longTitle,
            currentCardId: UUID(),
            questionText: longMultibyteQuestion,
            answerText: longMultibyteAnswer,
            isAnswerVisible: true,
            currentIndex: -5,
            totalCards: 40,
            masteredCount: 12,
            activeThemeId: "hacked_🌊_injected_theme",
            privacyModeEnabled: false,
            fontScaleRaw: "enormous_🧨_font"
        )

        XCTAssertEqual(safeState.activeThemeId, ThemePalette.minimalPaper.id)
        XCTAssertEqual(safeState.fontScaleRaw, LockScreenFontScale.standard.rawValue)
        XCTAssertEqual(safeState.currentIndex, 0)
        XCTAssertLessThanOrEqual(safeState.deckTitle.count, AppConstants.maxLiveActivityDeckTitleLength)
        XCTAssertLessThanOrEqual(safeState.questionText.count, AppConstants.maxLiveActivityTextLength)
        XCTAssertLessThanOrEqual(safeState.answerText.count, AppConstants.maxLiveActivityTextLength)
        XCTAssertTrue(safeState.isWithinActivityKitPayloadLimit)
        XCTAssertLessThan(safeState.estimatedJSONByteCount(), AppConstants.maxLiveActivityContentStateBytes)

        // Kiểm chứng cả luồng JSON decode cũng chạy qua chuẩn hóa.
        let encoded = try JSONEncoder().encode(safeState)
        let decoded = try JSONDecoder().decode(StudySessionAttributes.ContentState.self, from: encoded)
        XCTAssertTrue(decoded.isWithinActivityKitPayloadLimit)
    }

    @MainActor
    func testLockScreenWizardDelegatesNotificationsAndPhotoSaveToBackend() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "WizardOwner#2026"

        _ = try await env.container.auth.register(
            username: "wizard_delegate_tester",
            displayName: "Wizard Tester",
            password: userCredential
        )
        let deck = try await env.container.study.createDeck(
            title: "Wizard Deck",
            subjectTag: "Physics",
            accentHex: "#2563EB",
            examDate: nil,
            dailyGoal: 10
        )
        _ = try await env.container.study.upsertCard(
            cardId: nil,
            deckId: deck.id,
            question: "E = ?",
            answer: "mc^2",
            hintOrNote: "",
            status: .new
        )

        env.notificationService.authorized = false
        let denied = try await env.container.lockScreen.requestNotificationPermissionForWizard()
        XCTAssertFalse(denied)

        env.notificationService.authorized = true
        let granted = try await env.container.lockScreen.requestNotificationPermissionForWizard()
        XCTAssertTrue(granted)

        let payload = try await env.container.lockScreen.renderStudyWallpaperPNG(deckId: deck.id, maxLines: 3)
        try await env.container.lockScreen.saveWallpaperPNGToPhotos(payload.pngData)
        XCTAssertEqual(env.photoLibrarySaver.savedPayloads.count, 1)
        XCTAssertEqual(env.photoLibrarySaver.savedPayloads.first, payload.pngData)

        env.photoLibrarySaver.allowSave = false
        do {
            try await env.container.lockScreen.saveWallpaperPNGToPhotos(payload.pngData)
            XCTFail("Khi không có quyền Photos phải ném lỗi.")
        } catch let error as LockInDomainError {
            guard case .validationFailed = error else {
                return XCTFail("Kỳ vọng validationFailed, nhận: \(error)")
            }
        }
    }
}
