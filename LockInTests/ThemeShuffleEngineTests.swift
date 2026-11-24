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

    @MainActor
    func testSharedThemeRotationEnginePrioritizesDueScheduleAcrossMidnightAndPreservesPrivacy() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let credential = "ShortcutSchedule#2026"

        _ = try await env.container.auth.register(
            username: "shortcut_sched_owner",
            displayName: "Shortcut Schedule Owner",
            password: credential
        )
        _ = try await env.container.theme.updateShuffleConfiguration(
            isEnabled: false,
            poolIds: [ThemePalette.minimalPaper.id, ThemePalette.midnightInk.id],
            rotateOnAppOpen: false,
            rotateOnShortcutTrigger: false
        )
        _ = try await env.container.theme.updateLockScreenDisplayOptions(
            fontScale: .large,
            hideAnswerByDefault: true,
            privacyModeEnabled: true,
            showPopupOnOpen: true
        )

        let deckA = try await env.container.study.createDeck(
            title: "Initial Deck A",
            subjectTag: "General",
            accentHex: "#2563EB",
            examDate: nil,
            dailyGoal: 10
        )
        _ = try await env.container.study.upsertCard(
            cardId: nil,
            deckId: deckA.id,
            question: "Initial Q",
            answer: "Initial A",
            hintOrNote: "",
            status: .new
        )
        let seededSnap = try env.snapshotStore.loadSnapshot()
        let userId = try XCTUnwrap(seededSnap.activeUserId)
        let sessionEpoch = try XCTUnwrap(seededSnap.sessionEpoch)
        _ = try env.snapshotStore.mutateSnapshotIfSessionMatches(
            expectedUserId: userId,
            expectedSessionEpoch: sessionEpoch
        ) { state in
            state.activeDeckId = deckA.id
            state.activeDeckTitle = deckA.title
            state.currentCardQuestion = "Initial Q"
            state.currentCardAnswer = "Initial A"
            state.totalCardsInDeck = 1
        }

        let deckB = try await env.container.study.createDeck(
            title: "Shortcut Midnight Deck B",
            subjectTag: "Chemistry",
            accentHex: "#16A34A",
            examDate: nil,
            dailyGoal: 10
        )
        _ = try await env.container.study.upsertCard(
            cardId: nil,
            deckId: deckB.id,
            question: "Q-Midnight",
            answer: "A-Midnight",
            hintOrNote: "",
            status: .new
        )

        let cal = Calendar.current
        let monday = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12, minute: 0)))
        let tuesday0015 = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 0, minute: 15)))
        let mondayBit = 1 << (cal.component(.weekday, from: monday) - 1)

        let schedB = try await env.container.scheduler.saveSchedule(
            scheduleId: nil,
            deckId: deckB.id,
            title: "Shortcut TimeOfDay 23:30",
            hour: 23,
            minute: 30,
            weekdaysMask: mondayBit,
            isEnabled: true,
            autoRotateTheme: true
        )

        let sharedEngine = SharedThemeRotationEngine(
            modelContainer: env.modelContainer,
            snapshotStore: env.snapshotStore
        )

        // Chạy intent lúc 00:15 ngày hôm sau -> ưu tiên deckB từ lịch 23:30, xoay sang midnightInk và giữ Privacy Mode + Large font.
        let result1 = try await sharedEngine.rotateThemeInSharedStore(referenceDate: tuesday0015, calendar: cal)
        XCTAssertEqual(result1.prioritizedDeckId, deckB.id)
        XCTAssertTrue(result1.didRotateTheme)
        XCTAssertEqual(result1.nextTheme.id, ThemePalette.midnightInk.id)

        let snap1 = try env.snapshotStore.loadSnapshot()
        XCTAssertEqual(snap1.activeDeckId, deckB.id)
        XCTAssertEqual(snap1.currentCardQuestion, "Q-Midnight")
        XCTAssertEqual(snap1.activeThemeId, ThemePalette.midnightInk.id)
        XCTAssertTrue(snap1.privacyModeEnabled)
        XCTAssertEqual(snap1.fontScaleRaw, LockScreenFontScale.large.rawValue)

        // Tắt lịch B và bật lịch C cùng giờ với autoRotateTheme = false, rotateOnShortcutTrigger = false -> vẫn ưu tiên deckC nhưng giữ theme.
        _ = try await env.container.scheduler.saveSchedule(
            scheduleId: schedB.id,
            deckId: deckB.id,
            title: schedB.title,
            hour: schedB.hour,
            minute: schedB.minute,
            weekdaysMask: schedB.weekdaysMask,
            isEnabled: false,
            autoRotateTheme: true
        )

        let deckC = try await env.container.study.createDeck(
            title: "Shortcut Deck C Keep Theme",
            subjectTag: "History",
            accentHex: "#F59E0B",
            examDate: nil,
            dailyGoal: 10
        )
        _ = try await env.container.study.upsertCard(
            cardId: nil,
            deckId: deckC.id,
            question: "Q-History",
            answer: "A-History",
            hintOrNote: "",
            status: .new
        )
        _ = try await env.container.scheduler.saveSchedule(
            scheduleId: nil,
            deckId: deckC.id,
            title: "Shortcut C Keep Theme",
            hour: 23,
            minute: 30,
            weekdaysMask: mondayBit,
            isEnabled: true,
            autoRotateTheme: false
        )

        let result2 = try await sharedEngine.rotateThemeInSharedStore(referenceDate: tuesday0015, calendar: cal)
        XCTAssertEqual(result2.prioritizedDeckId, deckC.id)
        XCTAssertFalse(result2.didRotateTheme)
        XCTAssertEqual(result2.nextTheme.id, ThemePalette.midnightInk.id)

        let snap2 = try env.snapshotStore.loadSnapshot()
        XCTAssertEqual(snap2.activeDeckId, deckC.id)
        XCTAssertEqual(snap2.currentCardQuestion, "Q-History")
        XCTAssertEqual(snap2.activeThemeId, ThemePalette.midnightInk.id)
        XCTAssertTrue(snap2.privacyModeEnabled)
        XCTAssertEqual(snap2.fontScaleRaw, LockScreenFontScale.large.rawValue)
    }

    @MainActor
    func testSharedThemeRotationEngineRespectsShuffleAndShortcutToggleWhenNoScheduleIsDue() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let credential = "ShortcutToggle#2026"

        _ = try await env.container.auth.register(
            username: "shortcut_toggle_owner",
            displayName: "Shortcut Toggle Owner",
            password: credential
        )

        let sharedEngine = SharedThemeRotationEngine(
            modelContainer: env.modelContainer,
            snapshotStore: env.snapshotStore
        )
        let cal = Calendar.current
        let checkDate = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 14, minute: 0)))

        // Trường hợp 1: Không có lịch đến hạn, rotateOnShortcutTrigger = true nhưng isShuffleEnabled = false -> KHÔNG được xoay theme.
        _ = try await env.container.theme.updateShuffleConfiguration(
            isEnabled: false,
            poolIds: [ThemePalette.minimalPaper.id, ThemePalette.midnightInk.id],
            rotateOnAppOpen: false,
            rotateOnShortcutTrigger: true
        )
        let versionBeforeCase1 = try env.snapshotStore.loadSnapshot().snapshotVersion
        let resultCase1 = try await sharedEngine.rotateThemeInSharedStore(referenceDate: checkDate, calendar: cal)
        XCTAssertFalse(resultCase1.didRotateTheme)
        XCTAssertNil(resultCase1.prioritizedDeckId)
        XCTAssertEqual(resultCase1.nextTheme.id, ThemePalette.minimalPaper.id)
        XCTAssertEqual(resultCase1.snapshotVersion, versionBeforeCase1)
        let snapCase1 = try env.snapshotStore.loadSnapshot()
        XCTAssertEqual(snapCase1.activeThemeId, ThemePalette.minimalPaper.id)
        XCTAssertEqual(snapCase1.snapshotVersion, versionBeforeCase1)
        let prefCase1 = try await env.container.theme.fetchPreference()
        XCTAssertEqual(prefCase1.activeThemeId, ThemePalette.minimalPaper.id)

        // Trường hợp 2: Không có lịch đến hạn, isShuffleEnabled = true nhưng rotateOnShortcutTrigger = false -> KHÔNG được xoay theme.
        _ = try await env.container.theme.updateShuffleConfiguration(
            isEnabled: true,
            poolIds: [ThemePalette.minimalPaper.id, ThemePalette.midnightInk.id],
            rotateOnAppOpen: false,
            rotateOnShortcutTrigger: false
        )
        let versionBeforeCase2 = try env.snapshotStore.loadSnapshot().snapshotVersion
        let resultCase2 = try await sharedEngine.rotateThemeInSharedStore(referenceDate: checkDate, calendar: cal)
        XCTAssertFalse(resultCase2.didRotateTheme)
        XCTAssertNil(resultCase2.prioritizedDeckId)
        XCTAssertEqual(resultCase2.nextTheme.id, ThemePalette.minimalPaper.id)
        XCTAssertEqual(resultCase2.snapshotVersion, versionBeforeCase2)
        let snapCase2 = try env.snapshotStore.loadSnapshot()
        XCTAssertEqual(snapCase2.activeThemeId, ThemePalette.minimalPaper.id)
        let prefCase2 = try await env.container.theme.fetchPreference()
        XCTAssertEqual(prefCase2.activeThemeId, ThemePalette.minimalPaper.id)

        // Trường hợp 3: Không có lịch đến hạn, cả isShuffleEnabled và rotateOnShortcutTrigger đều bật -> Xoay sang midnightInk.
        _ = try await env.container.theme.updateShuffleConfiguration(
            isEnabled: true,
            poolIds: [ThemePalette.minimalPaper.id, ThemePalette.midnightInk.id],
            rotateOnAppOpen: false,
            rotateOnShortcutTrigger: true
        )
        let versionBeforeCase3 = try env.snapshotStore.loadSnapshot().snapshotVersion
        let resultCase3 = try await sharedEngine.rotateThemeInSharedStore(referenceDate: checkDate, calendar: cal)
        XCTAssertTrue(resultCase3.didRotateTheme)
        XCTAssertNil(resultCase3.prioritizedDeckId)
        XCTAssertEqual(resultCase3.nextTheme.id, ThemePalette.midnightInk.id)
        XCTAssertGreaterThan(resultCase3.snapshotVersion, versionBeforeCase3)
        let snapCase3 = try env.snapshotStore.loadSnapshot()
        XCTAssertEqual(snapCase3.activeThemeId, ThemePalette.midnightInk.id)
        let prefCase3 = try await env.container.theme.fetchPreference()
        XCTAssertEqual(prefCase3.activeThemeId, ThemePalette.midnightInk.id)
    }
}
