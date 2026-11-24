// SharedThemeRotationEngine.swift — Thuật toán xoay vòng theme trong Shuffle Pool dùng chung qua SharedAppGroup.
// Chỉ phụ thuộc Shared/**; cập nhật ThemePreference, AppGroupSnapshotStore, Live Activity, WidgetKit và CrossProcessNotifier.

import ActivityKit
import Foundation
import SwiftData
import WidgetKit

public struct ThemeRotationResult: Equatable, Sendable {
    public let previousThemeId: String
    public let nextTheme: ThemePalette
    public let snapshotVersion: Int
    public let prioritizedDeckId: UUID?
    public let didRotateTheme: Bool

    public init(
        previousThemeId: String,
        nextTheme: ThemePalette,
        snapshotVersion: Int,
        prioritizedDeckId: UUID? = nil,
        didRotateTheme: Bool = true
    ) {
        self.previousThemeId = previousThemeId
        self.nextTheme = nextTheme
        self.snapshotVersion = snapshotVersion
        self.prioritizedDeckId = prioritizedDeckId
        self.didRotateTheme = didRotateTheme
    }
}

public protocol SharedThemeRotationEngineProtocol: Sendable {
    func selectNextThemeId(currentThemeId: String, shufflePoolIds: [String]) -> String
    func rotateThemeInSharedStore() async throws -> ThemeRotationResult
    func rotateThemeInSharedStore(referenceDate: Date, calendar: Calendar) async throws -> ThemeRotationResult
}

public extension SharedThemeRotationEngineProtocol {
    func rotateThemeInSharedStore() async throws -> ThemeRotationResult {
        try await rotateThemeInSharedStore(referenceDate: Date(), calendar: .current)
    }
}

public final class SharedThemeRotationEngine: SharedThemeRotationEngineProtocol, @unchecked Sendable {
    private let modelContainer: ModelContainer
    private let snapshotStore: AppGroupSnapshotStoreProtocol

    public init(modelContainer: ModelContainer, snapshotStore: AppGroupSnapshotStoreProtocol) {
        self.modelContainer = modelContainer
        self.snapshotStore = snapshotStore
    }

    public static func makeShared() throws -> SharedThemeRotationEngine {
        let container = try SharedStoreContainer.makeShared()
        let store = try AppGroupSnapshotStore.makeShared()
        return SharedThemeRotationEngine(modelContainer: container, snapshotStore: store)
    }

    public static func selectNextThemeId(currentThemeId: String, shufflePoolIds: [String]) -> String {
        var generator = SystemRandomNumberGenerator()
        return selectNextThemeId(currentThemeId: currentThemeId, shufflePoolIds: shufflePoolIds, using: &generator)
    }

    public static func selectNextThemeId<G: RandomNumberGenerator>(
        currentThemeId: String,
        shufflePoolIds: [String],
        using generator: inout G
    ) -> String {
        let validIds = Set(ThemePalette.allBuiltIn.map(\.id))
        var deduplicatedPool: [String] = []
        var seen: Set<String> = []

        for rawId in shufflePoolIds where validIds.contains(rawId) && !seen.contains(rawId) {
            seen.insert(rawId)
            deduplicatedPool.append(rawId)
        }

        if deduplicatedPool.isEmpty {
            return ThemePalette.minimalPaper.id
        }
        if deduplicatedPool.count == 1 {
            return deduplicatedPool[0]
        }

        let candidates = deduplicatedPool.filter { $0 != currentThemeId }
        if let chosen = candidates.randomElement(using: &generator) {
            return chosen
        }
        return deduplicatedPool[0]
    }

    public func selectNextThemeId(currentThemeId: String, shufflePoolIds: [String]) -> String {
        Self.selectNextThemeId(currentThemeId: currentThemeId, shufflePoolIds: shufflePoolIds)
    }

    public func selectNextThemeId<G: RandomNumberGenerator>(
        currentThemeId: String,
        shufflePoolIds: [String],
        using generator: inout G
    ) -> String {
        Self.selectNextThemeId(currentThemeId: currentThemeId, shufflePoolIds: shufflePoolIds, using: &generator)
    }

    /// Tìm lịch học bật gần nhất đang nằm trong cửa sổ `[scheduledAt - windowBeforeSeconds, scheduledAt + windowAfterSeconds]`
    /// bằng cách duyệt ngày hôm qua, hôm nay và ngày mai (`dayOffset in -1...1`) để xử lý đúng mốc qua nửa đêm (vd: 23:30 -> 00:15).
    public static func findDueSchedule(
        for userId: UUID,
        at referenceDate: Date,
        windowBeforeSeconds: TimeInterval = 0,
        windowAfterSeconds: TimeInterval = 2 * 3600,
        in context: ModelContext,
        calendar: Calendar = .current
    ) throws -> (schedule: StudySchedule, scheduledAt: Date)? {
        let uid = userId
        let schedules = try context.fetch(
            FetchDescriptor<StudySchedule>(predicate: #Predicate<StudySchedule> { $0.ownerUserId == uid && $0.isEnabled == true })
        )
        let startOfRefDay = calendar.startOfDay(for: referenceDate)
        let lowerBound = referenceDate.addingTimeInterval(-windowAfterSeconds)
        let upperBound = referenceDate.addingTimeInterval(windowBeforeSeconds)

        var matches: [(schedule: StudySchedule, scheduledAt: Date)] = []
        for schedule in schedules {
            guard (0...23).contains(schedule.hour), (0...59).contains(schedule.minute) else { continue }
            for dayOffset in -1...1 {
                guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: startOfRefDay) else {
                    continue
                }
                let weekday = calendar.component(.weekday, from: candidateDay)
                let dayBit = 1 << (weekday - 1)
                guard (schedule.weekdaysMask & dayBit) != 0 else { continue }
                guard let scheduledAt = calendar.date(
                    bySettingHour: schedule.hour,
                    minute: schedule.minute,
                    second: 0,
                    of: candidateDay
                ) else {
                    continue
                }
                if scheduledAt >= lowerBound && scheduledAt <= upperBound {
                    matches.append((schedule, scheduledAt))
                }
            }
        }

        return matches.sorted { lhs, rhs in
            if lhs.scheduledAt != rhs.scheduledAt {
                return lhs.scheduledAt > rhs.scheduledAt
            }
            return lhs.schedule.id.uuidString > rhs.schedule.id.uuidString
        }.first
    }

    public func rotateThemeInSharedStore() async throws -> ThemeRotationResult {
        try await rotateThemeInSharedStore(referenceDate: Date(), calendar: .current)
    }

    public func rotateThemeInSharedStore(
        referenceDate: Date,
        calendar: Calendar = .current
    ) async throws -> ThemeRotationResult {
        for attempt in 0..<2 {
            let initialSnapshot = try snapshotStore.loadSnapshot()
            guard let userId = initialSnapshot.activeUserId,
                  let sessionEpoch = initialSnapshot.sessionEpoch else {
                throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
            }
            let expectedRevisionId = initialSnapshot.snapshotRevisionId

            let context = ModelContext(modelContainer)
            let uid = userId
            let prefDescriptor = FetchDescriptor<ThemePreference>(
                predicate: #Predicate<ThemePreference> { $0.ownerUserId == uid }
            )
            let preference = try context.fetch(prefDescriptor).first

            let dueMatch = try Self.findDueSchedule(
                for: uid,
                at: referenceDate,
                windowBeforeSeconds: 0,
                windowAfterSeconds: 2 * 3600,
                in: context,
                calendar: calendar
            )

            struct PrioritizedDeckPayload {
                let deckId: UUID
                let deckTitle: String
                let firstCard: (id: UUID, question: String, answer: String)?
                let totalCards: Int
                let masteredCards: Int
                let hideAnswerByDefault: Bool
                let progressRatio: Double
                let streakCount: Int
            }

            var prioritizedDeck: PrioritizedDeckPayload?
            if let dueMatch {
                let targetDeckId = dueMatch.schedule.deckId
                if let deck = try context.fetch(
                    FetchDescriptor<StudyDeck>(predicate: #Predicate<StudyDeck> { $0.id == targetDeckId && $0.ownerUserId == uid })
                ).first {
                    let orderedCards = deck.cards
                        .filter { $0.ownerUserId == uid }
                        .sorted {
                            if $0.sortOrder != $1.sortOrder {
                                return $0.sortOrder < $1.sortOrder
                            }
                            return $0.id.uuidString < $1.id.uuidString
                        }
                    let progress = try SharedDailyProgressHelper.fetchOrCreateTodayProgress(
                        for: uid,
                        in: context,
                        referenceDate: referenceDate,
                        defaultTarget: max(1, deck.dailyGoal)
                    )
                    prioritizedDeck = PrioritizedDeckPayload(
                        deckId: deck.id,
                        deckTitle: deck.title,
                        firstCard: orderedCards.first.map { ($0.id, $0.question, $0.answer) },
                        totalCards: orderedCards.count,
                        masteredCards: orderedCards.filter { $0.status == .mastered }.count,
                        hideAnswerByDefault: preference?.hideAnswerByDefault ?? true,
                        progressRatio: SharedDailyProgressHelper.completionRatio(for: progress),
                        streakCount: progress.streakCount
                    )
                }
            }

            let currentThemeId = preference?.activeThemeId ?? initialSnapshot.activeThemeId
            let poolIds = preference?.shufflePoolIds ?? initialSnapshot.shufflePoolIds
            let shortcutShuffleAllowed = (preference?.isShuffleEnabled ?? initialSnapshot.isShuffleEnabled)
                && (preference?.rotateOnShortcutTrigger ?? false)
            let shouldRotateTheme: Bool = {
                if let dueMatch, prioritizedDeck != nil {
                    return dueMatch.schedule.autoRotateTheme || shortcutShuffleAllowed
                }
                return shortcutShuffleAllowed
            }()
            if !shouldRotateTheme && prioritizedDeck == nil {
                return ThemeRotationResult(
                    previousThemeId: currentThemeId,
                    nextTheme: ThemePalette.palette(for: currentThemeId),
                    snapshotVersion: initialSnapshot.snapshotVersion,
                    prioritizedDeckId: nil,
                    didRotateTheme: false
                )
            }
            let targetThemeId = shouldRotateTheme
                ? Self.selectNextThemeId(currentThemeId: currentThemeId, shufflePoolIds: poolIds)
                : currentThemeId
            let nextPalette = ThemePalette.palette(for: targetThemeId)

            do {
                let updatedSnapshot = try snapshotStore.mutateSnapshotIfSessionMatches(
                    expectedUserId: userId,
                    expectedSessionEpoch: sessionEpoch,
                    expectedRevisionId: expectedRevisionId
                ) { state in
                    if shouldRotateTheme {
                        preference?.activeThemeId = nextPalette.id
                        state.activeThemeId = nextPalette.id
                    }
                    if let deckPayload = prioritizedDeck {
                        state.activeDeckId = deckPayload.deckId
                        state.activeDeckTitle = deckPayload.deckTitle
                        state.currentCardId = deckPayload.firstCard?.id
                        state.currentCardQuestion = deckPayload.firstCard?.question ?? "Bộ đề chưa có thẻ ôn."
                        state.currentCardAnswer = deckPayload.firstCard?.answer ?? ""
                        state.currentCardIndex = 0
                        state.totalCardsInDeck = deckPayload.totalCards
                        state.masteredCountInDeck = deckPayload.masteredCards
                        state.isAnswerVisible = !deckPayload.hideAnswerByDefault
                        state.dailyProgressRatio = deckPayload.progressRatio
                        state.streakCount = deckPayload.streakCount
                    }
                    if context.hasChanges {
                        try context.save()
                    }
                }

                let latestSnapshot = try snapshotStore.loadSnapshot()
                guard latestSnapshot.activeUserId == userId,
                      latestSnapshot.sessionEpoch == sessionEpoch else {
                    throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
                }

                if latestSnapshot.activeDeckId != nil {
                    let contentState = SharedCardNavigationEngine.makeContentState(from: latestSnapshot)
                    await SharedCardNavigationEngine.updateRunningLiveActivities(
                        deckId: prioritizedDeck != nil ? nil : latestSnapshot.activeDeckId,
                        state: contentState
                    )
                }

                WidgetCenter.shared.reloadAllTimelines()
                CrossProcessNotifier.postStateDidChange()

                return ThemeRotationResult(
                    previousThemeId: currentThemeId,
                    nextTheme: nextPalette,
                    snapshotVersion: updatedSnapshot.snapshotVersion,
                    prioritizedDeckId: prioritizedDeck?.deckId,
                    didRotateTheme: shouldRotateTheme
                )
            } catch let error as AppGroupStorageError {
                if case .staleSnapshotRevision = error, attempt == 0 {
                    continue
                }
                throw error
            }
        }

        throw AppGroupStorageError.storageIOFailure("Không thể xoay theme qua Shortcuts do xung đột revision liên tiếp.")
    }
}
