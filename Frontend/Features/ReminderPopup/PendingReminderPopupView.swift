// PendingReminderPopupView.swift — Pop-up nhắc việc ôn thi tồn đọng khi mở app kèm nút hành động nhanh.
// Thuộc Frontend/Features/ReminderPopup; ủy quyền hành động Ôn ngay và Đưa lên Lock Screen qua closures.

import SwiftUI

public struct PendingReminderPopupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lockInPalette) private var palette

    @Bindable var viewModel: PendingReminderViewModel
    private let onReviewNow: () -> Void
    private let onPinSuggestedDeck: (UUID) async -> Void

    public init(
        viewModel: PendingReminderViewModel,
        onReviewNow: @escaping () -> Void,
        onPinSuggestedDeck: @escaping (UUID) async -> Void
    ) {
        self.viewModel = viewModel
        self.onReviewNow = onReviewNow
        self.onPinSuggestedDeck = onPinSuggestedDeck
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color(lockInHex: palette.accentHex))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Việc ôn tập đang chờ bạn")
                            .font(.title3.weight(.bold))
                        Text("Tổng hợp theo thời gian thực khi mở app")
                            .font(.caption)
                            .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                    }
                }

                if let summary = viewModel.summary {
                    VStack(alignment: .leading, spacing: 10) {
                        reminderRow(
                            icon: "exclamationmark.circle.fill",
                            color: summary.overdueTasksCount > 0 ? .red : .green,
                            text: "Tác vụ quá hạn: \(summary.overdueTasksCount)"
                        )
                        reminderRow(
                            icon: "calendar.badge.clock",
                            color: .orange,
                            text: "Tác vụ đến hạn hôm nay: \(summary.dueTodayTasksCount)"
                        )
                        reminderRow(
                            icon: "target",
                            color: Color(lockInHex: palette.accentHex),
                            text: "Mục tiêu ngày còn thiếu: \(summary.remainingDailyGoalCount) lượt"
                        )
                        if let deckTitle = summary.suggestedDeckTitle {
                            reminderRow(
                                icon: "book.closed.fill",
                                color: Color(lockInHex: palette.accentHex),
                                text: "Đề xuất ôn: \(deckTitle)"
                            )
                        }
                        if let nextTitle = viewModel.nextScheduleTitle, let nextDate = viewModel.nextScheduleDate {
                            reminderRow(
                                icon: "alarm",
                                color: Color(lockInHex: palette.textSecondaryHex),
                                text: "Lịch kế tiếp (\(nextTitle)): \(nextDate.formatted(date: .abbreviated, time: .shortened))"
                            )
                        }
                    }
                    .minimalCardStyle()

                    VStack(spacing: 10) {
                        if let deckId = summary.suggestedDeckId {
                            Button {
                                Task {
                                    await onPinSuggestedDeck(deckId)
                                    dismiss()
                                }
                            } label: {
                                Label("Đưa bộ đề gợi ý lên Lock Screen", systemImage: "pin.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button {
                            onReviewNow()
                            dismiss()
                        } label: {
                            Label("Ôn ngay trong Tab 1", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button("Nhắc lại sau") {
                            dismiss()
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                    }
                }

                Spacer()
            }
            .padding()
            .background(Color(lockInHex: palette.backgroundHex).ignoresSafeArea())
            .navigationTitle("Nhắc nhở ôn thi")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func reminderRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline)
        }
    }
}
