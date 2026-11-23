// TaskProgressStreakServiceTests.swift — Kiểm thử CRUD tác vụ, tiến độ ngày, chuỗi streak và khóa lạc quan snapshot.
// Thuộc LockInTests (M4b); xác minh sắp xếp ưu tiên, nối tiếp streak từ ngày hôm trước và từ chối revision cũ.

import SwiftData
import XCTest
@testable import LockInApp

final class TaskProgressStreakServiceTests: XCTestCase {
    @MainActor
    func testTaskCrudSortingToggleCompletionAndSnapshotSync() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "TaskOwner#2026"

        _ = try await env.container.auth.register(
            username: "task_streak_tester",
            displayName: "Task Tester",
            password: userCredential
        )

        let lowTask = try await env.container.study.createTask(
            title: "Low Priority Reading",
            notes: "",
            dueDate: nil,
            priority: .low,
            linkedDeckId: nil
        )
        let highTask = try await env.container.study.createTask(
            title: "High Priority Practice",
            notes: "Urgent",
            dueDate: Date().addingTimeInterval(1800),
            priority: .high,
            linkedDeckId: nil
        )

        let sortedInitial = try await env.container.study.fetchTasks()
        XCTAssertEqual(sortedInitial.map(\.id), [highTask.id, lowTask.id])
        XCTAssertEqual(try env.snapshotStore.loadSnapshot().nextTaskId, highTask.id)

        let completedHigh = try await env.container.study.toggleTaskCompletion(taskId: highTask.id)
        XCTAssertTrue(completedHigh.isCompleted)
        XCTAssertNotNil(completedHigh.completedAt)

        let afterToggleTasks = try await env.container.study.fetchTasks()
        XCTAssertEqual(afterToggleTasks.map(\.id), [lowTask.id, highTask.id])

        let progress = try await env.container.study.fetchTodayProgress()
        XCTAssertEqual(progress.tasksCompleted, 1)
        XCTAssertEqual(progress.streakCount, 1)
        XCTAssertGreaterThan(progress.completionRatio, 0)

        let updatedSnapshot = try env.snapshotStore.loadSnapshot()
        XCTAssertEqual(updatedSnapshot.nextTaskId, lowTask.id)
        XCTAssertEqual(updatedSnapshot.streakCount, 1)
        XCTAssertGreaterThan(updatedSnapshot.dailyProgressRatio, 0)

        let updatedLow = try await env.container.study.updateTask(
            taskId: lowTask.id,
            title: "Updated Medium Task",
            notes: "Revised notes",
            dueDate: nil,
            priority: .medium,
            linkedDeckId: nil
        )
        XCTAssertEqual(updatedLow.title, "Updated Medium Task")
        XCTAssertEqual(updatedLow.priority, .medium)

        _ = try await env.container.study.toggleTaskCompletion(taskId: highTask.id)
        let decrementedProgress = try await env.container.study.fetchTodayProgress()
        XCTAssertEqual(decrementedProgress.tasksCompleted, 0)

        try await env.container.study.deleteTask(taskId: lowTask.id)
        let remaining = try await env.container.study.fetchTasks()
        XCTAssertEqual(remaining.map(\.id), [highTask.id])
    }

    @MainActor
    func testPendingReminderSummaryAndConsecutiveDayStreakCarryOver() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "StreakOwner#2026"

        let user = try await env.container.auth.register(
            username: "streak_carry_tester",
            displayName: "Streak Carry",
            password: userCredential
        )

        let deck = try await env.container.study.createDeck(
            title: "Calculus Review",
            subjectTag: "Math",
            accentHex: "#2563EB",
            examDate: nil,
            dailyGoal: 10
        )
        _ = try await env.container.study.upsertCard(
            cardId: nil,
            deckId: deck.id,
            question: "d/dx(sin x)?",
            answer: "cos x",
            hintOrNote: "",
            status: .new
        )

        _ = try await env.container.study.createTask(
            title: "Overdue Problem Set",
            notes: "",
            dueDate: Date().addingTimeInterval(-3600),
            priority: .high,
            linkedDeckId: deck.id
        )
        let dueTodayTask = try await env.container.study.createTask(
            title: "Today Summary Task",
            notes: "",
            dueDate: Date().addingTimeInterval(600),
            priority: .medium,
            linkedDeckId: deck.id
        )

        let reminder = try await env.container.study.fetchPendingReminderSummary()
        XCTAssertEqual(reminder.overdueTasksCount, 1)
        XCTAssertEqual(reminder.dueTodayTasksCount, 1)
        XCTAssertGreaterThan(reminder.remainingDailyGoalCount, 0)
        XCTAssertEqual(reminder.suggestedDeckId, deck.id)
        XCTAssertTrue(reminder.hasPendingItems)

        // Nạp bản ghi DailyProgress hôm qua có hoạt động và streak = 3 để kiểm tra nối tiếp sang hôm nay thành 4.
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        let context = ModelContext(env.modelContainer)
        let yesterdayProgress = DailyProgress(
            ownerUserId: user.id,
            dateKey: SharedDailyProgressHelper.dateKey(for: yesterday),
            cardsReviewed: 5,
            cardsMastered: 2,
            tasksCompleted: 1,
            dailyTargetCount: 10,
            streakCount: 3
        )
        context.insert(yesterdayProgress)
        try context.save()

        _ = try await env.container.study.toggleTaskCompletion(taskId: dueTodayTask.id)
        let todayProgress = try await env.container.study.fetchTodayProgress()
        XCTAssertEqual(todayProgress.streakCount, 4)
    }

    @MainActor
    func testSnapshotOptimisticLockRejectsStaleRevisionAndLoggedOutSession() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "LockTester#2026"

        let user = try await env.container.auth.register(
            username: "snapshot_lock_tester",
            displayName: "Snapshot Tester",
            password: userCredential
        )

        let initialSnapshot = try env.snapshotStore.loadSnapshot()
        let initialEpoch = try XCTUnwrap(initialSnapshot.sessionEpoch)
        let staleRevisionId = initialSnapshot.snapshotRevisionId

        let updated = try env.snapshotStore.mutateSnapshotIfSessionMatches(
            expectedUserId: user.id,
            expectedSessionEpoch: initialEpoch
        ) { state in
            state.activeThemeId = ThemePalette.darkFocus.id
        }
        XCTAssertNotEqual(updated.snapshotRevisionId, staleRevisionId)

        var staleCopy = initialSnapshot
        staleCopy.activeThemeId = ThemePalette.midnightInk.id
        XCTAssertThrowsError(
            try env.snapshotStore.saveSnapshotIfSessionMatches(
                staleCopy,
                expectedUserId: user.id,
                expectedSessionEpoch: initialEpoch,
                expectedRevisionId: staleRevisionId
            )
        ) { error in
            guard case AppGroupStorageError.staleSnapshotRevision = error else {
                return XCTFail("Kỳ vọng staleSnapshotRevision, nhận: \(error)")
            }
        }

        try await env.container.auth.logout()
        XCTAssertThrowsError(
            try env.snapshotStore.saveSnapshotIfSessionMatches(
                updated,
                expectedUserId: user.id,
                expectedSessionEpoch: initialEpoch,
                expectedRevisionId: updated.snapshotRevisionId
            )
        ) { error in
            XCTAssertEqual(error as? AppGroupStorageError, .sessionInvalidatedOrLoggedOut)
        }
    }
}
