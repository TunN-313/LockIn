// PendingReminderViewModel.swift — Kiểm tra task quá hạn/hôm nay và mục tiêu ngày còn thiếu khi mở app.
// Thuộc Frontend/Features/ReminderPopup; chỉ phụ thuộc StudyModuleProtocol và SchedulerModuleProtocol.

import Foundation
import Observation

@MainActor
@Observable
public final class PendingReminderViewModel {
    private let studyModule: StudyModuleProtocol
    private let schedulerModule: SchedulerModuleProtocol

    public var summary: PendingReminderSummary?
    public var nextScheduleTitle: String?
    public var nextScheduleDate: Date?
    public var isPresentingPopup: Bool = false

    public init(studyModule: StudyModuleProtocol, schedulerModule: SchedulerModuleProtocol) {
        self.studyModule = studyModule
        self.schedulerModule = schedulerModule
    }

    public func checkPendingReminders(showPopupEnabled: Bool, forceShow: Bool = false) async {
        guard showPopupEnabled || forceShow else {
            isPresentingPopup = false
            return
        }
        do {
            async let fetchedSummary = studyModule.fetchPendingReminderSummary()
            async let fetchedSchedules = schedulerModule.fetchSchedules()

            let currentSummary = try await fetchedSummary
            let schedules = try await fetchedSchedules

            summary = currentSummary

            let now = Date()
            let upcoming = schedules
                .compactMap { schedule -> (String, Date)? in
                    guard let date = schedulerModule.nextScheduledDate(for: schedule, after: now) else { return nil }
                    return (schedule.title, date)
                }
                .sorted { $0.1 < $1.1 }
                .first
            nextScheduleTitle = upcoming?.0
            nextScheduleDate = upcoming?.1

            if forceShow || currentSummary.hasPendingItems {
                isPresentingPopup = true
            }
        } catch {
            isPresentingPopup = false
        }
    }
}
