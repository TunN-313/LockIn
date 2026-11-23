// TaskProgressStreakService.swift — Quản lý TaskItem, DailyProgress, Streak và PendingReminderSummary.
// Thuộc StudyModule; đồng bộ trạng thái hoàn thành sang AppGroupSnapshotStore, WidgetKit và SyncEventBus.

import Foundation
import SwiftData
import WidgetKit

public protocol TaskProgressStreakServiceProtocol: Sendable {
    func fetchTasks() async throws -> [TaskItemDTO]
    func createTask(title: String, notes: String, dueDate: Date?, priority: TaskPriority, linkedDeckId: UUID?) async throws -> TaskItemDTO
    func updateTask(taskId: UUID, title: String, notes: String, dueDate: Date?, priority: TaskPriority, linkedDeckId: UUID?) async throws -> TaskItemDTO
    func toggleTaskCompletion(taskId: UUID) async throws -> TaskItemDTO
    func deleteTask(taskId: UUID) async throws
    func fetchTodayProgress() async throws -> DailyProgressDTO
    func fetchPendingReminderSummary() async throws -> PendingReminderSummary
}

public final class TaskProgressStreakService: TaskProgressStreakServiceProtocol, @unchecked Sendable {
    private let studyStore: SwiftDataStudyStore
    private let isolationGuard: UserDataIsolationGuardProtocol
    private let snapshotStore: AppGroupSnapshotStoreProtocol
    private let syncEventBus: SyncEventBus

    public init(
        studyStore: SwiftDataStudyStore,
        isolationGuard: UserDataIsolationGuardProtocol,
        snapshotStore: AppGroupSnapshotStoreProtocol,
        syncEventBus: SyncEventBus
    ) {
        self.studyStore = studyStore
        self.isolationGuard = isolationGuard
        self.snapshotStore = snapshotStore
        self.syncEventBus = syncEventBus
    }

    public func fetchTasks() async throws -> [TaskItemDTO] {
        let userId = try isolationGuard.requireActiveUserId()
        return try await studyStore.perform { context in
            let uid = userId
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate<TaskItem> { $0.ownerUserId == uid }
            )
            return try context.fetch(descriptor)
                .sorted { lhs, rhs in
                    if lhs.isCompleted != rhs.isCompleted {
                        return !lhs.isCompleted
                    }
                    return SharedTaskQuickActionEngine.sortTasks(lhs: lhs, rhs: rhs)
                }
                .map(Self.toDTO)
        }
    }

    public func createTask(
        title: String,
        notes: String,
        dueDate: Date?,
        priority: TaskPriority,
        linkedDeckId: UUID?
    ) async throws -> TaskItemDTO {
        let session = try isolationGuard.requireActiveSession()
        let cleanTitle = try validateText(title, fieldName: "Tiêu đề tác vụ", allowEmpty: false)
        let cleanNotes = try validateText(notes, fieldName: "Ghi chú tác vụ", allowEmpty: true)

        let result: (dto: TaskItemDTO, nextTask: (id: UUID, title: String)?, ratio: Double, streak: Int) =
            try await studyStore.perform { context in
                let uid = session.userId
                if let deckId = linkedDeckId {
                    let targetDeckId = deckId
                    let deckMatches = try context.fetch(
                        FetchDescriptor<StudyDeck>(predicate: #Predicate<StudyDeck> { $0.id == targetDeckId && $0.ownerUserId == uid })
                    )
                    guard !deckMatches.isEmpty else {
                        throw LockInDomainError.entityNotFound
                    }
                }

                let item = TaskItem(
                    ownerUserId: uid,
                    title: cleanTitle,
                    notes: cleanNotes,
                    dueDate: dueDate,
                    priority: priority,
                    isCompleted: false,
                    completedAt: nil,
                    linkedDeckId: linkedDeckId
                )
                context.insert(item)
                try context.save()

                let summary = try Self.computeSnapshotTaskAndProgress(for: uid, in: context)
                return (Self.toDTO(item), summary.nextTask, summary.ratio, summary.streak)
            }

        let marker = try syncSnapshot(
            userId: session.userId,
            sessionEpoch: session.sessionEpoch,
            nextTask: result.nextTask,
            ratio: result.ratio,
            streak: result.streak
        )
        await MainActor.run {
            syncEventBus.publish(.tasksChanged, observedMarker: marker)
        }
        return result.dto
    }

    public func updateTask(
        taskId: UUID,
        title: String,
        notes: String,
        dueDate: Date?,
        priority: TaskPriority,
        linkedDeckId: UUID?
    ) async throws -> TaskItemDTO {
        let session = try isolationGuard.requireActiveSession()
        let cleanTitle = try validateText(title, fieldName: "Tiêu đề tác vụ", allowEmpty: false)
        let cleanNotes = try validateText(notes, fieldName: "Ghi chú tác vụ", allowEmpty: true)

        let result: (dto: TaskItemDTO, nextTask: (id: UUID, title: String)?, ratio: Double, streak: Int) =
            try await studyStore.perform { context in
                let uid = session.userId
                let targetId = taskId
                let descriptor = FetchDescriptor<TaskItem>(
                    predicate: #Predicate<TaskItem> { $0.id == targetId && $0.ownerUserId == uid }
                )
                guard let task = try context.fetch(descriptor).first else {
                    throw LockInDomainError.entityNotFound
                }

                if let deckId = linkedDeckId {
                    let targetDeckId = deckId
                    let deckMatches = try context.fetch(
                        FetchDescriptor<StudyDeck>(predicate: #Predicate<StudyDeck> { $0.id == targetDeckId && $0.ownerUserId == uid })
                    )
                    guard !deckMatches.isEmpty else {
                        throw LockInDomainError.entityNotFound
                    }
                }

                task.title = cleanTitle
                task.notes = cleanNotes
                task.dueDate = dueDate
                task.priority = priority
                task.linkedDeckId = linkedDeckId
                try context.save()

                let summary = try Self.computeSnapshotTaskAndProgress(for: uid, in: context)
                return (Self.toDTO(task), summary.nextTask, summary.ratio, summary.streak)
            }

        let marker = try syncSnapshot(
            userId: session.userId,
            sessionEpoch: session.sessionEpoch,
            nextTask: result.nextTask,
            ratio: result.ratio,
            streak: result.streak
        )
        await MainActor.run {
            syncEventBus.publish(.tasksChanged, observedMarker: marker)
        }
        return result.dto
    }

    public func toggleTaskCompletion(taskId: UUID) async throws -> TaskItemDTO {
        let session = try isolationGuard.requireActiveSession()

        let result: (dto: TaskItemDTO, nextTask: (id: UUID, title: String)?, ratio: Double, streak: Int) =
            try await studyStore.perform { context in
                let uid = session.userId
                let targetId = taskId
                let descriptor = FetchDescriptor<TaskItem>(
                    predicate: #Predicate<TaskItem> { $0.id == targetId && $0.ownerUserId == uid }
                )
                guard let task = try context.fetch(descriptor).first else {
                    throw LockInDomainError.entityNotFound
                }

                let wasCompleted = task.isCompleted
                task.isCompleted = !wasCompleted
                task.completedAt = task.isCompleted ? Date() : nil

                let progress = try SharedDailyProgressHelper.fetchOrCreateTodayProgress(for: uid, in: context)
                if !wasCompleted && task.isCompleted {
                    try SharedDailyProgressHelper.recordActivity(on: progress, tasksCompletedDelta: 1, in: context)
                } else if wasCompleted && !task.isCompleted && progress.tasksCompleted > 0 {
                    progress.tasksCompleted -= 1
                }

                try context.save()
                let summary = try Self.computeSnapshotTaskAndProgress(for: uid, in: context)
                return (Self.toDTO(task), summary.nextTask, summary.ratio, summary.streak)
            }

        let marker = try syncSnapshot(
            userId: session.userId,
            sessionEpoch: session.sessionEpoch,
            nextTask: result.nextTask,
            ratio: result.ratio,
            streak: result.streak
        )
        await MainActor.run {
            syncEventBus.publish(.tasksChanged, observedMarker: marker)
            syncEventBus.publish(.progressUpdated)
        }
        return result.dto
    }

    public func deleteTask(taskId: UUID) async throws {
        let session = try isolationGuard.requireActiveSession()

        let summary: (nextTask: (id: UUID, title: String)?, ratio: Double, streak: Int) =
            try await studyStore.perform { context in
                let uid = session.userId
                let targetId = taskId
                let descriptor = FetchDescriptor<TaskItem>(
                    predicate: #Predicate<TaskItem> { $0.id == targetId && $0.ownerUserId == uid }
                )
                guard let task = try context.fetch(descriptor).first else {
                    throw LockInDomainError.entityNotFound
                }
                context.delete(task)
                try context.save()
                return try Self.computeSnapshotTaskAndProgress(for: uid, in: context)
            }

        let marker = try syncSnapshot(
            userId: session.userId,
            sessionEpoch: session.sessionEpoch,
            nextTask: summary.nextTask,
            ratio: summary.ratio,
            streak: summary.streak
        )
        await MainActor.run {
            syncEventBus.publish(.tasksChanged, observedMarker: marker)
        }
    }

    public func fetchTodayProgress() async throws -> DailyProgressDTO {
        let userId = try isolationGuard.requireActiveUserId()
        return try await studyStore.perform { context in
            let progress = try SharedDailyProgressHelper.fetchOrCreateTodayProgress(for: userId, in: context)
            try context.save()
            return DailyProgressDTO(
                dateKey: progress.dateKey,
                cardsReviewed: progress.cardsReviewed,
                cardsMastered: progress.cardsMastered,
                tasksCompleted: progress.tasksCompleted,
                dailyTargetCount: progress.dailyTargetCount,
                streakCount: progress.streakCount
            )
        }
    }

    public func fetchPendingReminderSummary() async throws -> PendingReminderSummary {
        let userId = try isolationGuard.requireActiveUserId()
        let now = Date()
        let endOfToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now

        return try await studyStore.perform { context in
            let uid = userId
            let pendingTasks = try context.fetch(
                FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.ownerUserId == uid && $0.isCompleted == false })
            )
            let overdueCount = pendingTasks.filter {
                guard let dueDate = $0.dueDate else { return false }
                return dueDate < now
            }.count
            let dueTodayCount = pendingTasks.filter {
                guard let dueDate = $0.dueDate else { return false }
                return dueDate >= now && dueDate <= endOfToday
            }.count

            let todayProgress = try SharedDailyProgressHelper.fetchOrCreateTodayProgress(for: uid, in: context)
            let completedToday = todayProgress.cardsReviewed + todayProgress.tasksCompleted
            let remainingGoal = max(0, todayProgress.dailyTargetCount - completedToday)

            let decks = try context.fetch(
                FetchDescriptor<StudyDeck>(predicate: #Predicate<StudyDeck> { $0.ownerUserId == uid })
            ).sorted { lhs, rhs in
                switch (lhs.examDate, rhs.examDate) {
                case let (lDate?, rDate?):
                    return lDate < rDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.updatedAt > rhs.updatedAt
                }
            }

            try context.save()
            return PendingReminderSummary(
                overdueTasksCount: overdueCount,
                dueTodayTasksCount: dueTodayCount,
                remainingDailyGoalCount: remainingGoal,
                suggestedDeckId: decks.first?.id,
                suggestedDeckTitle: decks.first?.title
            )
        }
    }

    private func syncSnapshot(
        userId: UUID,
        sessionEpoch: UUID,
        nextTask: (id: UUID, title: String)?,
        ratio: Double,
        streak: Int
    ) throws -> SnapshotStateMarker {
        let updated = try snapshotStore.mutateSnapshotIfSessionMatches(
            expectedUserId: userId,
            expectedSessionEpoch: sessionEpoch
        ) { state in
            state.nextTaskId = nextTask?.id
            state.nextTaskTitle = nextTask?.title
            state.dailyProgressRatio = ratio
            state.streakCount = streak
        }
        WidgetCenter.shared.reloadAllTimelines()
        CrossProcessNotifier.postStateDidChange()
        return SnapshotStateMarker(version: updated.snapshotVersion, revisionId: updated.snapshotRevisionId)
    }

    private static func computeSnapshotTaskAndProgress(
        for userId: UUID,
        in context: ModelContext
    ) throws -> (nextTask: (id: UUID, title: String)?, ratio: Double, streak: Int) {
        let uid = userId
        let pending = try context.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.ownerUserId == uid && $0.isCompleted == false })
        ).sorted(by: SharedTaskQuickActionEngine.sortTasks)
        let progress = try SharedDailyProgressHelper.fetchOrCreateTodayProgress(for: uid, in: context)
        try context.save()
        return (
            pending.first.map { ($0.id, $0.title) },
            SharedDailyProgressHelper.completionRatio(for: progress),
            progress.streakCount
        )
    }

    private func validateText(_ raw: String, fieldName: String, allowEmpty: Bool) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !allowEmpty && trimmed.isEmpty {
            throw LockInDomainError.validationFailed("\(fieldName) không được để trống.")
        }
        guard trimmed.count <= AppConstants.maxFieldCharacterLength else {
            throw LockInDomainError.validationFailed("\(fieldName) không vượt quá \(AppConstants.maxFieldCharacterLength) ký tự.")
        }
        return trimmed
    }

    private static func toDTO(_ item: TaskItem) -> TaskItemDTO {
        TaskItemDTO(
            id: item.id,
            ownerUserId: item.ownerUserId,
            title: item.title,
            notes: item.notes,
            dueDate: item.dueDate,
            priority: item.priority,
            isCompleted: item.isCompleted,
            completedAt: item.completedAt,
            linkedDeckId: item.linkedDeckId
        )
    }
}
