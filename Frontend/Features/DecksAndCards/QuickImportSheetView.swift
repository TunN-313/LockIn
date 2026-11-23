// QuickImportSheetView.swift — Modal nhập liệu nhanh theo cú pháp "Câu hỏi | Đáp án | Ghi chú" và xem trước lỗi.
// Thuộc Frontend/Features/DecksAndCards; gọi previewQuickImport/commitQuickImport qua DeckListAndEditorViewModel.

import SwiftUI

public struct QuickImportSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lockInPalette) private var palette

    let deckId: UUID
    @Bindable var viewModel: DeckListAndEditorViewModel
    @State private var rawText: String = ""
    @State private var isSaving: Bool = false

    public init(deckId: UUID, viewModel: DeckListAndEditorViewModel) {
        self.deckId = deckId
        self.viewModel = viewModel
    }

    private var preview: QuickImportPreview {
        viewModel.previewQuickImport(rawText: rawText)
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mỗi dòng nhập theo mẫu: Câu hỏi | Đáp án | Ghi chú (tối đa 500 dòng, 500 ký tự/trường).")
                    .font(.caption)
                    .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))

                TextEditor(text: $rawText)
                    .font(.footnote.monospaced())
                    .padding(8)
                    .frame(minHeight: 160, maxHeight: 220)
                    .background(Color(lockInHex: palette.cardHex), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(lockInHex: palette.textSecondaryHex).opacity(0.25), lineWidth: 1)
                    )

                HStack(spacing: 12) {
                    Label("\(preview.candidates.count) thẻ hợp lệ", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)

                    if !preview.errors.isEmpty {
                        Label("\(preview.errors.count) dòng lỗi", systemImage: "exclamationmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                if preview.truncatedOverLimit {
                    Label("Vượt quá 500 dòng: chỉ lấy 500 dòng hợp lệ đầu tiên.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                List {
                    if !preview.errors.isEmpty {
                        Section("Dòng chưa đúng định dạng") {
                            ForEach(preview.errors) { err in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Dòng \(err.lineNumber): \(err.reason)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                    Text(err.rawLine)
                                        .font(.caption2)
                                        .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    if !preview.candidates.isEmpty {
                        Section("Xem trước thẻ sẽ lưu") {
                            ForEach(Array(preview.candidates.enumerated()), id: \.offset) { _, candidate in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.question)
                                        .font(.caption.weight(.semibold))
                                    Text(candidate.answer)
                                        .font(.caption2)
                                        .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .padding()
            .navigationTitle("Nhập nhanh (Quick Import)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu \(preview.candidates.count) thẻ") {
                        Task {
                            isSaving = true
                            let count = await viewModel.commitQuickImport(
                                deckId: deckId,
                                candidates: preview.candidates
                            )
                            isSaving = false
                            if count != nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(preview.candidates.isEmpty || isSaving)
                }
            }
        }
    }
}
