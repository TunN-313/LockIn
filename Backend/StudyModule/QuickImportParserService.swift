// QuickImportParserService.swift — Phân tích văn bản dán nhanh "Câu hỏi | Đáp án | Ghi chú" thành danh sách thẻ.
// Thực thi giới hạn tối đa 500 dòng và 500 ký tự/trường theo chuẩn bảo mật đầu vào của StudyModule.

import Foundation

public protocol QuickImportParserProtocol: Sendable {
    func parsePreview(rawText: String) -> QuickImportPreview
}

public final class QuickImportParserService: QuickImportParserProtocol {
    public init() {}

    public func parsePreview(rawText: String) -> QuickImportPreview {
        let normalizedNewlines = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let allLines = normalizedNewlines.components(separatedBy: "\n")

        var candidates: [QuickImportCandidate] = []
        var errors: [QuickImportLineError] = []
        var nonEmptyProcessed = 0
        var truncatedOverLimit = false

        for (index, rawLine) in allLines.enumerated() {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            if nonEmptyProcessed >= AppConstants.maxQuickImportLines {
                truncatedOverLimit = true
                break
            }
            nonEmptyProcessed += 1
            let lineNumber = index + 1

            let parts = trimmedLine.components(separatedBy: "|")
            guard parts.count >= 2 else {
                errors.append(
                    QuickImportLineError(
                        lineNumber: lineNumber,
                        rawLine: trimmedLine,
                        reason: "Thiếu dấu '|' phân cách Câu hỏi và Đáp án."
                    )
                )
                continue
            }

            let question = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let hintOrNote = parts.count >= 3
                ? parts.dropFirst(2).joined(separator: " | ").trimmingCharacters(in: .whitespacesAndNewlines)
                : ""

            guard !question.isEmpty, !answer.isEmpty else {
                errors.append(
                    QuickImportLineError(
                        lineNumber: lineNumber,
                        rawLine: trimmedLine,
                        reason: "Câu hỏi hoặc Đáp án không được để trống."
                    )
                )
                continue
            }

            guard question.count <= AppConstants.maxFieldCharacterLength,
                  answer.count <= AppConstants.maxFieldCharacterLength,
                  hintOrNote.count <= AppConstants.maxFieldCharacterLength else {
                errors.append(
                    QuickImportLineError(
                        lineNumber: lineNumber,
                        rawLine: trimmedLine,
                        reason: "Mỗi trường không được vượt quá \(AppConstants.maxFieldCharacterLength) ký tự."
                    )
                )
                continue
            }

            candidates.append(QuickImportCandidate(question: question, answer: answer, hintOrNote: hintOrNote))
        }

        return QuickImportPreview(
            candidates: candidates,
            errors: errors,
            truncatedOverLimit: truncatedOverLimit
        )
    }
}
