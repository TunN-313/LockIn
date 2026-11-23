// StudyDeckCardService.swift — Quản lý CRUD bộ đề (StudyDeck), thẻ ôn (StudyCard) và điều phối StudyModuleProtocol.
// Cô lập dữ liệu theo activeUserId, kết hợp QuickImportParserService và TaskProgressStreakService.

import Foundation
import SwiftData
import WidgetKit

public final class StudyDeckCardService: StudyModuleProtocol, @unchecked Sendable {
    private let studyStore: SwiftDataStudyStore
    private let isolationGuard: UserDataIsolationGuardProtocol
    private let snapshotStore: AppGroupSnapshotStoreProtocol
    private let syncEventBus: SyncEventBus
    private let parser: QuickImportParserProtocol
    private let taskProgressService: TaskProgressStreakServiceProtocol

    public init(
        studyStore: SwiftDataStudyStore,
        isolationGuard: UserDataIsolationGuardProtocol,
        snapshotStore: AppGroupSnapshotStoreProtocol,
        syncEventBus: SyncEventBus,
        parser: QuickImportParserProtocol,
        taskProgressService: TaskProgressStreakServiceProtocol
    ) {
        self.studyStore = studyStore
        self.isolationGuard = isolationGuard
        self.snapshotStore = snapshotStore
        self.syncEventBus = syncEventBus
        self.parser = parser
        self.taskProgressService = taskProgressService
    }

    public func fetchDecks() async throws -> [StudyDeckDTO] {
        let userId = try isolationGuard.requireActiveUserId()
        return try await studyStore.perform { context in
            let uid = userId
            let descriptor = FetchDescriptor<StudyDeck>(
                predicate: #Predicate<StudyDeck> { $0.ownerUserId == uid },
                sortBy: [SortDescriptor(\StudyDeck.updatedAt, order: .reverse)]
            )
            return try context.fetch(descriptor).map { Self.toDeckDTO($0, ownerUserId: uid) }
        }
    }

    public func createDeck(
        title: String,
        subjectTag: String,
        accentHex: String,
        examDate: Date?,
        dailyGoal: Int
    ) async throws -> StudyDeckDTO {
        let userId = try isolationGuard.requireActiveUserId()
        let cleanTitle = try validateField(title, name: "Tên bộ đề", allowEmpty: false)
        let cleanTag = try validateField(subjectTag, name: "Môn học / Tag", allowEmpty: true)
        let cleanHex = sanitizeHex(accentHex)

        let created = try await studyStore.perform { context in
            let deck = StudyDeck(
                ownerUserId: userId,
                title: cleanTitle,
                subjectTag: cleanTag,
                accentHex: cleanHex,
                examDate: examDate,
                dailyGoal: max(1, dailyGoal),
                createdAt: Date(),
                updatedAt: Date()
            )
            context.insert(deck)
            try context.save()
            return Self.toDeckDTO(deck, ownerUserId: userId)
        }

        await MainActor.run {
            syncEventBus.publish(.cardsChanged(deckId: created.id))
        }
        return created
    }

    public func updateDeck(
        deckId: UUID,
        title: String,
        subjectTag: String,
        accentHex: String,
        examDate: Date?,
        dailyGoal: Int
    ) async throws -> StudyDeckDTO {
        let session = try isolationGuard.requireActiveSession()
        let cleanTitle = try validateField(title, name: "Tên bộ đề", allowEmpty: false)
        let cleanTag = try validateField(subjectTag, name: "Môn học / Tag", allowEmpty: true)
        let cleanHex = sanitizeHex(accentHex)

        let updated = try await studyStore.perform { context in
            let uid = session.userId
            let targetId = deckId
            let descriptor = FetchDescriptor<StudyDeck>(
                predicate: #Predicate<StudyDeck> { $0.id == targetId && $0.ownerUserId == uid }
            )
            guard let deck = try context.fetch(descriptor).first else {
                throw LockInDomainError.entityNotFound
            }
            deck.title = cleanTitle
            deck.subjectTag = cleanTag
            deck.accentHex = cleanHex
            deck.examDate = examDate
            deck.dailyGoal = max(1, dailyGoal)
            deck.updatedAt = Date()
            try context.save()
            return Self.toDeckDTO(deck, ownerUserId: uid)
        }

        let snapshot = try snapshotStore.loadSnapshot()
        if snapshot.activeDeckId == deckId {
            let synced = try snapshotStore.mutateSnapshotIfSessionMatches(
                expectedUserId: session.userId,
                expectedSessionEpoch: session.sessionEpoch
            ) { state in
                state.activeDeckTitle = updated.title
            }
            let contentState = SharedCardNavigationEngine.makeContentState(from: synced)
            await SharedCardNavigationEngine.updateRunningLiveActivities(deckId: deckId, state: contentState)
            WidgetCenter.shared.reloadAllTimelines()
            CrossProcessNotifier.postStateDidChange()
            let marker = SnapshotStateMarker(version: synced.snapshotVersion, revisionId: synced.snapshotRevisionId)
            await MainActor.run {
                syncEventBus.publish(.cardsChanged(deckId: deckId), observedMarker: marker)
            }
        } else {
            await MainActor.run {
                syncEventBus.publish(.cardsChanged(deckId: deckId))
            }
        }
        return updated
    }

    public func deleteDeck(deckId: UUID) async throws {
        let session = try isolationGuard.requireActiveSession()

        try await studyStore.perform { context in
            let uid = session.userId
            let targetId = deckId
            let descriptor = FetchDescriptor<StudyDeck>(
                predicate: #Predicate<StudyDeck> { $0.id == targetId && $0.ownerUserId == uid }
            )
            guard let deck = try context.fetch(descriptor).first else {
                throw LockInDomainError.entityNotFound
            }
            context.delete(deck)
            try context.save()
        }

        let currentSnapshot = try snapshotStore.loadSnapshot()
        if currentSnapshot.activeDeckId == deckId {
            let clearedDeckSnapshot = try snapshotStore.mutateSnapshotIfSessionMatches(
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
            }
            WidgetCenter.shared.reloadAllTimelines()
            CrossProcessNotifier.postStateDidChange()
            let marker = SnapshotStateMarker(
                version: clearedDeckSnapshot.snapshotVersion,
                revisionId: clearedDeckSnapshot.snapshotRevisionId
            )
            await MainActor.run {
                syncEventBus.publish(.cardsChanged(deckId: deckId), observedMarker: marker)
            }
        } else {
            await MainActor.run {
                syncEventBus.publish(.cardsChanged(deckId: deckId))
            }
        }
    }

    public func fetchCards(deckId: UUID) async throws -> [StudyCardDTO] {
        let userId = try isolationGuard.requireActiveUserId()
        return try await studyStore.perform { context in
            let uid = userId
            let targetDeckId = deckId
            let descriptor = FetchDescriptor<StudyDeck>(
                predicate: #Predicate<StudyDeck> { $0.id == targetDeckId && $0.ownerUserId == uid }
            )
            guard let deck = try context.fetch(descriptor).first else {
                throw LockInDomainError.entityNotFound
            }
            return deck.cards
                .filter { $0.ownerUserId == uid }
                .sorted {
                    if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                    return $0.id.uuidString < $1.id.uuidString
                }
                .map { Self.toCardDTO($0, deckId: deck.id) }
        }
    }

    public func upsertCard(
        cardId: UUID?,
        deckId: UUID,
        question: String,
        answer: String,
        hintOrNote: String,
        status: StudyCardStatus
    ) async throws -> StudyCardDTO {
        let session = try isolationGuard.requireActiveSession()
        let cleanQuestion = try validateField(question, name: "Câu hỏi", allowEmpty: false)
        let cleanAnswer = try validateField(answer, name: "Đáp án", allowEmpty: false)
        let cleanHint = try validateField(hintOrNote, name: "Ghi chú", allowEmpty: true)

        let cardDTO = try await studyStore.perform { context in
            let uid = session.userId
            let targetDeckId = deckId
            let deckDescriptor = FetchDescriptor<StudyDeck>(
                predicate: #Predicate<StudyDeck> { $0.id == targetDeckId && $0.ownerUserId == uid }
            )
            guard let deck = try context.fetch(deckDescriptor).first else {
                throw LockInDomainError.entityNotFound
            }

            let targetCard: StudyCard
            if let existingId = cardId {
                let cid = existingId
                let cardDescriptor = FetchDescriptor<StudyCard>(
                    predicate: #Predicate<StudyCard> { $0.id == cid && $0.ownerUserId == uid }
                )
                guard let found = try context.fetch(cardDescriptor).first else {
                    throw LockInDomainError.entityNotFound
                }
                found.question = cleanQuestion
                found.answer = cleanAnswer
                found.hintOrNote = cleanHint
                found.status = status
                found.deck = deck
                targetCard = found
            } else {
                let nextOrder = (deck.cards.map(\.sortOrder).max() ?? -1) + 1
                let newCard = StudyCard(
                    ownerUserId: uid,
                    deck: deck,
                    question: cleanQuestion,
                    answer: cleanAnswer,
                    hintOrNote: cleanHint,
                    status: status,
                    reviewCount: 0,
                    lastReviewedAt: nil,
                    sortOrder: nextOrder
                )
                context.insert(newCard)
                targetCard = newCard
            }

            deck.updatedAt = Date()
            try context.save()
            return Self.toCardDTO(targetCard, deckId: deck.id)
        }

        await syncActiveDeckSnapshotIfNeeded(deckId: deckId, userId: session.userId, sessionEpoch: session.sessionEpoch)
        return cardDTO
    }

    public func deleteCard(cardId: UUID) async throws {
        let session = try isolationGuard.requireActiveSession()

        let parentDeckId: UUID? = try await studyStore.perform { context in
            let uid = session.userId
            let cid = cardId
            let cardDescriptor = FetchDescriptor<StudyCard>(
                predicate: #Predicate<StudyCard> { $0.id == cid && $0.ownerUserId == uid }
            )
            guard let card = try context.fetch(cardDescriptor).first else {
                throw LockInDomainError.entityNotFound
            }
            let deckId = card.deck?.id
            card.deck?.updatedAt = Date()
            context.delete(card)
            try context.save()
            return deckId
        }

        if let parentDeckId {
            await syncActiveDeckSnapshotIfNeeded(deckId: parentDeckId, userId: session.userId, sessionEpoch: session.sessionEpoch)
        } else {
            await MainActor.run {
                syncEventBus.publish(.cardsChanged(deckId: nil))
            }
        }
    }

    public func previewQuickImport(rawText: String) -> QuickImportPreview {
        parser.parsePreview(rawText: rawText)
    }

    public func commitQuickImport(deckId: UUID, candidates: [QuickImportCandidate]) async throws -> [StudyCardDTO] {
        let session = try isolationGuard.requireActiveSession()
        guard !candidates.isEmpty else { return [] }
        guard candidates.count <= AppConstants.maxQuickImportLines else {
            throw LockInDomainError.validationFailed("Mỗi lần chỉ nhập tối đa \(AppConstants.maxQuickImportLines) thẻ.")
        }

        let validatedCandidates: [QuickImportCandidate] = try candidates.map { candidate in
            let q = try validateField(candidate.question, name: "Câu hỏi", allowEmpty: false)
            let a = try validateField(candidate.answer, name: "Đáp án", allowEmpty: false)
            let h = try validateField(candidate.hintOrNote, name: "Ghi chú", allowEmpty: true)
            return QuickImportCandidate(question: q, answer: a, hintOrNote: h)
        }

        let insertedDTOs = try await studyStore.perform { context in
            let uid = session.userId
            let targetDeckId = deckId
            let deckDescriptor = FetchDescriptor<StudyDeck>(
                predicate: #Predicate<StudyDeck> { $0.id == targetDeckId && $0.ownerUserId == uid }
            )
            guard let deck = try context.fetch(deckDescriptor).first else {
                throw LockInDomainError.entityNotFound
            }

            var nextOrder = (deck.cards.map(\.sortOrder).max() ?? -1) + 1
            var results: [StudyCardDTO] = []

            for candidate in validatedCandidates {
                let card = StudyCard(
                    ownerUserId: uid,
                    deck: deck,
                    question: candidate.question,
                    answer: candidate.answer,
                    hintOrNote: candidate.hintOrNote,
                    status: .new,
                    reviewCount: 0,
                    lastReviewedAt: nil,
                    sortOrder: nextOrder
                )
                context.insert(card)
                nextOrder += 1
                results.append(Self.toCardDTO(card, deckId: deck.id))
            }

            deck.updatedAt = Date()
            try context.save()
            return results
        }

        await syncActiveDeckSnapshotIfNeeded(deckId: deckId, userId: session.userId, sessionEpoch: session.sessionEpoch)
        return insertedDTOs
    }

    // MARK: - Task, Progress & Reminder Delegation

    public func fetchTasks() async throws -> [TaskItemDTO] {
        try await taskProgressService.fetchTasks()
    }

    public func createTask(
        title: String,
        notes: String,
        dueDate: Date?,
        priority: TaskPriority,
        linkedDeckId: UUID?
    ) async throws -> TaskItemDTO {
        try await taskProgressService.createTask(
            title: title,
            notes: notes,
            dueDate: dueDate,
            priority: priority,
            linkedDeckId: linkedDeckId
        )
    }

    public func updateTask(
        taskId: UUID,
        title: String,
        notes: String,
        dueDate: Date?,
        priority: TaskPriority,
        linkedDeckId: UUID?
    ) async throws -> TaskItemDTO {
        try await taskProgressService.updateTask(
            taskId: taskId,
            title: title,
            notes: notes,
            dueDate: dueDate,
            priority: priority,
            linkedDeckId: linkedDeckId
        )
    }

    public func toggleTaskCompletion(taskId: UUID) async throws -> TaskItemDTO {
        try await taskProgressService.toggleTaskCompletion(taskId: taskId)
    }

    public func deleteTask(taskId: UUID) async throws {
        try await taskProgressService.deleteTask(taskId: taskId)
    }

    public func fetchTodayProgress() async throws -> DailyProgressDTO {
        try await taskProgressService.fetchTodayProgress()
    }

    public func fetchPendingReminderSummary() async throws -> PendingReminderSummary {
        try await taskProgressService.fetchPendingReminderSummary()
    }

    // MARK: - Helpers

    private func syncActiveDeckSnapshotIfNeeded(deckId: UUID, userId: UUID, sessionEpoch: UUID) async {
        guard let snapshot = try? snapshotStore.loadSnapshot(), snapshot.activeDeckId == deckId else {
            await MainActor.run {
                syncEventBus.publish(.cardsChanged(deckId: deckId))
            }
            return
        }

        guard let cards = try? await fetchCards(deckId: deckId) else {
            await MainActor.run {
                syncEventBus.publish(.cardsChanged(deckId: deckId))
            }
            return
        }

        let currentIndex = cards.isEmpty ? 0 : min(snapshot.currentCardIndex, cards.count - 1)
        let activeCard = cards.isEmpty ? nil : cards[currentIndex]
        let mastered = cards.filter { $0.status == .mastered }.count

        if let synced = try? snapshotStore.mutateSnapshotIfSessionMatches(
            expectedUserId: userId,
            expectedSessionEpoch: sessionEpoch
        ) { state in
            state.currentCardId = activeCard?.id
            state.currentCardQuestion = activeCard?.question ?? "Chưa có thẻ nào trong bộ đề."
            state.currentCardAnswer = activeCard?.answer ?? ""
            state.currentCardIndex = currentIndex
            state.totalCardsInDeck = cards.count
            state.masteredCountInDeck = mastered
        } {
            let contentState = SharedCardNavigationEngine.makeContentState(from: synced)
            await SharedCardNavigationEngine.updateRunningLiveActivities(deckId: deckId, state: contentState)
            WidgetCenter.shared.reloadAllTimelines()
            CrossProcessNotifier.postStateDidChange()
            let marker = SnapshotStateMarker(version: synced.snapshotVersion, revisionId: synced.snapshotRevisionId)
            await MainActor.run {
                syncEventBus.publish(.cardsChanged(deckId: deckId), observedMarker: marker)
            }
        }
    }

    private func validateField(_ raw: String, name: String, allowEmpty: Bool) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !allowEmpty && trimmed.isEmpty {
            throw LockInDomainError.validationFailed("\(name) không được để trống.")
        }
        guard trimmed.count <= AppConstants.maxFieldCharacterLength else {
            throw LockInDomainError.validationFailed("\(name) không vượt quá \(AppConstants.maxFieldCharacterLength) ký tự.")
        }
        return trimmed
    }

    private func sanitizeHex(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("#") && (trimmed.count == 7 || trimmed.count == 4) ? trimmed : "#2563EB"
    }

    private static func toDeckDTO(_ deck: StudyDeck, ownerUserId: UUID) -> StudyDeckDTO {
        let ownedCards = deck.cards.filter { $0.ownerUserId == ownerUserId }
        let mastered = ownedCards.filter { $0.status == .mastered }.count
        return StudyDeckDTO(
            id: deck.id,
            ownerUserId: deck.ownerUserId,
            title: deck.title,
            subjectTag: deck.subjectTag,
            accentHex: deck.accentHex,
            examDate: deck.examDate,
            dailyGoal: deck.dailyGoal,
            totalCards: ownedCards.count,
            masteredCards: mastered,
            createdAt: deck.createdAt,
            updatedAt: deck.updatedAt
        )
    }

    private static func toCardDTO(_ card: StudyCard, deckId: UUID) -> StudyCardDTO {
        StudyCardDTO(
            id: card.id,
            ownerUserId: card.ownerUserId,
            deckId: deckId,
            question: card.question,
            answer: card.answer,
            hintOrNote: card.hintOrNote,
            status: card.status,
            reviewCount: card.reviewCount,
            lastReviewedAt: card.lastReviewedAt,
            sortOrder: card.sortOrder
        )
    }
}
