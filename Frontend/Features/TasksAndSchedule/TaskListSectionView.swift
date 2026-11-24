// TaskListSectionView.swift — Giao diện danh sách tác vụ ôn tập ưu tiên trên Tab 1 (StudyHubTabView).
// Thuộc Frontend/Features/TasksAndSchedule; chỉ gọi TaskListViewModel và Frontend/DesignSystem.

import SwiftUI

public struct TaskListSectionView: View {
    @Environment(\.lockInPalette) private var palette
    @Bindable var viewModel: TaskListViewModel

    @State private var isPresentingEditor = false
    @State private var editingTask: TaskItemDTO?
    @State private var draftTitle = ""
    @State private var draftNotes = ""
    @State private var draftHasDueDate = false
    @State private var draftDueDate = Date()
    @State private var draftPriority: TaskPriority = .medium
    @State private var draftLinkedDeckId: UUID?

    public init(viewModel: TaskListViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Việc cần làm", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Button {
                    openCreator()
                } label: {
                    Label("Thêm việc", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if viewModel.tasks.isEmpty {
                Text("Chưa có tác vụ nào. Tạo task để ghim việc ưu tiên lên Lock Screen Widget.")
                    .font(.footnote)
                    .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.tasks) { task in
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            Task { await viewModel.toggleCompletion(task.id) }
                        } label: {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(task.isCompleted ? .green : Color(lockInHex: palette.accentHex))
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(task.title)
                                    .font(.subheadline.weight(.semibold))
                                    .strikethrough(task.isCompleted)
                                    .foregroundStyle(
                                        task.isCompleted
                                            ? Color(lockInHex: palette.textSecondaryHex)
                                            : Color(lockInHex: palette.textPrimaryHex)
                                    )
                                Spacer()
                                priorityBadge(task.priority)
                            }

                            if !task.notes.isEmpty {
                                Text(task.notes)
                                    .font(.caption)
                                    .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                            }

                            if let dueDate = task.dueDate {
                                Label(dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                                    .font(.caption2)
                                    .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                            }
                        }

                        Menu {
                            Button("Chỉnh sửa", systemImage: "pencil") {
                                openEditor(for: task)
                            }
                            Button("Xóa", systemImage: "trash", role: .destructive) {
                                Task { await viewModel.deleteTask(task.id) }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                        }
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
            taskEditorSheet
        }
    }

    private func priorityBadge(_ priority: TaskPriority) -> some View {
        let title: String
        let color: Color
        switch priority {
        case .high:
            title = "Cao"
            color = .red
        case .medium:
            title = "Vừa"
            color = .orange
        case .low:
            title = "Thấp"
            color = .blue
        }
        return Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var taskEditorSheet: some View {
        NavigationStack {
            Form {
                Section("Tác vụ") {
                    TextField("Tiêu đề (vd: Ôn xong 20 câu Chương 3)", text: $draftTitle)
                    TextField("Ghi chú", text: $draftNotes, axis: .vertical)
                    Picker("Mức ưu tiên", selection: $draftPriority) {
                        Text("Thấp").tag(TaskPriority.low)
                        Text("Trung bình").tag(TaskPriority.medium)
                        Text("Cao").tag(TaskPriority.high)
                    }
                }

                Section("Hạn chót & Bộ đề liên kết") {
                    Toggle("Có hạn hoàn thành", isOn: $draftHasDueDate)
                    if draftHasDueDate {
                        DatePicker("Thời hạn", selection: $draftDueDate)
                    }
                    Picker("Gắn bộ đề", selection: $draftLinkedDeckId) {
                        Text("Không gắn").tag(UUID?.none)
                        ForEach(viewModel.availableDecks) { deck in
                            Text(deck.title).tag(Optional(deck.id))
                        }
                    }
                }
            }
            .navigationTitle(editingTask == nil ? "Thêm tác vụ" : "Sửa tác vụ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { isPresentingEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        Task {
                            let ok = await viewModel.saveTask(
                                editingTaskId: editingTask?.id,
                                title: draftTitle,
                                notes: draftNotes,
                                dueDate: draftHasDueDate ? draftDueDate : nil,
                                priority: draftPriority,
                                linkedDeckId: draftLinkedDeckId
                            )
                            if ok { isPresentingEditor = false }
                        }
                    }
                }
            }
        }
    }

    private func openCreator() {
        editingTask = nil
        draftTitle = ""
        draftNotes = ""
        draftHasDueDate = false
        draftDueDate = Calendar.current.date(byAdding: .hour, value: 4, to: Date()) ?? Date()
        draftPriority = .medium
        draftLinkedDeckId = nil
        isPresentingEditor = true
    }

    private func openEditor(for task: TaskItemDTO) {
        editingTask = task
        draftTitle = task.title
        draftNotes = task.notes
        draftHasDueDate = task.dueDate != nil
        draftDueDate = task.dueDate ?? Date()
        draftPriority = task.priority
        draftLinkedDeckId = task.linkedDeckId
        isPresentingEditor = true
    }
}
