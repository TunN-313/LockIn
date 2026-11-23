// StudySessionAttributes.swift — Định nghĩa ActivityAttributes và ContentState bất biến (< 4KB UTF-8) cho Live Activity.
// Mọi thuộc tính dùng `let`, ép activeThemeId/fontScaleRaw vào tập hợp hợp lệ và áp trần 220 ký tự / < 4,096 bytes.

import ActivityKit
import Foundation

public struct StudySessionAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public static let safeMaxEncodedBytes = 3_800

        public let deckId: UUID
        public let deckTitle: String
        public let currentCardId: UUID?
        public let questionText: String
        public let answerText: String
        public let isAnswerVisible: Bool
        public let currentIndex: Int
        public let totalCards: Int
        public let masteredCount: Int
        public let activeThemeId: String
        public let privacyModeEnabled: Bool
        public let fontScaleRaw: String

        public init(
            deckId: UUID,
            deckTitle: String,
            currentCardId: UUID?,
            questionText: String,
            answerText: String,
            isAnswerVisible: Bool,
            currentIndex: Int,
            totalCards: Int,
            masteredCount: Int,
            activeThemeId: String,
            privacyModeEnabled: Bool,
            fontScaleRaw: String
        ) {
            self = Self.sanitize(
                deckId: deckId,
                deckTitle: deckTitle,
                currentCardId: currentCardId,
                questionText: questionText,
                answerText: answerText,
                isAnswerVisible: isAnswerVisible,
                currentIndex: currentIndex,
                totalCards: totalCards,
                masteredCount: masteredCount,
                activeThemeId: activeThemeId,
                privacyModeEnabled: privacyModeEnabled,
                fontScaleRaw: fontScaleRaw
            )
        }

        private init(
            uncheckedDeckId deckId: UUID,
            deckTitle: String,
            currentCardId: UUID?,
            questionText: String,
            answerText: String,
            isAnswerVisible: Bool,
            currentIndex: Int,
            totalCards: Int,
            masteredCount: Int,
            activeThemeId: String,
            privacyModeEnabled: Bool,
            fontScaleRaw: String
        ) {
            self.deckId = deckId
            self.deckTitle = deckTitle
            self.currentCardId = currentCardId
            self.questionText = questionText
            self.answerText = answerText
            self.isAnswerVisible = isAnswerVisible
            self.currentIndex = currentIndex
            self.totalCards = totalCards
            self.masteredCount = masteredCount
            self.activeThemeId = activeThemeId
            self.privacyModeEnabled = privacyModeEnabled
            self.fontScaleRaw = fontScaleRaw
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let deckId = try container.decode(UUID.self, forKey: .deckId)
            let deckTitle = try container.decode(String.self, forKey: .deckTitle)
            let currentCardId = try container.decodeIfPresent(UUID.self, forKey: .currentCardId)
            let questionText = try container.decode(String.self, forKey: .questionText)
            let answerText = try container.decode(String.self, forKey: .answerText)
            let isAnswerVisible = try container.decode(Bool.self, forKey: .isAnswerVisible)
            let currentIndex = try container.decode(Int.self, forKey: .currentIndex)
            let totalCards = try container.decode(Int.self, forKey: .totalCards)
            let masteredCount = try container.decode(Int.self, forKey: .masteredCount)
            let activeThemeId = try container.decode(String.self, forKey: .activeThemeId)
            let privacyModeEnabled = try container.decode(Bool.self, forKey: .privacyModeEnabled)
            let fontScaleRaw = try container.decode(String.self, forKey: .fontScaleRaw)

            self.init(
                deckId: deckId,
                deckTitle: deckTitle,
                currentCardId: currentCardId,
                questionText: questionText,
                answerText: answerText,
                isAnswerVisible: isAnswerVisible,
                currentIndex: currentIndex,
                totalCards: totalCards,
                masteredCount: masteredCount,
                activeThemeId: activeThemeId,
                privacyModeEnabled: privacyModeEnabled,
                fontScaleRaw: fontScaleRaw
            )
        }

        /// Khởi tạo ContentState bất biến đã chuẩn hóa qua cùng phép kiểm tra ký tự (<= 220), tập giá trị hợp lệ và trần JSON (< 4,096 bytes).
        public static func makeSafe(
            deckId: UUID,
            deckTitle: String,
            currentCardId: UUID?,
            questionText: String,
            answerText: String,
            isAnswerVisible: Bool,
            currentIndex: Int,
            totalCards: Int,
            masteredCount: Int,
            activeThemeId: String,
            privacyModeEnabled: Bool,
            fontScaleRaw: String
        ) -> ContentState {
            ContentState(
                deckId: deckId,
                deckTitle: deckTitle,
                currentCardId: currentCardId,
                questionText: questionText,
                answerText: answerText,
                isAnswerVisible: isAnswerVisible,
                currentIndex: currentIndex,
                totalCards: totalCards,
                masteredCount: masteredCount,
                activeThemeId: activeThemeId,
                privacyModeEnabled: privacyModeEnabled,
                fontScaleRaw: fontScaleRaw
            )
        }

        /// Ước lượng kích thước JSON (bytes) để kiểm chứng toàn bộ payload không vượt quá 4,096 bytes của ActivityKit.
        public func estimatedJSONByteCount() -> Int {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(self) else {
                return Int.max
            }
            return data.count
        }

        public var isWithinActivityKitPayloadLimit: Bool {
            estimatedJSONByteCount() < AppConstants.maxLiveActivityContentStateBytes
        }

        private static func sanitize(
            deckId: UUID,
            deckTitle: String,
            currentCardId: UUID?,
            questionText: String,
            answerText: String,
            isAnswerVisible: Bool,
            currentIndex: Int,
            totalCards: Int,
            masteredCount: Int,
            activeThemeId: String,
            privacyModeEnabled: Bool,
            fontScaleRaw: String
        ) -> ContentState {
            var safeTitle = truncateCharacters(deckTitle, limit: AppConstants.maxLiveActivityDeckTitleLength)
            var safeQuestion = truncateCharacters(questionText, limit: AppConstants.maxLiveActivityTextLength)
            var safeAnswer = truncateCharacters(answerText, limit: AppConstants.maxLiveActivityTextLength)
            // Ép metadata vào tập giá trị đóng hợp lệ để không thể bơm chuỗi Unicode nhiều byte vào metadata.
            let safeThemeId = ThemePalette.palette(for: activeThemeId).id
            let safeFontScale = (LockScreenFontScale(rawValue: fontScaleRaw) ?? .standard).rawValue
            let clampedIndex = max(0, currentIndex)
            let clampedTotal = max(0, totalCards)
            let clampedMastered = max(0, masteredCount)

            var state = ContentState(
                uncheckedDeckId: deckId,
                deckTitle: safeTitle,
                currentCardId: currentCardId,
                questionText: safeQuestion,
                answerText: safeAnswer,
                isAnswerVisible: isAnswerVisible,
                currentIndex: clampedIndex,
                totalCards: clampedTotal,
                masteredCount: clampedMastered,
                activeThemeId: safeThemeId,
                privacyModeEnabled: privacyModeEnabled,
                fontScaleRaw: safeFontScale
            )

            let targetBytes = min(safeMaxEncodedBytes, AppConstants.maxLiveActivityContentStateBytes - 1)
            for _ in 0..<64 {
                if state.estimatedJSONByteCount() <= targetBytes {
                    return state
                }
                let qBytes = safeQuestion.utf8.count
                let aBytes = safeAnswer.utf8.count
                let tBytes = safeTitle.utf8.count

                if aBytes >= qBytes && aBytes >= tBytes && aBytes > 0 {
                    safeAnswer = shrinkByHalfUTF8(safeAnswer)
                } else if qBytes >= tBytes && qBytes > 0 {
                    safeQuestion = shrinkByHalfUTF8(safeQuestion)
                } else if tBytes > 0 {
                    safeTitle = shrinkByHalfUTF8(safeTitle)
                } else {
                    break
                }

                state = ContentState(
                    uncheckedDeckId: deckId,
                    deckTitle: safeTitle,
                    currentCardId: currentCardId,
                    questionText: safeQuestion,
                    answerText: safeAnswer,
                    isAnswerVisible: isAnswerVisible,
                    currentIndex: clampedIndex,
                    totalCards: clampedTotal,
                    masteredCount: clampedMastered,
                    activeThemeId: safeThemeId,
                    privacyModeEnabled: privacyModeEnabled,
                    fontScaleRaw: safeFontScale
                )
            }

            if !state.isWithinActivityKitPayloadLimit {
                state = ContentState(
                    uncheckedDeckId: deckId,
                    deckTitle: "",
                    currentCardId: currentCardId,
                    questionText: "",
                    answerText: "",
                    isAnswerVisible: isAnswerVisible,
                    currentIndex: clampedIndex,
                    totalCards: clampedTotal,
                    masteredCount: clampedMastered,
                    activeThemeId: safeThemeId,
                    privacyModeEnabled: privacyModeEnabled,
                    fontScaleRaw: safeFontScale
                )
            }
            return state
        }

        private static func truncateCharacters(_ value: String, limit: Int) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > limit else { return trimmed }
            let prefixCount = max(0, limit - 3)
            return prefixCount > 0 ? String(trimmed.prefix(prefixCount)) + "..." : ""
        }

        private static func shrinkByHalfUTF8(_ value: String) -> String {
            let currentBytes = value.utf8.count
            let nextBudget = currentBytes / 2
            guard nextBudget >= 4 else { return "" }
            return truncateToUTF8Bytes(value, maxUTF8Bytes: nextBudget)
        }

        /// Cắt chuỗi theo đúng ranh giới grapheme cluster (Character) để không làm hỏng ký tự Unicode/emoji đa byte.
        private static func truncateToUTF8Bytes(_ value: String, maxUTF8Bytes: Int) -> String {
            guard value.utf8.count > maxUTF8Bytes else { return value }
            let ellipsis = "..."
            let ellipsisBytes = ellipsis.utf8.count
            guard maxUTF8Bytes > ellipsisBytes else { return "" }

            let budget = maxUTF8Bytes - ellipsisBytes
            var usedBytes = 0
            var result = ""
            for character in value {
                let charBytes = String(character).utf8.count
                if usedBytes + charBytes > budget {
                    break
                }
                result.append(character)
                usedBytes += charBytes
            }
            return result.isEmpty ? "" : result + ellipsis
        }
    }

    public let sessionId: UUID

    public init(sessionId: UUID = UUID()) {
        self.sessionId = sessionId
    }
}
