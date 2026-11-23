// StudyLockScreenWidgets.swift — Lock Screen Widgets (accessoryCircular và accessoryRectangular) dùng WidgetKit.
// Đọc dữ liệu từ AppGroupSnapshotStore và tương tác hoàn thành nhanh task hoặc chuyển thẻ qua AppIntent.

import AppIntents
import SwiftUI
import WidgetKit

struct StudySnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: LockScreenSnapshot
}

struct StudySnapshotTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StudySnapshotEntry {
        StudySnapshotEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (StudySnapshotEntry) -> Void) {
        let snapshot = loadSafeSnapshot()
        completion(StudySnapshotEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StudySnapshotEntry>) -> Void) {
        let snapshot = loadSafeSnapshot()
        let entry = StudySnapshotEntry(date: Date(), snapshot: snapshot)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadSafeSnapshot() -> LockScreenSnapshot {
        guard let store = try? AppGroupSnapshotStore.makeShared(),
              let snapshot = try? store.loadSnapshot() else {
            return .empty
        }
        return snapshot
    }
}

struct StudyProgressCircularWidget: Widget {
    let kind = "LockInStudyProgressCircularWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StudySnapshotTimelineProvider()) { entry in
            CircularProgressWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tiến độ ôn thi")
        .description("Theo dõi phần trăm hoàn thành mục tiêu ngày và chuỗi streak trên Lock Screen.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct StudyQuickActionRectangularWidget: Widget {
    let kind = "LockInStudyQuickActionRectangularWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StudySnapshotTimelineProvider()) { entry in
            RectangularQuickActionWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Ôn nhanh & Việc cần làm")
        .description("Xem nhanh tác vụ ưu tiên hoặc thẻ ôn kế tiếp và đánh dấu hoàn thành ngay trên Lock Screen.")
        .supportedFamilies([.accessoryRectangular])
    }
}

private struct CircularProgressWidgetView: View {
    let entry: StudySnapshotEntry

    var body: some View {
        let progress = min(1.0, max(0.0, entry.snapshot.dailyProgressRatio))
        let percent = Int((progress * 100).rounded())

        Gauge(value: progress) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(percent)%")
                .font(.caption2.monospacedDigit().bold())
        }
        .gaugeStyle(.accessoryCircular)
    }
}

private struct RectangularQuickActionWidgetView: View {
    let entry: StudySnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let taskTitle = entry.snapshot.nextTaskTitle, !taskTitle.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.caption2)
                    Text("Việc cần làm")
                        .font(.caption2.weight(.semibold))
                    Spacer()
                    Button(intent: CompleteNextTaskIntent()) {
                        Image(systemName: "checkmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                Text(taskTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .privacySensitive(entry.snapshot.privacyModeEnabled)
            } else if !entry.snapshot.currentCardQuestion.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "book.closed.fill")
                        .font(.caption2)
                    Text(entry.snapshot.activeDeckTitle.isEmpty ? "LockIn" : entry.snapshot.activeDeckTitle)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Button(intent: NextCardIntent()) {
                        Image(systemName: "arrow.right.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                Text(entry.snapshot.currentCardQuestion)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .privacySensitive(entry.snapshot.privacyModeEnabled)
            } else {
                Label("LockIn sẵn sàng", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                Text("Mở app để chọn bộ thẻ ôn thi hoặc tạo tác vụ.")
                    .font(.caption2)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
