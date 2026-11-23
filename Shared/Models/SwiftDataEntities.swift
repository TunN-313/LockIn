// SwiftDataEntities.swift — Định nghĩa 7 @Model SwiftData và các enum trạng thái cốt lõi của LockIn.
// Cung cấp schema lưu trữ cục bộ dùng chung qua SharedStoreContainer giữa Backend và LockInWidgetsExtension.

import Foundation
import SwiftData

public enum StudyCardStatus: String, Codable, CaseIterable, Sendable {
    case new
    case learning
    case mastered
}

public enum TaskPriority: Int, Codable, CaseIterable, Sendable, Comparable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum LockScreenFontScale: String, Codable, CaseIterable, Sendable {
    case compact
    case standard
    case large
}

@Model
public final class UserProfile {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var username: String
    public var displayName: String
    public var passwordHash: Data
    public var passwordSalt: Data
    public var isBiometricEnabled: Bool
    public var createdAt: Date
    public var lastLoginAt: Date?

    public init(
        id: UUID = UUID(),
        username: String,
        displayName: String,
        passwordHash: Data,
        passwordSalt: Data,
        isBiometricEnabled: Bool = false,
        createdAt: Date = Date(),
        lastLoginAt: Date? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.passwordHash = passwordHash
        self.passwordSalt = passwordSalt
        self.isBiometricEnabled = isBiometricEnabled
        self.createdAt = createdAt
        self.lastLoginAt = lastLoginAt
    }
}

@Model
public final class StudyDeck {
    @Attribute(.unique) public var id: UUID
    public var ownerUserId: UUID
    public var title: String
    public var subjectTag: String
    public var accentHex: String
    public var examDate: Date?
    public var dailyGoal: Int
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \StudyCard.deck)
    public var cards: [StudyCard] = []

    public init(
        id: UUID = UUID(),
        ownerUserId: UUID,
        title: String,
        subjectTag: String = "",
        accentHex: String = "#2563EB",
        examDate: Date? = nil,
        dailyGoal: Int = 15,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ownerUserId = ownerUserId
        self.title = title
        self.subjectTag = subjectTag
        self.accentHex = accentHex
        self.examDate = examDate
        self.dailyGoal = dailyGoal
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class StudyCard {
    @Attribute(.unique) public var id: UUID
    public var ownerUserId: UUID
    public var deck: StudyDeck?
    public var question: String
    public var answer: String
    public var hintOrNote: String
    public var statusRaw: String
    public var reviewCount: Int
    public var lastReviewedAt: Date?
    public var sortOrder: Int

    public var status: StudyCardStatus {
        get { StudyCardStatus(rawValue: statusRaw) ?? .new }
        set { statusRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        ownerUserId: UUID,
        deck: StudyDeck? = nil,
        question: String,
        answer: String,
        hintOrNote: String = "",
        status: StudyCardStatus = .new,
        reviewCount: Int = 0,
        lastReviewedAt: Date? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.ownerUserId = ownerUserId
        self.deck = deck
        self.question = question
        self.answer = answer
        self.hintOrNote = hintOrNote
        self.statusRaw = status.rawValue
        self.reviewCount = reviewCount
        self.lastReviewedAt = lastReviewedAt
        self.sortOrder = sortOrder
    }
}

@Model
public final class TaskItem {
    @Attribute(.unique) public var id: UUID
    public var ownerUserId: UUID
    public var title: String
    public var notes: String
    public var dueDate: Date?
    public var priorityRaw: Int
    public var isCompleted: Bool
    public var completedAt: Date?
    public var linkedDeckId: UUID?

    public var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        ownerUserId: UUID,
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        priority: TaskPriority = .medium,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        linkedDeckId: UUID? = nil
    ) {
        self.id = id
        self.ownerUserId = ownerUserId
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priorityRaw = priority.rawValue
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.linkedDeckId = linkedDeckId
    }
}

@Model
public final class StudySchedule {
    @Attribute(.unique) public var id: UUID
    public var ownerUserId: UUID
    public var deckId: UUID
    public var title: String
    public var hour: Int
    public var minute: Int
    public var weekdaysMask: Int
    public var isEnabled: Bool
    public var autoRotateTheme: Bool

    public init(
        id: UUID = UUID(),
        ownerUserId: UUID,
        deckId: UUID,
        title: String,
        hour: Int,
        minute: Int,
        weekdaysMask: Int,
        isEnabled: Bool = true,
        autoRotateTheme: Bool = false
    ) {
        self.id = id
        self.ownerUserId = ownerUserId
        self.deckId = deckId
        self.title = title
        self.hour = hour
        self.minute = minute
        self.weekdaysMask = weekdaysMask
        self.isEnabled = isEnabled
        self.autoRotateTheme = autoRotateTheme
    }

    /// Kiểm tra lịch có lặp vào thứ trong tuần (1 = Chủ Nhật ... 7 = Thứ Bảy theo Calendar.weekday).
    public func isScheduled(onCalendarWeekday weekday: Int) -> Bool {
        guard (1...7).contains(weekday) else { return false }
        let bit = 1 << (weekday - 1)
        return (weekdaysMask & bit) != 0
    }

    public static func makeWeekdaysMask(_ calendarWeekdays: Set<Int>) -> Int {
        calendarWeekdays.reduce(0) { mask, weekday in
            guard (1...7).contains(weekday) else { return mask }
            return mask | (1 << (weekday - 1))
        }
    }
}

@Model
public final class ThemePreference {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var ownerUserId: UUID
    public var activeThemeId: String
    public var isShuffleEnabled: Bool
    public var shufflePoolIds: [String]
    public var rotateOnAppOpen: Bool
    public var rotateOnShortcutTrigger: Bool
    public var lockScreenFontScale: String
    public var hideAnswerByDefault: Bool
    public var privacyModeEnabled: Bool
    public var showPopupOnOpen: Bool

    public var fontScale: LockScreenFontScale {
        get { LockScreenFontScale(rawValue: lockScreenFontScale) ?? .standard }
        set { lockScreenFontScale = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        ownerUserId: UUID,
        activeThemeId: String = "minimal_paper",
        isShuffleEnabled: Bool = false,
        shufflePoolIds: [String] = ["minimal_paper", "dark_focus"],
        rotateOnAppOpen: Bool = false,
        rotateOnShortcutTrigger: Bool = false,
        lockScreenFontScale: LockScreenFontScale = .standard,
        hideAnswerByDefault: Bool = true,
        privacyModeEnabled: Bool = false,
        showPopupOnOpen: Bool = true
    ) {
        self.id = id
        self.ownerUserId = ownerUserId
        self.activeThemeId = activeThemeId
        self.isShuffleEnabled = isShuffleEnabled
        self.shufflePoolIds = shufflePoolIds
        self.rotateOnAppOpen = rotateOnAppOpen
        self.rotateOnShortcutTrigger = rotateOnShortcutTrigger
        self.lockScreenFontScale = lockScreenFontScale.rawValue
        self.hideAnswerByDefault = hideAnswerByDefault
        self.privacyModeEnabled = privacyModeEnabled
        self.showPopupOnOpen = showPopupOnOpen
    }
}

@Model
public final class DailyProgress {
    @Attribute(.unique) public var id: UUID
    public var ownerUserId: UUID
    public var dateKey: String
    public var cardsReviewed: Int
    public var cardsMastered: Int
    public var tasksCompleted: Int
    public var dailyTargetCount: Int
    public var streakCount: Int

    public init(
        id: UUID = UUID(),
        ownerUserId: UUID,
        dateKey: String,
        cardsReviewed: Int = 0,
        cardsMastered: Int = 0,
        tasksCompleted: Int = 0,
        dailyTargetCount: Int = 20,
        streakCount: Int = 0
    ) {
        self.id = id
        self.ownerUserId = ownerUserId
        self.dateKey = dateKey
        self.cardsReviewed = cardsReviewed
        self.cardsMastered = cardsMastered
        self.tasksCompleted = tasksCompleted
        self.dailyTargetCount = dailyTargetCount
        self.streakCount = streakCount
    }
}
