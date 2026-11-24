// DeckListAndEditorViewModel.swift — Điều phối CRUD StudyDeck/StudyCard, Quick Import và Pin to Lock Screen.
// Thuộc Frontend/Features/DecksAndCards; chỉ phụ thuộc StudyModuleProtocol, LockScreenModuleProtocol và SyncEventBus.

import Foundation
import Observation

@MainActor
@Observable
public final class DeckListAndEditorViewModel {
    private let studyModule: StudyModuleProtocol
    private let lockScreenModule: LockScreenModuleProtocol
    private let syncEventBus: SyncEventBus
    private var observerTask: Task<Void, Never>?

    public var decks: [StudyDeckDTO] = []
    public var cardsByDeckId: [UUID: [StudyCardDTO]] = [:]
    public var openedDeckId: UUID?
    public var activeDeckIdOnLockScreen: UUID?
    public var isLoading: Bool = false
    public var statusMessage: String?
    public var errorMessage: String?

    public init(
        studyModule: StudyModuleProtocol,
        lockScreenModule: LockScreenModuleProtocol,
        syncEventBus: SyncEventBus
    ) {
        self.studyModule = studyModule
        self.lockScreenModule = lockScreenModule
        self.syncEventBus = syncEventBus
    }

    public func startObserving() {
        guard observerTask == nil else { return }
        let stream = syncEventBus.subscribe()
        observerTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self else { break }
                switch event {
                case .cardsChanged(let deckId):
                    await self.refreshDecks()
                    if let deckId {
                        await self.loadCards(forDeckId: deckId)
                    } else {
                        await self.reloadOpenedDeckCards()
                    }
                case .progressUpdated, .externalStateRefreshed, .userSessionChanged:
                    await self.refreshDecks()
                    await self.reloadOpenedDeckCards()
                case .tasksChanged, .themeRotated, .appLockPolicyChanged:
                    break
                }
            }
        }
    }

    public func stopObserving() {
        observerTask?.cancel()
        observerTask = nil
    }

    public func refreshDecks() async {
        isLoading = true
        defer { isLoading = false }
        do {
            decks = try await studyModule.fetchDecks()
            let bridgeStatus = await lockScreenModule.checkBridgeStatus()
            activeDeckIdOnLockScreen = bridgeStatus.activeDeckId
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadCards(forDeckId deckId: UUID) async {
        do {
            cardsByDeckId[deckId] = try await studyModule.fetchCards(deckId: deckId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadOpenedDeckCards() async {
        var targetIds = Set(cardsByDeckId.keys)
        if let openedDeckId {
            targetIds.insert(openedDeckId)
        }
        for deckId in targetIds {
            await loadCards(forDeckId: deckId)
        }
    }

    public func saveDeck(
        editingDeckId: UUID?,
        title: String,
        subjectTag: String,
        accentHex: String,
        examDate: Date?,
        dailyGoal: Int
    ) async -> Bool {
        errorMessage = nil
        do {
            if let editingDeckId {
                _ = try await studyModule.updateDeck(
                    deckId: editingDeckId,
                    title: title,
                    subjectTag: subjectTag,
                    accentHex: accentHex,
                    examDate: examDate,
                    dailyGoal: dailyGoal
                )
            } else {
                _ = try await studyModule.createDeck(
                    title: title,
                    subjectTag: subjectTag,
                    accentHex: accentHex,
                    examDate: examDate,
                    dailyGoal: dailyGoal
                )
            }
            await refreshDecks()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func deleteDeck(_ deckId: UUID) async {
        errorMessage = nil
        do {
            try await studyModule.deleteDeck(deckId: deckId)
            cardsByDeckId.removeValue(forKey: deckId)
            await refreshDecks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func saveCard(
        cardId: UUID?,
        deckId: UUID,
        question: String,
        answer: String,
        hintOrNote: String,
        status: StudyCardStatus
    ) async -> Bool {
        errorMessage = nil
        do {
            _ = try await studyModule.upsertCard(
                cardId: cardId,
                deckId: deckId,
                question: question,
                answer: answer,
                hintOrNote: hintOrNote,
                status: status
            )
            await loadCards(forDeckId: deckId)
            await refreshDecks()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func deleteCard(_ cardId: UUID, inDeck deckId: UUID) async {
        errorMessage = nil
        do {
            try await studyModule.deleteCard(cardId: cardId)
            await loadCards(forDeckId: deckId)
            await refreshDecks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func previewQuickImport(rawText: String) -> QuickImportPreview {
        studyModule.previewQuickImport(rawText: rawText)
    }

    public func commitQuickImport(deckId: UUID, candidates: [QuickImportCandidate]) async -> Int? {
        errorMessage = nil
        do {
            let inserted = try await studyModule.commitQuickImport(deckId: deckId, candidates: candidates)
            await loadCards(forDeckId: deckId)
            await refreshDecks()
            statusMessage = "Đã nhập thêm \(inserted.count) thẻ vào bộ đề."
            return inserted.count
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func pinDeckToLockScreen(_ deckId: UUID) async {
        errorMessage = nil
        statusMessage = nil
        do {
            try await lockScreenModule.startOrUpdateLiveActivity(forDeckId: deckId)
            activeDeckIdOnLockScreen = deckId
            statusMessage = "Đã ghim bộ đề lên màn hình khóa (Live Activity)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func examCountdownDays(for examDate: Date?, referenceDate: Date = Date()) -> Int? {
        guard let examDate else { return nil }
        let calendar = Calendar.current
        let startToday = calendar.startOfDay(for: referenceDate)
        let startExam = calendar.startOfDay(for: examDate)
        return calendar.dateComponents([.day], from: startToday, to: startExam).day
    }
}
