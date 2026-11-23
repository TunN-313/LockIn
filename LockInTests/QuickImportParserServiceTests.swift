// QuickImportParserServiceTests.swift — Kiểm thử parser nhập nhanh "Câu hỏi | Đáp án | Ghi chú".
// Thuộc LockInTests (M4b); xác minh chuẩn hóa xuống dòng, ghép dấu '|' trong ghi chú, báo lỗi dòng và trần 500 dòng.

import XCTest
@testable import LockInApp

final class QuickImportParserServiceTests: XCTestCase {
    func testParsesValidTwoAndThreeColumnLinesWithNormalizedNewlines() {
        let parser = QuickImportParserService()
        let rawInput = [
            "  ",
            "HTTP 401 | Unauthorized | Thiếu xác thực \r",
            "HTTP 403 | Forbidden | Có xác thực | Nhưng thiếu quyền\r\n",
            "\tBig-O Binary Search   |   O(log n)   \n",
            ""
        ].joined()

        let preview = parser.parsePreview(rawText: rawInput)

        XCTAssertFalse(preview.truncatedOverLimit)
        XCTAssertTrue(preview.errors.isEmpty)
        XCTAssertEqual(preview.candidates.count, 3)

        XCTAssertEqual(
            preview.candidates[0],
            QuickImportCandidate(question: "HTTP 401", answer: "Unauthorized", hintOrNote: "Thiếu xác thực")
        )
        XCTAssertEqual(
            preview.candidates[1],
            QuickImportCandidate(question: "HTTP 403", answer: "Forbidden", hintOrNote: "Có xác thực | Nhưng thiếu quyền")
        )
        XCTAssertEqual(
            preview.candidates[2],
            QuickImportCandidate(question: "Big-O Binary Search", answer: "O(log n)", hintOrNote: "")
        )
    }

    func testCollectsErrorsForMissingDelimiterEmptyFieldsAndOverlengthText() {
        let parser = QuickImportParserService()
        let tooLongField = String(repeating: "x", count: AppConstants.maxFieldCharacterLength + 1)
        let exactLimitField = String(repeating: "y", count: AppConstants.maxFieldCharacterLength)

        let rawInput = """
        Dòng thiếu phân cách
           | Có đáp án nhưng trống câu hỏi
        Có câu hỏi |   
        \(tooLongField) | Quá dài
        \(exactLimitField) | Hợp lệ | Ghi chú ngắn
        """

        let preview = parser.parsePreview(rawText: rawInput)

        XCTAssertFalse(preview.truncatedOverLimit)
        XCTAssertEqual(preview.candidates.count, 1)
        XCTAssertEqual(preview.candidates.first?.answer, "Hợp lệ")

        XCTAssertEqual(preview.errors.count, 4)
        XCTAssertEqual(preview.errors.map(\.lineNumber), [1, 2, 3, 4])
    }

    func testEnforcesMaximum500NonEmptyLinesCap() {
        let parser = QuickImportParserService()
        var lines: [String] = ["", "   "]
        for idx in 1...505 {
            lines.append("Câu \(idx) | Đáp án \(idx)")
            if idx % 100 == 0 {
                lines.append("")
            }
        }

        let preview = parser.parsePreview(rawText: lines.joined(separator: "\n"))

        XCTAssertTrue(preview.truncatedOverLimit)
        XCTAssertEqual(preview.candidates.count, AppConstants.maxQuickImportLines)
        XCTAssertEqual(preview.candidates.first?.question, "Câu 1")
        XCTAssertEqual(preview.candidates.last?.question, "Câu \(AppConstants.maxQuickImportLines)")
        XCTAssertTrue(preview.errors.isEmpty)
    }
}
