// SwiftDataStudyStore.swift — Quản lý giao dịch đọc/ghi SwiftData trên SharedStoreContainer và dọn dữ liệu user.
// Triển khai StorageMaintenanceProtocol, đồng bộ qua AppGroupSnapshotStore, WidgetKit và SyncEventBus.

import ActivityKit
import Foundation
import SwiftData
import WidgetKit

public actor SwiftDataStudyStore: StorageMaintenanceProtocol {
    public let modelContainer: ModelContainer
    private let isolationGuard: UserDataIsolationGuardProtocol
    private let snapshotStore: AppGroupSnapshotStoreProtocol
    private let syncEventBus: SyncEventBus

    public init(
        modelContainer: ModelContainer,
        isolationGuard: UserDataIsolationGuardProtocol,
        snapshotStore: AppGroupSnapshotStoreProtocol,
        syncEventBus: SyncEventBus
    ) {
        self.modelContainer = modelContainer
        self.isolationGuard = isolationGuard
        self.snapshotStore = snapshotStore
        self.syncEventBus = syncEventBus
    }

    public func perform<T: Sendable>(_ work: (ModelContext) throws -> T) throws -> T {
        let context = ModelContext(modelContainer)
        return try work(context)
    }

    /// Xóa toàn bộ dữ liệu học tập của user hiện tại (giữ lại UserProfile) và làm mới Lock Screen snapshot.
    public func purgeCurrentUserStudyData() async throws {
        let session = try isolationGuard.requireActiveSession()
        let uid = session.userId

        try perform { context in
            let decks = try context.fetch(
                FetchDescriptor<StudyDeck>(predicate: #Predicate<StudyDeck> { $0.ownerUserId == uid })
            )
            for deck in decks {
                context.delete(deck)
            }

            let cards = try context.fetch(
                FetchDescriptor<StudyCard>(predicate: #Predicate<StudyCard> { $0.ownerUserId == uid })
            )
            for card in cards {
                context.delete(card)
            }

            let tasks = try context.fetch(
                FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.ownerUserId == uid })
            )
            for task in tasks {
                context.delete(task)
            }

            let schedules = try context.fetch(
                FetchDescriptor<StudySchedule>(predicate: #Predicate<StudySchedule> { $0.ownerUserId == uid })
            )
            for schedule in schedules {
                context.delete(schedule)
            }

            let progresses = try context.fetch(
                FetchDescriptor<DailyProgress>(predicate: #Predicate<DailyProgress> { $0.ownerUserId == uid })
            )
            for progress in progresses {
                context.delete(progress)
            }

            try context.save()
        }

        for activity in Activity<StudySessionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let updatedSnapshot = try snapshotStore.mutateSnapshotIfSessionMatches(
            expectedUserId: session.userId,
            expectedSessionEpoch: session.sessionEpoch
        ) { state in
            state.activeDeckId = nil
            state.activeDeckTitle = ""
            state.currentCardId = nil
            state.currentCardQuestion = ""
            state.currentCardAnswer = ""
            state.currentCardIndex = 0
            state.totalCardsInDeck = 0
            state.masteredCountInDeck = 0
            state.isAnswerVisible = false
            state.dailyProgressRatio = 0
            state.streakCount = 0
            state.nextTaskId = nil
            state.nextTaskTitle = nil
        }

        WidgetCenter.shared.reloadAllTimelines()
        CrossProcessNotifier.postStateDidChange()

        let marker = SnapshotStateMarker(
            version: updatedSnapshot.snapshotVersion,
            revisionId: updatedSnapshot.snapshotRevisionId
        )
        await MainActor.run {
            syncEventBus.publish(.cardsChanged(deckId: nil), observedMarker: marker)
            syncEventBus.publish(.tasksChanged)
            syncEventBus.publish(.progressUpdated)
        }
    }
}
