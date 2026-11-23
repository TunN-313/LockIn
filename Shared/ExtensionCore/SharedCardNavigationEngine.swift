// SharedCardNavigationEngine.swift — Cài đặt điều hướng thẻ (Flip/Next/Prev/MarkMastered) dùng chung qua SharedAppGroup.
// Chỉ phụ thuộc Shared/**; khóa flock + expectedRevisionId trước khi lưu SwiftData và giữ nguyên theme/Privacy Mode mới nhất.

import ActivityKit
import Foundation
import SwiftData
import WidgetKit

public enum CardNavigationAction: String, Codable, Sendable {
    case flip
    case next
    case previous
    case markMastered
}

public struct CardNavigationResult: Equatable, Sendable {
    public let contentState: StudySessionAttributes.ContentState
    public let snapshot: LockScreenSnapshot

    public init(contentState: StudySessionAttributes.ContentState, snapshot: LockScreenSnapshot) {
        self.contentState = contentState
        self.snapshot = snapshot
    }
}

public protocol SharedCardNavigationEngineProtocol: Sendable {
    func perform(action: CardNavigationAction) async throws -> CardNavigationResult
    func loadCurrentContentState() async throws -> StudySessionAttributes.ContentState?
}

public enum SharedDailyProgressHelper {
    public static func dateKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 2026
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    @discardableResult
    public static func fetchOrCreateTodayProgress(
        for userId: UUID,
        in context: ModelContext,
        referenceDate: Date = Date(),
        defaultTarget: Int = 20
    ) throws -> DailyProgress {
        let key = dateKey(for: referenceDate)
        let uid = userId
        let descriptor = FetchDescriptor<DailyProgress>(
            predicate: #Predicate<DailyProgress> { $0.ownerUserId == uid && $0.dateKey == key }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let previousStreak = try carriedOverStreakBeforeToday(for: userId, in: context, today: referenceDate)
        let created = DailyProgress(
            ownerUserId: userId,
            dateKey: key,
            cardsReviewed: 0,
            cardsMastered: 0,
            tasksCompleted: 0,
            dailyTargetCount: max(1, defaultTarget),
            streakCount: previousStreak
        )
        context.insert(created)
        return created
    }

    public static func recordActivity(
        on progress: DailyProgress,
        cardsReviewedDelta: Int = 0,
        cardsMasteredDelta: Int = 0,
        tasksCompletedDelta: Int = 0,
        in context: ModelContext,
        referenceDate: Date = Date()
    ) throws {
        let hadActivityBefore = (progress.cardsReviewed + progress.tasksCompleted) > 0
        progress.cardsReviewed += max(0, cardsReviewedDelta)
        progress.cardsMastered += max(0, cardsMasteredDelta)
        progress.tasksCompleted += max(0, tasksCompletedDelta)
        let hasActivityNow = (progress.cardsReviewed + progress.tasksCompleted) > 0

        if !hadActivityBefore && hasActivityNow {
            let carriedStreak = try carriedOverStreakBeforeToday(
                for: progress.ownerUserId,
                in: context,
                today: referenceDate
            )
            progress.streakCount = carriedStreak + 1
        }
    }

    public static func completionRatio(for progress: DailyProgress) -> Double {
        guard progress.dailyTargetCount > 0 else { return 0 }
        let completed = progress.cardsReviewed + progress.tasksCompleted
        return min(1.0, Double(completed) / Double(progress.dailyTargetCount))
    }

    private static func carriedOverStreakBeforeToday(
        for userId: UUID,
        in context: ModelContext,
        today: Date
    ) throws -> Int {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) else {
            return 0
        }
        let yesterdayKey = dateKey(for: yesterday)
        let uid = userId
        let descriptor = FetchDescriptor<DailyProgress>(
            predicate: #Predicate<DailyProgress> { $0.ownerUserId == uid && $0.dateKey == yesterdayKey }
        )
        guard let yesterdayRecord = try context.fetch(descriptor).first,
              (yesterdayRecord.cardsReviewed + yesterdayRecord.tasksCompleted) > 0 else {
            return 0
        }
        return max(1, yesterdayRecord.streakCount)
    }
}

public final class SharedCardNavigationEngine: SharedCardNavigationEngineProtocol, @unchecked Sendable {
    private let modelContainer: ModelContainer
    private let snapshotStore: AppGroupSnapshotStoreProtocol

    public init(modelContainer: ModelContainer, snapshotStore: AppGroupSnapshotStoreProtocol) {
        self.modelContainer = modelContainer
        self.snapshotStore = snapshotStore
    }

    public static func makeShared() throws -> SharedCardNavigationEngine {
        let container = try SharedStoreContainer.makeShared()
        let store = try AppGroupSnapshotStore.makeShared()
        return SharedCardNavigationEngine(modelContainer: container, snapshotStore: store)
    }

    public func loadCurrentContentState() async throws -> StudySessionAttributes.ContentState? {
        let snapshot = try snapshotStore.loadSnapshot()
        guard snapshot.activeUserId != nil,
              snapshot.sessionEpoch != nil,
              let deckId = snapshot.activeDeckId else {
            return nil
        }
        return StudySessionAttributes.ContentState.makeSafe(
            deckId: deckId,
            deckTitle: snapshot.activeDeckTitle,
            currentCardId: snapshot.currentCardId,
            questionText: snapshot.currentCardQuestion,
            answerText: snapshot.currentCardAnswer,
            isAnswerVisible: snapshot.isAnswerVisible,
            currentIndex: snapshot.currentCardIndex,
            totalCards: snapshot.totalCardsInDeck,
            masteredCount: snapshot.masteredCountInDeck,
            activeThemeId: snapshot.activeThemeId,
            privacyModeEnabled: snapshot.privacyModeEnabled,
            fontScaleRaw: snapshot.fontScaleRaw
        )
    }

    public func perform(action: CardNavigationAction) async throws -> CardNavigationResult {
        for attempt in 0..<2 {
            let initialSnapshot = try snapshotStore.loadSnapshot()
            guard let userId = initialSnapshot.activeUserId,
                  let sessionEpoch = initialSnapshot.sessionEpoch,
                  let deckId = initialSnapshot.activeDeckId else {
                throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
            }

            let context = ModelContext(modelContainer)
            let uid = userId
            let targetDeckId = deckId

            let deckDescriptor = FetchDescriptor<StudyDeck>(
                predicate: #Predicate<StudyDeck> { $0.ownerUserId == uid && $0.id == targetDeckId }
            )
            guard let deck = try context.fetch(deckDescriptor).first else {
                throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
            }

            let orderedCards = deck.cards
                .filter { $0.ownerUserId == uid }
                .sorted {
                    if $0.sortOrder != $1.sortOrder {
                        return $0.sortOrder < $1.sortOrder
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }

            let prefDescriptor = FetchDescriptor<ThemePreference>(
                predicate: #Predicate<ThemePreference> { $0.ownerUserId == uid }
            )
            let hideAnswerByDefault = try context.fetch(prefDescriptor).first?.hideAnswerByDefault ?? true

            do {
                let updatedSnapshot = try snapshotStore.mutateSnapshotIfSessionMatches(
                    expectedUserId: userId,
                    expectedSessionEpoch: sessionEpoch,
                    expectedRevisionId: initialSnapshot.snapshotRevisionId
                ) { state in
                    guard state.activeDeckId == deck.id,
                          state.currentCardId == initialSnapshot.currentCardId else {
                        throw AppGroupStorageError.staleSnapshotRevision(
                            expected: initialSnapshot.snapshotRevisionId,
                            actual: state.snapshotRevisionId
                        )
                    }

                    guard !orderedCards.isEmpty else {
                        state.activeDeckTitle = deck.title
                        state.currentCardId = nil
                        state.currentCardQuestion = "Chưa có thẻ nào trong bộ đề."
                        state.currentCardAnswer = ""
                        state.currentCardIndex = 0
                        state.totalCardsInDeck = 0
                        state.masteredCountInDeck = 0
                        state.isAnswerVisible = false
                        return
                    }

                    let currentIndex: Int = {
                        if let currentId = state.currentCardId,
                           let matchedIndex = orderedCards.firstIndex(where: { $0.id == currentId }) {
                            return matchedIndex
                        }
                        return min(max(0, state.currentCardIndex), orderedCards.count - 1)
                    }()

                    let todayProgress = try SharedDailyProgressHelper.fetchOrCreateTodayProgress(
                        for: userId,
                        in: context,
                        defaultTarget: max(1, deck.dailyGoal)
                    )

                    var nextIndex = currentIndex
                    var nextAnswerVisible = state.isAnswerVisible

                    switch action {
                    case .flip:
                        nextAnswerVisible.toggle()
                    case .next:
                        nextIndex = (currentIndex + 1) % orderedCards.count
                        nextAnswerVisible = !hideAnswerByDefault
                        let nextCard = orderedCards[nextIndex]
                        nextCard.reviewCount += 1
                        nextCard.lastReviewedAt = Date()
                        if nextCard.status == .new {
                            nextCard.status = .learning
                        }
                        try SharedDailyProgressHelper.recordActivity(
                            on: todayProgress,
                            cardsReviewedDelta: 1,
                            in: context
                        )
                    case .previous:
                        nextIndex = (currentIndex - 1 + orderedCards.count) % orderedCards.count
                        nextAnswerVisible = !hideAnswerByDefault
                        let prevCard = orderedCards[nextIndex]
                        prevCard.reviewCount += 1
                        prevCard.lastReviewedAt = Date()
                        if prevCard.status == .new {
                            prevCard.status = .learning
                        }
                        try SharedDailyProgressHelper.recordActivity(
                            on: todayProgress,
                            cardsReviewedDelta: 1,
                            in: context
                        )
                    case .markMastered:
                        let currentCard = orderedCards[currentIndex]
                        let wasAlreadyMastered = currentCard.status == .mastered
                        currentCard.status = .mastered
                        currentCard.reviewCount += 1
                        currentCard.lastReviewedAt = Date()
                        try SharedDailyProgressHelper.recordActivity(
                            on: todayProgress,
                            cardsReviewedDelta: 1,
                            cardsMasteredDelta: wasAlreadyMastered ? 0 : 1,
                            in: context
                        )
                        nextIndex = (currentIndex + 1) % orderedCards.count
                        nextAnswerVisible = !hideAnswerByDefault
                    }

                    try context.save()

                    let activeCard = orderedCards[nextIndex]
                    let masteredCount = orderedCards.filter { $0.status == .mastered }.count
                    let progressRatio = SharedDailyProgressHelper.completionRatio(for: todayProgress)
                    let streakCount = todayProgress.streakCount

                    // Chỉ ghi các trường thuộc thao tác thẻ/tiến độ; giữ nguyên activeThemeId, privacyModeEnabled, fontScaleRaw.
                    state.activeDeckId = deck.id
                    state.activeDeckTitle = deck.title
                    state.currentCardId = activeCard.id
                    state.currentCardQuestion = activeCard.question
                    state.currentCardAnswer = activeCard.answer
                    state.currentCardIndex = nextIndex
                    state.totalCardsInDeck = orderedCards.count
                    state.masteredCountInDeck = masteredCount
                    state.isAnswerVisible = nextAnswerVisible
                    state.dailyProgressRatio = progressRatio
                    state.streakCount = streakCount
                }

                let contentState = Self.makeContentState(from: updatedSnapshot)
                await Self.updateRunningLiveActivities(deckId: deck.id, state: contentState)
                WidgetCenter.shared.reloadAllTimelines()
                CrossProcessNotifier.postStateDidChange()

                return CardNavigationResult(contentState: contentState, snapshot: updatedSnapshot)
            } catch let error as AppGroupStorageError {
                if case .staleSnapshotRevision = error, attempt == 0 {
                    let latest = try snapshotStore.loadSnapshot()
                    if latest.activeUserId == userId,
                       latest.sessionEpoch == sessionEpoch,
                       latest.activeDeckId == deckId,
                       latest.currentCardId == initialSnapshot.currentCardId {
                        continue
                    }
                }
                throw error
            }
        }

        throw AppGroupStorageError.storageIOFailure("Không thể đồng bộ thao tác thẻ do xung đột revision liên tiếp.")
    }

    public static func makeContentState(from snapshot: LockScreenSnapshot) -> StudySessionAttributes.ContentState {
        StudySessionAttributes.ContentState.makeSafe(
            deckId: snapshot.activeDeckId ?? UUID(),
            deckTitle: snapshot.activeDeckTitle,
            currentCardId: snapshot.currentCardId,
            questionText: snapshot.currentCardQuestion,
            answerText: snapshot.currentCardAnswer,
            isAnswerVisible: snapshot.isAnswerVisible,
            currentIndex: snapshot.currentCardIndex,
            totalCards: snapshot.totalCardsInDeck,
            masteredCount: snapshot.masteredCountInDeck,
            activeThemeId: snapshot.activeThemeId,
            privacyModeEnabled: snapshot.privacyModeEnabled,
            fontScaleRaw: snapshot.fontScaleRaw
        )
    }

    public static func updateRunningLiveActivities(
        deckId: UUID? = nil,
        state: StudySessionAttributes.ContentState
    ) async {
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<StudySessionAttributes>.activities {
            if let deckId, activity.content.state.deckId != deckId {
                continue
            }
            await activity.update(content)
        }
    }
}
