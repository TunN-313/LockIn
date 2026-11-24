// LiveActivityBridgeService.swift — Điều phối Live Activity (foreground request), đồng bộ AppGroupSnapshotStore và Wallpaper PNG.
// Triển khai LockScreenModuleProtocol thuộc Backend/LockScreenModule.

import ActivityKit
import Foundation
import SwiftData
import WidgetKit

private struct SnapshotStoreSyncPayload: Sendable {
    let activeThemeId: String
    let isShuffleEnabled: Bool
    let shufflePoolIds: [String]
    let privacyModeEnabled: Bool
    let fontScaleRaw: String
    let hideAnswerByDefault: Bool
    let progressRatio: Double
    let streak: Int
    let nextTaskId: UUID?
    let nextTaskTitle: String?
    let deckTitle: String?
    let cards: [(id: UUID, question: String, answer: String, isMastered: Bool)]
}

public final class LiveActivityBridgeService: LockScreenModuleProtocol, @unchecked Sendable {
    private let studyStore: SwiftDataStudyStore
    private let isolationGuard: UserDataIsolationGuardProtocol
    private let snapshotStore: AppGroupSnapshotStoreProtocol
    private let permissionChecker: DevicePermissionCheckerProtocol
    private let wallpaperRenderer: StudyWallpaperRenderServiceProtocol
    private let schedulerModule: SchedulerModuleProtocol
    private let photoLibrarySaver: PhotoLibrarySaverProtocol
    private let syncEventBus: SyncEventBus

    public init(
        studyStore: SwiftDataStudyStore,
        isolationGuard: UserDataIsolationGuardProtocol,
        snapshotStore: AppGroupSnapshotStoreProtocol,
        permissionChecker: DevicePermissionCheckerProtocol,
        wallpaperRenderer: StudyWallpaperRenderServiceProtocol,
        schedulerModule: SchedulerModuleProtocol,
        photoLibrarySaver: PhotoLibrarySaverProtocol = PhotoLibrarySaver(),
        syncEventBus: SyncEventBus
    ) {
        self.studyStore = studyStore
        self.isolationGuard = isolationGuard
        self.snapshotStore = snapshotStore
        self.permissionChecker = permissionChecker
        self.wallpaperRenderer = wallpaperRenderer
        self.schedulerModule = schedulerModule
        self.photoLibrarySaver = photoLibrarySaver
        self.syncEventBus = syncEventBus
    }

    public func requestNotificationPermissionForWizard() async throws -> Bool {
        try await schedulerModule.requestNotificationPermission()
    }

    public func saveWallpaperPNGToPhotos(_ pngData: Data) async throws {
        guard !pngData.isEmpty else {
            throw LockInDomainError.validationFailed("Chưa có dữ liệu ảnh PNG hợp lệ để lưu vào Thư viện ảnh.")
        }
        try await photoLibrarySaver.savePNGDataToPhotos(pngData)
    }

    public func checkBridgeStatus() async -> LockScreenBridgeStatus {
        let snapshot = try? snapshotStore.loadSnapshot()
        return await permissionChecker.checkBridgeStatus(
            activeDeckId: snapshot?.activeDeckId,
            activeDeckTitle: snapshot?.activeDeckTitle
        )
    }

    public func startOrUpdateLiveActivity(forDeckId deckId: UUID) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LockInDomainError.liveActivitiesDisabled
        }

        let session = try isolationGuard.requireActiveSession()
        let deckState = try await loadDeckAndCardsSnapshotData(deckId: deckId, userId: session.userId)

        let updatedSnapshot = try snapshotStore.mutateSnapshotIfSessionMatches(
            expectedUserId: session.userId,
            expectedSessionEpoch: session.sessionEpoch
        ) { state in
            state.activeDeckId = deckState.deckId
            state.activeDeckTitle = deckState.deckTitle
            state.currentCardId = deckState.firstCard?.id
            state.currentCardQuestion = deckState.firstCard?.question ?? "Bộ đề chưa có thẻ ôn."
            state.currentCardAnswer = deckState.firstCard?.answer ?? ""
            state.currentCardIndex = 0
            state.totalCardsInDeck = deckState.totalCards
            state.masteredCountInDeck = deckState.masteredCards
            state.isAnswerVisible = !deckState.hideAnswerByDefault
            state.activeThemeId = deckState.activeThemeId
            state.privacyModeEnabled = deckState.privacyModeEnabled
            state.fontScaleRaw = deckState.fontScaleRaw
            state.dailyProgressRatio = deckState.progressRatio
            state.streakCount = deckState.streakCount
        }

        let contentState = SharedCardNavigationEngine.makeContentState(from: updatedSnapshot)
        let payloadBytes = contentState.estimatedJSONByteCount()
        guard contentState.isWithinActivityKitPayloadLimit else {
            throw LockInDomainError.payloadExceedsLimit(bytes: payloadBytes)
        }

        let content = ActivityContent(state: contentState, staleDate: nil)
        let activeActivities = Activity<StudySessionAttributes>.activities
        if let existing = activeActivities.first {
            await existing.update(content)
        } else {
            let attributes = StudySessionAttributes()
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        }

        WidgetCenter.shared.reloadAllTimelines()
        CrossProcessNotifier.postStateDidChange()

        let marker = SnapshotStateMarker(
            version: updatedSnapshot.snapshotVersion,
            revisionId: updatedSnapshot.snapshotRevisionId
        )
        await MainActor.run {
            syncEventBus.publish(.cardsChanged(deckId: deckId), observedMarker: marker)
        }
    }

    public func stopActiveLiveActivity() async {
        for activity in Activity<StudySessionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    public func syncSnapshotFromStore() async throws {
        let session = try isolationGuard.requireActiveSession()

        for attempt in 0..<3 {
            let snapshot = try snapshotStore.loadSnapshot()
            guard snapshot.activeUserId == session.userId,
                  snapshot.sessionEpoch == session.sessionEpoch else {
                throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
            }
            let observedDeckId = snapshot.activeDeckId
            let observedRevisionId = snapshot.snapshotRevisionId

            let data: SnapshotStoreSyncPayload = try await studyStore.perform { context in
                let uid = session.userId
                let pref = try ThemeCatalogService.fetchOrCreatePreference(for: uid, in: context)
                let progress = try SharedDailyProgressHelper.fetchOrCreateTodayProgress(for: uid, in: context)
                let pendingTasks = try context.fetch(
                    FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.ownerUserId == uid && $0.isCompleted == false })
                ).sorted(by: SharedTaskQuickActionEngine.sortTasks)

                var deckTitle: String?
                var cards: [(id: UUID, question: String, answer: String, isMastered: Bool)] = []
                if let deckId = observedDeckId {
                    let targetDeckId = deckId
                    if let deck = try context.fetch(
                        FetchDescriptor<StudyDeck>(predicate: #Predicate<StudyDeck> { $0.id == targetDeckId && $0.ownerUserId == uid })
                    ).first {
                        deckTitle = deck.title
                        cards = deck.cards
                            .filter { $0.ownerUserId == uid }
                            .sorted { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) }
                            .map { ($0.id, $0.question, $0.answer, $0.status == .mastered) }
                    }
                }

                try context.save()
                return SnapshotStoreSyncPayload(
                    activeThemeId: pref.activeThemeId,
                    isShuffleEnabled: pref.isShuffleEnabled,
                    shufflePoolIds: pref.shufflePoolIds,
                    privacyModeEnabled: pref.privacyModeEnabled,
                    fontScaleRaw: pref.lockScreenFontScale,
                    hideAnswerByDefault: pref.hideAnswerByDefault,
                    progressRatio: SharedDailyProgressHelper.completionRatio(for: progress),
                    streak: progress.streakCount,
                    nextTaskId: pendingTasks.first?.id,
                    nextTaskTitle: pendingTasks.first?.title,
                    deckTitle: deckTitle,
                    cards: cards
                )
            }

            do {
                let updatedSnapshot = try snapshotStore.mutateSnapshotIfSessionMatches(
                    expectedUserId: session.userId,
                    expectedSessionEpoch: session.sessionEpoch,
                    expectedRevisionId: observedRevisionId
                ) { state in
                    guard state.activeDeckId == observedDeckId else {
                        throw AppGroupStorageError.staleSnapshotRevision(
                            expected: observedRevisionId,
                            actual: state.snapshotRevisionId
                        )
                    }

                    state.activeThemeId = data.activeThemeId
                    state.isShuffleEnabled = data.isShuffleEnabled
                    state.shufflePoolIds = data.shufflePoolIds
                    state.privacyModeEnabled = data.privacyModeEnabled
                    state.fontScaleRaw = data.fontScaleRaw
                    state.dailyProgressRatio = data.progressRatio
                    state.streakCount = data.streak
                    state.nextTaskId = data.nextTaskId
                    state.nextTaskTitle = data.nextTaskTitle

                    if let deckTitle = data.deckTitle {
                        state.activeDeckTitle = deckTitle
                        state.totalCardsInDeck = data.cards.count
                        state.masteredCountInDeck = data.cards.filter(\.isMastered).count
                        if data.cards.isEmpty {
                            state.currentCardId = nil
                            state.currentCardQuestion = "Chưa có thẻ nào trong bộ đề."
                            state.currentCardAnswer = ""
                            state.currentCardIndex = 0
                            state.isAnswerVisible = false
                        } else if let currentCardId = state.currentCardId,
                                  let matchedIndex = data.cards.firstIndex(where: { $0.id == currentCardId }) {
                            let card = data.cards[matchedIndex]
                            state.currentCardIndex = matchedIndex
                            state.currentCardId = card.id
                            state.currentCardQuestion = card.question
                            state.currentCardAnswer = card.answer
                        } else {
                            let safeIndex = min(max(0, state.currentCardIndex), data.cards.count - 1)
                            let card = data.cards[safeIndex]
                            state.currentCardIndex = safeIndex
                            state.currentCardId = card.id
                            state.currentCardQuestion = card.question
                            state.currentCardAnswer = card.answer
                            state.isAnswerVisible = !data.hideAnswerByDefault
                        }
                    } else if observedDeckId != nil {
                        state.activeDeckId = nil
                        state.activeDeckTitle = ""
                        state.currentCardId = nil
                        state.currentCardQuestion = ""
                        state.currentCardAnswer = ""
                        state.currentCardIndex = 0
                        state.totalCardsInDeck = 0
                        state.masteredCountInDeck = 0
                        state.isAnswerVisible = false
                    }
                }

                if let activeDeckId = updatedSnapshot.activeDeckId {
                    let contentState = SharedCardNavigationEngine.makeContentState(from: updatedSnapshot)
                    let content = ActivityContent(state: contentState, staleDate: nil)
                    for activity in Activity<StudySessionAttributes>.activities {
                        if activity.content.state.deckId == activeDeckId {
                            await activity.update(content)
                        } else {
                            await activity.end(nil, dismissalPolicy: .immediate)
                        }
                    }
                } else {
                    for activity in Activity<StudySessionAttributes>.activities {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                }

                WidgetCenter.shared.reloadAllTimelines()
                CrossProcessNotifier.postStateDidChange()
                return
            } catch let error as AppGroupStorageError {
                if case .staleSnapshotRevision = error, attempt < 2 {
                    continue
                }
                throw error
            }
        }
    }

    public func renderStudyWallpaperPNG(deckId: UUID?, maxLines: Int) async throws -> WallpaperRenderPayload {
        let userId = try isolationGuard.requireActiveUserId()
        let clampedLimit = min(5, max(1, maxLines))

        let renderInput: (title: String, lines: [String], palette: ThemePalette) = try await studyStore.perform { context in
            let uid = userId
            let pref = try ThemeCatalogService.fetchOrCreatePreference(for: uid, in: context)
            let palette = ThemePalette.palette(for: pref.activeThemeId)

            var chosenTitle = "Tài liệu ôn thi LockIn"
            var lines: [String] = []

            if let targetDeckId = deckId {
                let did = targetDeckId
                if let deck = try context.fetch(
                    FetchDescriptor<StudyDeck>(predicate: #Predicate<StudyDeck> { $0.id == did && $0.ownerUserId == uid })
                ).first {
                    chosenTitle = deck.title
                    let cards = deck.cards
                        .filter { $0.ownerUserId == uid }
                        .sorted { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) }
                    lines = cards.prefix(clampedLimit).map { card in
                        "\(card.question) → \(card.answer)"
                    }
                }
            }

            if lines.isEmpty {
                let tasks = try context.fetch(
                    FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.ownerUserId == uid && $0.isCompleted == false })
                ).sorted(by: SharedTaskQuickActionEngine.sortTasks)
                lines = tasks.prefix(clampedLimit).map(\.title)
            }

            if lines.isEmpty {
                lines = ["Thêm thẻ ôn thi hoặc tác vụ trong tab Học & Tác vụ."]
            }

            return (chosenTitle, lines, palette)
        }

        return try await MainActor.run {
            try wallpaperRenderer.renderSummaryPNG(
                deckTitle: renderInput.title,
                summaryLines: renderInput.lines,
                palette: renderInput.palette
            )
        }
    }

    private func loadDeckAndCardsSnapshotData(
        deckId: UUID,
        userId: UUID
    ) async throws -> (
        deckId: UUID,
        deckTitle: String,
        firstCard: (id: UUID, question: String, answer: String)?,
        totalCards: Int,
        masteredCards: Int,
        hideAnswerByDefault: Bool,
        activeThemeId: String,
        privacyModeEnabled: Bool,
        fontScaleRaw: String,
        progressRatio: Double,
        streakCount: Int
    ) {
        try await studyStore.perform { context in
            let uid = userId
            let targetDeckId = deckId
            guard let deck = try context.fetch(
                FetchDescriptor<StudyDeck>(predicate: #Predicate<StudyDeck> { $0.id == targetDeckId && $0.ownerUserId == uid })
            ).first else {
                throw LockInDomainError.entityNotFound
            }

            let orderedCards = deck.cards
                .filter { $0.ownerUserId == uid }
                .sorted { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) }

            let pref = try ThemeCatalogService.fetchOrCreatePreference(for: uid, in: context)
            let progress = try SharedDailyProgressHelper.fetchOrCreateTodayProgress(for: uid, in: context)
            try context.save()

            let first = orderedCards.first.map { ($0.id, $0.question, $0.answer) }
            let mastered = orderedCards.filter { $0.status == .mastered }.count

            return (
                deck.id,
                deck.title,
                first,
                orderedCards.count,
                mastered,
                pref.hideAnswerByDefault,
                pref.activeThemeId,
                pref.privacyModeEnabled,
                pref.lockScreenFontScale,
                SharedDailyProgressHelper.completionRatio(for: progress),
                progress.streakCount
            )
        }
    }
}
