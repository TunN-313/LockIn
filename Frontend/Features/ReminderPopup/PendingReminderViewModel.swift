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
    public var reminderFrequency: ReminderNotificationFrequency = .off
    public var isPresentingPopup: Bool = false
    public var isSchedulingSnooze: Bool = false
    public var statusMessage: String?
    public var errorMessage: String?

    public init(studyModule: StudyModuleProtocol, schedulerModule: SchedulerModuleProtocol) {
        self.studyModule = studyModule
        self.schedulerModule = schedulerModule
    }

    public func checkPendingReminders(showPopupEnabled: Bool, forceShow: Bool = false) async {
        guard showPopupEnabled || forceShow else {
            isPresentingPopup = false
            return
        }
        statusMessage = nil
        errorMessage = nil
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

    public func loadReminderFrequency() async {
        do {
            reminderFrequency = try await schedulerModule.fetchReminderFrequency()
        } catch {
            // Giữ cấu hình mặc định nếu chưa có hồ sơ hoạt động.
        }
    }

    public func updateReminderFrequency(_ frequency: ReminderNotificationFrequency) async {
        errorMessage = nil
        statusMessage = nil
        do {
            let updated = try await schedulerModule.updateReminderFrequency(frequency)
            reminderFrequency = updated
            statusMessage = updated == .off
                ? "Đã tắt thông báo nhắc việc định kỳ."
                : "Đã lên lịch nhắc: \(updated.displayName)."
        } catch {
            errorMessage = error.localizedDescription
            await loadReminderFrequency()
        }
    }

    public func snoozeReminder(afterMinutes: Int = 30) async -> Bool {
        errorMessage = nil
        statusMessage = nil
        isSchedulingSnooze = true
        defer { isSchedulingSnooze = false }
        do {
            let triggerDate = try await schedulerModule.scheduleSnoozeReminder(
                afterMinutes: afterMinutes,
                suggestedDeckTitle: summary?.suggestedDeckTitle
            )
            statusMessage = "Đã hẹn nhắc lại lúc \(triggerDate.formatted(date: .omitted, time: .shortened)) (sau \(afterMinutes) phút)."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
