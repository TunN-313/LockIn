// SchedulePlannerView.swift — Giao diện cài đặt lịch học real-time (giờ + các ngày T2–CN) trên Tab 1.
// Thuộc Frontend/Features/TasksAndSchedule; không import UserNotifications trực tiếp.

import SwiftUI

public struct SchedulePlannerView: View {
    @Environment(\.lockInPalette) private var palette
    @Bindable var viewModel: SchedulePlannerViewModel

    @State private var isPresentingEditor = false
    @State private var editingSchedule: StudyScheduleDTO?
    @State private var draftTitle = ""
    @State private var draftDeckId: UUID?
    @State private var draftTime = Date()
    @State private var draftWeekdays: Set<Int> = [2, 4, 6]
    @State private var draftEnabled = true
    @State private var draftAutoRotate = true

    private let weekdayOptions: [(weekday: Int, label: String)] = [
        (2, "T2"), (3, "T3"), (4, "T4"), (5, "T5"), (6, "T6"), (7, "T7"), (1, "CN")
    ]

    public init(viewModel: SchedulePlannerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Lịch học Real-time", systemImage: "alarm.fill")
                    .font(.headline)
                Spacer()
                Button {
                    openCreator()
                } label: {
                    Label("Đặt lịch", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(viewModel.availableDecks.isEmpty)
            }

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(Color(lockInHex: palette.accentHex))
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if viewModel.schedules.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chưa có khung giờ ôn tập cố định.")
                        .font(.footnote)
                        .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                    Button {
                        Task { await viewModel.requestNotificationPermission() }
                    } label: {
                        Label("Bật quyền thông báo nhắc giờ", systemImage: "bell.badge")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ForEach(viewModel.schedules) { schedule in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "%02d:%02d — %@", schedule.hour, schedule.minute, schedule.title))
                                .font(.subheadline.weight(.semibold))
                            Text(viewModel.deckTitle(for: schedule.deckId))
                                .font(.caption)
                                .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                            HStack(spacing: 8) {
                                Text(viewModel.nextOccurrenceText(for: schedule))
                                    .font(.caption2)
                                    .foregroundStyle(Color(lockInHex: palette.accentHex))
                                if schedule.autoRotateTheme {
                                    Label("Đổi theme", systemImage: "paintpalette")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                                }
                            }
                        }

                        Spacer()

                        Button {
                            Task { await viewModel.activateScheduledSession(schedule.id) }
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Bắt đầu phiên lịch")

                        Button {
                            openEditor(for: schedule)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            Task { await viewModel.deleteSchedule(schedule.id) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .background(
                        Color(lockInHex: palette.backgroundHex).opacity(0.65),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
            }
        }
        .minimalCardStyle()
        .task {
            viewModel.startObserving()
            await viewModel.refresh()
        }
        .sheet(isPresented: $isPresentingEditor) {
            scheduleEditorSheet
        }
    }

    private var scheduleEditorSheet: some View {
        NavigationStack {
            Form {
                Section("Khung giờ ôn tập") {
                    TextField("Tên lịch (vd: Ôn tối trước ngủ)", text: $draftTitle)
                    DatePicker("Giờ nhắc", selection: $draftTime, displayedComponents: .hourAndMinute)
                    Picker("Bộ đề ôn", selection: $draftDeckId) {
                        ForEach(viewModel.availableDecks) { deck in
                            Text(deck.title).tag(Optional(deck.id))
                        }
                    }
                }

                Section("Các ngày lặp lại") {
                    HStack(spacing: 6) {
                        ForEach(weekdayOptions, id: \.weekday) { option in
                            let selected = draftWeekdays.contains(option.weekday)
                            Button(option.label) {
                                if selected {
                                    draftWeekdays.remove(option.weekday)
                                } else {
                                    draftWeekdays.insert(option.weekday)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(selected ? Color(lockInHex: palette.accentHex) : .gray.opacity(0.35))
                            .font(.caption.weight(.semibold))
                        }
                    }
                }

                Section {
                    Toggle("Kích hoạt lịch", isOn: $draftEnabled)
                    Toggle("Đổi theme khi tới phiên học", isOn: $draftAutoRotate)
                    Button("Xin quyền thông báo ngay") {
                        Task { await viewModel.requestNotificationPermission() }
                    }
                } header: {
                    Text("Tùy chọn")
                } footer: {
                    Text("Thông báo nhắc đúng giờ hẹn; bộ đề ưu tiên và đổi theme được áp dụng khi mở LockIn trong khung giờ lịch hoặc nhấn Bắt đầu.")
                }
            }
            .navigationTitle(editingSchedule == nil ? "Thêm lịch học" : "Chỉnh sửa lịch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { isPresentingEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        guard let deckId = draftDeckId ?? viewModel.availableDecks.first?.id else { return }
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: draftTime)
                        Task {
                            let ok = await viewModel.saveSchedule(
                                scheduleId: editingSchedule?.id,
                                deckId: deckId,
                                title: draftTitle,
                                hour: comps.hour ?? 20,
                                minute: comps.minute ?? 0,
                                selectedWeekdays: draftWeekdays,
                                isEnabled: draftEnabled,
                                autoRotateTheme: draftAutoRotate
                            )
                            if ok { isPresentingEditor = false }
                        }
                    }
                }
            }
        }
    }

    private func openCreator() {
        editingSchedule = nil
        draftTitle = "Ôn tập LockIn"
        draftDeckId = viewModel.availableDecks.first?.id
        draftTime = Calendar.current.date(bySettingHour: 20, minute: 30, second: 0, of: Date()) ?? Date()
        draftWeekdays = [2, 3, 4, 5, 6]
        draftEnabled = true
        draftAutoRotate = true
        isPresentingEditor = true
    }

    private func openEditor(for schedule: StudyScheduleDTO) {
        editingSchedule = schedule
        draftTitle = schedule.title
        draftDeckId = schedule.deckId
        draftTime = Calendar.current.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: Date()) ?? Date()
        var days: Set<Int> = []
        for day in 1...7 where (schedule.weekdaysMask & (1 << (day - 1))) != 0 {
            days.insert(day)
        }
        draftWeekdays = days
        draftEnabled = schedule.isEnabled
        draftAutoRotate = schedule.autoRotateTheme
        isPresentingEditor = true
    }
}
