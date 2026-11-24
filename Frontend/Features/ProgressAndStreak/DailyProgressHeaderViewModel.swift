// DailyProgressHeaderViewModel.swift — Theo dõi % mục tiêu trong ngày, chuỗi Streak và lắng nghe SyncEventBus.
// Thuộc Frontend/Features/ProgressAndStreak; chỉ dùng StudyModuleProtocol và Backend/Core/SyncEventBus.

import Foundation
import Observation

@MainActor
@Observable
public final class DailyProgressHeaderViewModel {
    private let studyModule: StudyModuleProtocol
    private let syncEventBus: SyncEventBus
    private var observerTask: Task<Void, Never>?

    public var progress: DailyProgressDTO = DailyProgressDTO(
        dateKey: "",
        cardsReviewed: 0,
        cardsMastered: 0,
        tasksCompleted: 0,
        dailyTargetCount: 20,
        streakCount: 0
    )
    public var isLoading: Bool = false
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
                case .cardsChanged, .tasksChanged, .progressUpdated, .externalStateRefreshed, .userSessionChanged:
                    await self.refresh()
                case .themeRotated, .appLockPolicyChanged:
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
        isLoading = true
        defer { isLoading = false }
        do {
            progress = try await studyModule.fetchTodayProgress()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
