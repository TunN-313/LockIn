// StudyHubTabView.swift — Tab 1 ghép ProgressAndStreak, DecksAndCards và TasksAndSchedule.
// Thuộc Frontend/Tabs; đồng bộ trạng thái qua DependencyContainer và SyncEventBus.

import SwiftUI

public struct StudyHubTabView: View {
    @Environment(\.lockInPalette) private var palette

    @State private var progressVM: DailyProgressHeaderViewModel
    @State private var decksVM: DeckListAndEditorViewModel
    @State private var tasksVM: TaskListViewModel
    @State private var scheduleVM: SchedulePlannerViewModel

    public init(container: DependencyContainer) {
        _progressVM = State(initialValue: DailyProgressHeaderViewModel(
            studyModule: container.study,
            syncEventBus: container.syncEventBus
        ))
        _decksVM = State(initialValue: DeckListAndEditorViewModel(
            studyModule: container.study,
            lockScreenModule: container.lockScreen,
            syncEventBus: container.syncEventBus
        ))
        _tasksVM = State(initialValue: TaskListViewModel(
            studyModule: container.study,
            syncEventBus: container.syncEventBus
        ))
        _scheduleVM = State(initialValue: SchedulePlannerViewModel(
            schedulerModule: container.scheduler,
            studyModule: container.study,
            syncEventBus: container.syncEventBus
        ))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DailyProgressHeaderView(viewModel: progressVM)
                    DeckListView(viewModel: decksVM)
                    TaskListSectionView(viewModel: tasksVM)
                    SchedulePlannerView(viewModel: scheduleVM)
                }
                .padding()
            }
            .background(Color(lockInHex: palette.backgroundHex).ignoresSafeArea())
            .navigationTitle("Học & Tác vụ")
            .onAppear {
                progressVM.startObserving()
                decksVM.startObserving()
                tasksVM.startObserving()
                scheduleVM.startObserving()
            }
            .onDisappear {
                progressVM.stopObserving()
                decksVM.stopObserving()
                tasksVM.stopObserving()
                scheduleVM.stopObserving()
            }
            .refreshable {
                await progressVM.refresh()
                await decksVM.refreshDecks()
                await tasksVM.refresh()
                await scheduleVM.refresh()
            }
        }
    }
}
