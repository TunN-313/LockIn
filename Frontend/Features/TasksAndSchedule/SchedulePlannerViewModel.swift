// SchedulePlannerViewModel.swift — Điều phối lịch ôn tập real-time (StudySchedule) và thông báo nhắc giờ.
// Thuộc Frontend/Features/TasksAndSchedule; chỉ phụ thuộc SchedulerModuleProtocol, StudyModuleProtocol và SyncEventBus.

import Foundation
import Observation

@MainActor
@Observable
public final class SchedulePlannerViewModel {
    private let schedulerModule: SchedulerModuleProtocol
    private let studyModule: StudyModuleProtocol
    private let syncEventBus: SyncEventBus
    private var observerTask: Task<Void, Never>?

    public var schedules: [StudyScheduleDTO] = []
    public var availableDecks: [StudyDeckDTO] = []
    public var statusMessage: String?
    public var errorMessage: String?

    public init(
        schedulerModule: SchedulerModuleProtocol,
        studyModule: StudyModuleProtocol,
        syncEventBus: SyncEventBus
    ) {
        self.schedulerModule = schedulerModule
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
                case .cardsChanged, .externalStateRefreshed, .userSessionChanged:
                    await self.refresh()
                case .tasksChanged, .progressUpdated, .themeRotated, .appLockPolicyChanged:
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
            async let fetchedSchedules = schedulerModule.fetchSchedules()
            async let fetchedDecks = studyModule.fetchDecks()
            schedules = try await fetchedSchedules
            availableDecks = try await fetchedDecks
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func saveSchedule(
        scheduleId: UUID?,
        deckId: UUID,
        title: String,
        hour: Int,
        minute: Int,
        selectedWeekdays: Set<Int>,
        isEnabled: Bool,
        autoRotateTheme: Bool
    ) async -> Bool {
        errorMessage = nil
        let mask = StudySchedule.makeWeekdaysMask(selectedWeekdays)
        do {
            _ = try await schedulerModule.saveSchedule(
                scheduleId: scheduleId,
                deckId: deckId,
                title: title,
                hour: hour,
                minute: minute,
                weekdaysMask: mask,
                isEnabled: isEnabled,
                autoRotateTheme: autoRotateTheme
            )
            await refresh()
            statusMessage = "Đã lưu lịch ôn và đồng bộ thông báo."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func deleteSchedule(_ scheduleId: UUID) async {
        errorMessage = nil
        do {
            try await schedulerModule.deleteSchedule(scheduleId: scheduleId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func requestNotificationPermission() async {
        errorMessage = nil
        do {
            let granted = try await schedulerModule.requestNotificationPermission()
            statusMessage = granted
                ? "Đã bật quyền thông báo nhắc giờ ôn thi."
                : "Quyền thông báo bị từ chối trong Cài đặt iOS."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func activateScheduledSession(_ scheduleId: UUID) async {
        errorMessage = nil
        do {
            let result = try await schedulerModule.activateScheduledSession(scheduleId: scheduleId)
            if result.didRotateTheme {
                let themeName = ThemePalette.palette(for: result.activeThemeId).displayName
                statusMessage = "Đã ưu tiên bộ đề \(result.prioritizedDeckTitle) & đổi theme sang \(themeName)."
            } else {
                statusMessage = "Đã ưu tiên bộ đề \(result.prioritizedDeckTitle) lên màn hình khóa."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func nextOccurrenceText(for schedule: StudyScheduleDTO) -> String {
        guard let nextDate = schedulerModule.nextScheduledDate(for: schedule, after: Date()) else {
            return "Đang tắt"
        }
        return "Kế tiếp: \(nextDate.formatted(date: .abbreviated, time: .shortened))"
    }

    public func deckTitle(for deckId: UUID) -> String {
        availableDecks.first(where: { $0.id == deckId })?.title ?? "Bộ đề ôn thi"
    }
}
