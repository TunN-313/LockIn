// DeckListView.swift — Danh sách bộ đề ôn thi kèm tiến độ thuộc bài, ExamCountdown và nút Pin Lock Screen.
// Thuộc Frontend/Features/DecksAndCards; tích hợp modal tạo/sửa bộ đề và điều hướng sang DeckDetailCardsView.

import SwiftUI

public struct DeckListView: View {
    @Environment(\.lockInPalette) private var palette
    @Bindable var viewModel: DeckListAndEditorViewModel

    @State private var isPresentingEditor = false
    @State private var editingDeck: StudyDeckDTO?
    @State private var draftTitle = ""
    @State private var draftSubject = ""
    @State private var draftAccentHex = "#2563EB"
    @State private var draftHasExamDate = false
    @State private var draftExamDate = Date()
    @State private var draftDailyGoal = 15

    private let accentOptions = ["#2563EB", "#14B8A6", "#16A34A", "#F59E0B", "#C2410C", "#7C3AED"]

    public init(viewModel: DeckListAndEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Bộ đề ôn thi", systemImage: "books.vertical.fill")
                    .font(.headline)
                Spacer()
                Button {
                    openCreator()
                } label: {
                    Label("Tạo bộ đề", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color(lockInHex: palette.accentHex))
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if viewModel.decks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.title2)
                        .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                    Text("Chưa có bộ đề nào. Bấm \"Tạo bộ đề\" để thêm tài liệu ôn thi.")
                        .font(.footnote)
                        .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(viewModel.decks) { deck in
                    deckCard(deck)
                }
            }
        }
        .minimalCardStyle()
        .task {
            viewModel.startObserving()
            await viewModel.refreshDecks()
        }
        .sheet(isPresented: $isPresentingEditor) {
            deckEditorSheet
        }
    }

    @ViewBuilder
    private func deckCard(_ deck: StudyDeckDTO) -> some View {
        let isPinned = viewModel.activeDeckIdOnLockScreen == deck.id
        let countdown = viewModel.examCountdownDays(for: deck.examDate)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                NavigationLink {
                    DeckDetailCardsView(deckId: deck.id, viewModel: viewModel)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(lockInHex: deck.accentHex))
                                .frame(width: 10, height: 10)
                            Text(deck.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color(lockInHex: palette.textPrimaryHex))
                        }

                        if !deck.subjectTag.isEmpty {
                            Text(deck.subjectTag)
                                .font(.caption)
                                .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if let countdown {
                    Text(countdown >= 0 ? "Còn \(countdown) ngày" : "Đã qua thi")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(lockInHex: deck.accentHex).opacity(0.14), in: Capsule())
                        .foregroundStyle(Color(lockInHex: deck.accentHex))
                }
            }

            ProgressBarComponent(
                title: "Đã thuộc \(deck.masteredCards)/\(deck.totalCards) thẻ",
                progress: deck.masteryRatio,
                accentHex: deck.accentHex,
                height: 8
            )

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.pinDeckToLockScreen(deck.id) }
                } label: {
                    Label(
                        isPinned ? "Đang ghim Lock Screen" : "Đưa lên màn hình khóa",
                        systemImage: isPinned ? "pin.circle.fill" : "pin.fill"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(lockInHex: deck.accentHex))

                Spacer()

                Button {
                    openEditor(for: deck)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    Task { await viewModel.deleteDeck(deck.id) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color(lockInHex: palette.backgroundHex).opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var deckEditorSheet: some View {
        NavigationStack {
            Form {
                Section("Thông tin bộ đề") {
                    TextField("Tên bộ đề (vd: Giải tích 1)", text: $draftTitle)
                    TextField("Môn học / Tag", text: $draftSubject)
                    Stepper("Mục tiêu ngày: \(draftDailyGoal) thẻ", value: $draftDailyGoal, in: 1...200)
                }

                Section("Màu nhấn") {
                    HStack(spacing: 12) {
                        ForEach(accentOptions, id: \.self) { hex in
                            Circle()
                                .fill(Color(lockInHex: hex))
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if draftAccentHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture {
                                    draftAccentHex = hex
                                }
                        }
                    }
                }

                Section("Ngày thi (ExamCountdown)") {
                    Toggle("Đặt mốc ngày thi", isOn: $draftHasExamDate)
                    if draftHasExamDate {
                        DatePicker("Ngày thi", selection: $draftExamDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(editingDeck == nil ? "Tạo bộ đề mới" : "Chỉnh sửa bộ đề")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { isPresentingEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        Task {
                            let saved = await viewModel.saveDeck(
                                editingDeckId: editingDeck?.id,
                                title: draftTitle,
                                subjectTag: draftSubject,
                                accentHex: draftAccentHex,
                                examDate: draftHasExamDate ? draftExamDate : nil,
                                dailyGoal: draftDailyGoal
                            )
                            if saved { isPresentingEditor = false }
                        }
                    }
                }
            }
        }
    }

    private func openCreator() {
        editingDeck = nil
        draftTitle = ""
        draftSubject = ""
        draftAccentHex = accentOptions[0]
        draftHasExamDate = false
        draftExamDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
        draftDailyGoal = 15
        isPresentingEditor = true
    }

    private func openEditor(for deck: StudyDeckDTO) {
        editingDeck = deck
        draftTitle = deck.title
        draftSubject = deck.subjectTag
        draftAccentHex = deck.accentHex
        draftHasExamDate = deck.examDate != nil
        draftExamDate = deck.examDate ?? Date()
        draftDailyGoal = deck.dailyGoal
        isPresentingEditor = true
    }
}
