// DailyProgressHeaderView.swift — Header hiển thị Progress Bar mục tiêu ngày và huy hiệu Streak trên Tab 1.
// Thuộc Frontend/Features/ProgressAndStreak; sử dụng ProgressBarComponent và MinimalCardStyle.

import SwiftUI

public struct DailyProgressHeaderView: View {
    @Environment(\.lockInPalette) private var palette
    @Bindable var viewModel: DailyProgressHeaderViewModel

    public init(viewModel: DailyProgressHeaderViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let completedUnits = viewModel.progress.cardsReviewed + viewModel.progress.tasksCompleted
        let targetUnits = max(1, viewModel.progress.dailyTargetCount)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tiến độ hôm nay")
                        .font(.headline)
                    Text("\(completedUnits)/\(targetUnits) lượt thẻ & việc đã hoàn thành")
                        .font(.caption)
                        .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(viewModel.progress.streakCount) ngày")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Color(lockInHex: palette.accentHex).opacity(0.14),
                    in: Capsule(style: .continuous)
                )
            }

            ProgressBarComponent(
                title: "Mục tiêu ngày",
                progress: viewModel.progress.completionRatio,
                height: 12
            )

            HStack(spacing: 16) {
                Label("\(viewModel.progress.cardsReviewed) lượt ôn", systemImage: "rectangle.stack")
                Label("\(viewModel.progress.cardsMastered) đã thuộc", systemImage: "checkmark.seal.fill")
                Label("\(viewModel.progress.tasksCompleted) việc xong", systemImage: "checklist")
            }
            .font(.caption)
            .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .minimalCardStyle()
        .task {
            viewModel.startObserving()
            await viewModel.refresh()
        }
    }
}
