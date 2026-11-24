// DeckDetailCardsView.swift — Quản lý danh sách StudyCard trong một bộ đề, hỗ trợ thêm/sửa thẻ và Quick Import.
// Thuộc Frontend/Features/DecksAndCards; kết nối DeckListAndEditorViewModel và QuickImportSheetView.

import SwiftUI

public struct DeckDetailCardsView: View {
    @Environment(\.lockInPalette) private var palette
    let deckId: UUID
    @Bindable var viewModel: DeckListAndEditorViewModel

    @State private var isPresentingCardEditor = false
    @State private var isPresentingQuickImport = false
    @State private var editingCard: StudyCardDTO?
    @State private var draftQuestion = ""
    @State private var draftAnswer = ""
    @State private var draftHint = ""
    @State private var draftStatus: StudyCardStatus = .new

    public init(deckId: UUID, viewModel: DeckListAndEditorViewModel) {
        self.deckId = deckId
        self.viewModel = viewModel
    }

    private var deck: StudyDeckDTO? {
        viewModel.decks.first { $0.id == deckId }
    }

    private var cards: [StudyCardDTO] {
        viewModel.cardsByDeckId[deckId] ?? []
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let deck {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(deck.title)
                                    .font(.title3.weight(.bold))
                                if !deck.subjectTag.isEmpty {
                                    Text(deck.subjectTag)
                                        .font(.caption)
                                        .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                                }
                            }
                            Spacer()
                            Button {
                                Task { await viewModel.pinDeckToLockScreen(deck.id) }
                            } label: {
                                Label("Pin Lock Screen", systemImage: "pin.fill")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        ProgressBarComponent(
                            title: "Thuộc \(deck.masteredCards)/\(deck.totalCards) thẻ",
                            progress: deck.masteryRatio,
                            accentHex: deck.accentHex
                        )

                        HStack(spacing: 10) {
                            Button {
                                openCardCreator()
                            } label: {
                                Label("Thêm thẻ", systemImage: "plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                isPresentingQuickImport = true
                            } label: {
                                Label("Dán nhanh", systemImage: "doc.on.clipboard")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .minimalCardStyle()
                }

                if cards.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.badge.plus")
                            .font(.title2)
                            .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                        Text("Bộ đề chưa có thẻ ôn nào. Dùng \"Thêm thẻ\" hoặc \"Dán nhanh\" (Câu hỏi | Đáp án).")
                            .font(.footnote)
                            .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                            .multilineTextAlignment(.center)
                    }
                    .minimalCardStyle()
                } else {
                    ForEach(cards) { card in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                statusBadge(card.status)
                                Spacer()
                                Text("Ôn: \(card.reviewCount)")
                                    .font(.caption2)
                                    .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                            }

                            Text(card.question)
                                .font(.subheadline.weight(.semibold))

                            Text(card.answer)
                                .font(.footnote)
                                .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))

                            if !card.hintOrNote.isEmpty {
                                Label(card.hintOrNote, systemImage: "lightbulb")
                                    .font(.caption)
                                    .foregroundStyle(Color(lockInHex: palette.accentHex))
                            }

                            HStack {
                                Spacer()
                                Button {
                                    openCardEditor(card)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.bordered)

                                Button(role: .destructive) {
                                    Task { await viewModel.deleteCard(card.id, inDeck: deckId) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .minimalCardStyle(padding: 14)
                    }
                }
            }
            .padding()
        }
        .background(Color(lockInHex: palette.backgroundHex).ignoresSafeArea())
        .navigationTitle(deck?.title ?? "Chi tiết bộ đề")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: deckId) {
            viewModel.openedDeckId = deckId
            viewModel.startObserving()
            await viewModel.refreshDecks()
            await viewModel.loadCards(forDeckId: deckId)
        }
        .onDisappear {
            if viewModel.openedDeckId == deckId {
                viewModel.openedDeckId = nil
            }
        }
        .sheet(isPresented: $isPresentingCardEditor) {
            cardEditorSheet
        }
        .sheet(isPresented: $isPresentingQuickImport) {
            QuickImportSheetView(deckId: deckId, viewModel: viewModel)
        }
    }

    private func statusBadge(_ status: StudyCardStatus) -> some View {
        let label: String
        let color: Color
        switch status {
        case .new:
            label = "Mới"
            color = .blue
        case .learning:
            label = "Đang học"
            color = .orange
        case .mastered:
            label = "Đã thuộc"
            color = .green
        }
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var cardEditorSheet: some View {
        NavigationStack {
            Form {
                Section("Nội dung thẻ (mặt trước & mặt sau)") {
                    TextField("Câu hỏi", text: $draftQuestion, axis: .vertical)
                        .lineLimit(2...5)
                    TextField("Đáp án", text: $draftAnswer, axis: .vertical)
                        .lineLimit(2...5)
                    TextField("Ghi chú / Gợi ý ngắn", text: $draftHint)
                }

                Section("Trạng thái") {
                    Picker("Mức độ thuộc", selection: $draftStatus) {
                        Text("Mới").tag(StudyCardStatus.new)
                        Text("Đang học").tag(StudyCardStatus.learning)
                        Text("Đã thuộc").tag(StudyCardStatus.mastered)
                    }
                }
            }
            .navigationTitle(editingCard == nil ? "Thêm thẻ mới" : "Sửa thẻ ôn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { isPresentingCardEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        Task {
                            let ok = await viewModel.saveCard(
                                cardId: editingCard?.id,
                                deckId: deckId,
                                question: draftQuestion,
                                answer: draftAnswer,
                                hintOrNote: draftHint,
                                status: draftStatus
                            )
                            if ok { isPresentingCardEditor = false }
                        }
                    }
                }
            }
        }
    }

    private func openCardCreator() {
        editingCard = nil
        draftQuestion = ""
        draftAnswer = ""
        draftHint = ""
        draftStatus = .new
        isPresentingCardEditor = true
    }

    private func openCardEditor(_ card: StudyCardDTO) {
        editingCard = card
        draftQuestion = card.question
        draftAnswer = card.answer
        draftHint = card.hintOrNote
        draftStatus = card.status
        isPresentingCardEditor = true
    }
}
