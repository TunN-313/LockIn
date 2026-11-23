// SharedTaskQuickActionEngine.swift — Hoàn thành nhanh TaskItem ưu tiên kế tiếp từ Lock Screen Widget.
// Chỉ phụ thuộc Shared/**; kiểm tra expectedRevisionId trong flock trước khi lưu SwiftData để tránh ghi đè chéo tiến trình.

import Foundation
import SwiftData
import WidgetKit

public struct TaskQuickActionResult: Equatable, Sendable {
    public let completedTaskId: UUID?
    public let nextPendingTaskId: UUID?
    public let nextPendingTaskTitle: String?
    public let snapshotVersion: Int

    public init(
        completedTaskId: UUID?,
        nextPendingTaskId: UUID?,
        nextPendingTaskTitle: String?,
        snapshotVersion: Int
    ) {
        self.completedTaskId = completedTaskId
        self.nextPendingTaskId = nextPendingTaskId
        self.nextPendingTaskTitle = nextPendingTaskTitle
        self.snapshotVersion = snapshotVersion
    }
}

public protocol SharedTaskQuickActionEngineProtocol: Sendable {
    func completeNextPendingTask() async throws -> TaskQuickActionResult
}

public final class SharedTaskQuickActionEngine: SharedTaskQuickActionEngineProtocol, @unchecked Sendable {
    private let modelContainer: ModelContainer
    private let snapshotStore: AppGroupSnapshotStoreProtocol

    public init(modelContainer: ModelContainer, snapshotStore: AppGroupSnapshotStoreProtocol) {
        self.modelContainer = modelContainer
        self.snapshotStore = snapshotStore
    }

    public static func makeShared() throws -> SharedTaskQuickActionEngine {
        let container = try SharedStoreContainer.makeShared()
        let store = try AppGroupSnapshotStore.makeShared()
        return SharedTaskQuickActionEngine(modelContainer: container, snapshotStore: store)
    }

    public func completeNextPendingTask() async throws -> TaskQuickActionResult {
        for attempt in 0..<2 {
            let initialSnapshot = try snapshotStore.loadSnapshot()
            guard let userId = initialSnapshot.activeUserId,
                  let sessionEpoch = initialSnapshot.sessionEpoch else {
                throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
            }

            let context = ModelContext(modelContainer)
            let uid = userId
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate<TaskItem> { $0.ownerUserId == uid && $0.isCompleted == false }
            )
            let pendingTasks = try context.fetch(descriptor).sorted(by: Self.sortTasks)
            var completedId: UUID?
            var nextTaskIdResult: UUID?
            var nextTaskTitleResult: String?

            do {
                let updatedSnapshot = try snapshotStore.mutateSnapshotIfSessionMatches(
                    expectedUserId: userId,
                    expectedSessionEpoch: sessionEpoch,
                    expectedRevisionId: initialSnapshot.snapshotRevisionId
                ) { state in
                    if let expectedTaskId = initialSnapshot.nextTaskId, state.nextTaskId != expectedTaskId {
                        throw AppGroupStorageError.staleSnapshotRevision(
                            expected: initialSnapshot.snapshotRevisionId,
                            actual: state.snapshotRevisionId
                        )
                    }

                    guard let topTask = pendingTasks.first else {
                        state.nextTaskId = nil
                        state.nextTaskTitle = nil
                        completedId = nil
                        nextTaskIdResult = nil
                        nextTaskTitleResult = nil
                        return
                    }

                    topTask.isCompleted = true
                    topTask.completedAt = Date()

                    let todayProgress = try SharedDailyProgressHelper.fetchOrCreateTodayProgress(for: userId, in: context)
                    try SharedDailyProgressHelper.recordActivity(
                        on: todayProgress,
                        tasksCompletedDelta: 1,
                        in: context
                    )
                    try context.save()

                    let remainingNext = pendingTasks.dropFirst().first
                    completedId = topTask.id
                    nextTaskIdResult = remainingNext?.id
                    nextTaskTitleResult = remainingNext?.title

                    state.nextTaskId = remainingNext?.id
                    state.nextTaskTitle = remainingNext?.title
                    state.dailyProgressRatio = SharedDailyProgressHelper.completionRatio(for: todayProgress)
                    state.streakCount = todayProgress.streakCount
                }

                WidgetCenter.shared.reloadAllTimelines()
                CrossProcessNotifier.postStateDidChange()

                return TaskQuickActionResult(
                    completedTaskId: completedId,
                    nextPendingTaskId: nextTaskIdResult,
                    nextPendingTaskTitle: nextTaskTitleResult,
                    snapshotVersion: updatedSnapshot.snapshotVersion
                )
            } catch let error as AppGroupStorageError {
                if case .staleSnapshotRevision = error, attempt == 0 {
                    let latest = try snapshotStore.loadSnapshot()
                    if latest.activeUserId == userId,
                       latest.sessionEpoch == sessionEpoch,
                       latest.nextTaskId == initialSnapshot.nextTaskId {
                        continue
                    }
                }
                throw error
            }
        }

        throw AppGroupStorageError.storageIOFailure("Không thể đồng bộ hoàn thành tác vụ do xung đột revision liên tiếp.")
    }

    public static func sortTasks(lhs: TaskItem, rhs: TaskItem) -> Bool {
        if lhs.priorityRaw != rhs.priorityRaw {
            return lhs.priorityRaw > rhs.priorityRaw
        }
        switch (lhs.dueDate, rhs.dueDate) {
        case let (lDate?, rDate?) where lDate != rDate:
            return lDate < rDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
