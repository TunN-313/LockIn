// TaskListViewModel.swift — Điều phối CRUD TaskItem và đồng bộ hoàn thành tác vụ với StudyModule & SyncEventBus.
// Thuộc Frontend/Features/TasksAndSchedule; chỉ phụ thuộc StudyModuleProtocol và SyncEventBus.

import Foundation
import Observation

@MainActor
@Observable
public final class TaskListViewModel {
    private let studyModule: StudyModuleProtocol
    private let syncEventBus: SyncEventBus
    private var observerTask: Task<Void, Never>?

    public var tasks: [TaskItemDTO] = []
    public var availableDecks: [StudyDeckDTO] = []
    public var errorMessage: String?

    public init(studyModule: StudyModuleProtocol, syncEventBus: SyncEventBus) {
        self.studyModule = studyModule
        self.syncEventBus = syncEventBus
    }

    public func startObserving() {
        guard observerTask == nil else { return }
        let stream = syncEventBus.subscribe()
        observerTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self else { break }
                switch event {
                case .tasksChanged, .cardsChanged, .externalStateRefreshed, .userSessionChanged:
                    await self.refresh()
                case .progressUpdated, .themeRotated:
                    break
                }
            }
        }
    }

    public func stopObserving() {
        observerTask?.cancel()
        observerTask = nil
    }

    public func refresh() async {
        do {
            async let fetchedTasks = studyModule.fetchTasks()
            async let fetchedDecks = studyModule.fetchDecks()
            tasks = try await fetchedTasks
            availableDecks = try await fetchedDecks
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func saveTask(
        editingTaskId: UUID?,
        title: String,
        notes: String,
        dueDate: Date?,
        priority: TaskPriority,
        linkedDeckId: UUID?
    ) async -> Bool {
        errorMessage = nil
        do {
            if let editingTaskId {
                _ = try await studyModule.updateTask(
                    taskId: editingTaskId,
                    title: title,
                    notes: notes,
                    dueDate: dueDate,
                    priority: priority,
                    linkedDeckId: linkedDeckId
                )
            } else {
                _ = try await studyModule.createTask(
                    title: title,
                    notes: notes,
                    dueDate: dueDate,
                    priority: priority,
                    linkedDeckId: linkedDeckId
                )
            }
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func toggleCompletion(_ taskId: UUID) async {
        errorMessage = nil
        do {
            _ = try await studyModule.toggleTaskCompletion(taskId: taskId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteTask(_ taskId: UUID) async {
        errorMessage = nil
        do {
            try await studyModule.deleteTask(taskId: taskId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
