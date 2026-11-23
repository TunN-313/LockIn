// MainTabContainerView.swift — Thanh TabView 3 tab chính (Portrait-only) và điều phối PendingReminderPopupView.
// Thuộc Frontend/Tabs; gắn kết StudyHubTabView, ThemesTabView và SettingsTabView với DependencyContainer.

import SwiftUI

public enum LockInMainTab: Hashable {
    case studyHub
    case themes
    case settings
}

public struct MainTabContainerView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let container: DependencyContainer

    @State private var selectedTab: LockInMainTab = .studyHub
    @State private var reminderVM: PendingReminderViewModel

    public init(container: DependencyContainer) {
        self.container = container
        _reminderVM = State(initialValue: PendingReminderViewModel(
            studyModule: container.study,
            schedulerModule: container.scheduler
        ))
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            StudyHubTabView(container: container)
                .tabItem {
                    Label("Học & Tác vụ", systemImage: "books.vertical.fill")
                }
                .tag(LockInMainTab.studyHub)

            ThemesTabView(container: container) {
                Task {
                    await reminderVM.checkPendingReminders(showPopupEnabled: true, forceShow: true)
                }
            }
            .tabItem {
                Label("Giao diện", systemImage: "paintpalette.fill")
            }
            .tag(LockInMainTab.themes)

            SettingsTabView(container: container)
                .tabItem {
                    Label("Cài đặt", systemImage: "gearshape.fill")
                }
                .tag(LockInMainTab.settings)
        }
        .task {
            let showPopup = (try? await container.theme.fetchPreference().showPopupOnOpen) ?? true
            await reminderVM.checkPendingReminders(showPopupEnabled: showPopup)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                let showPopup = (try? await container.theme.fetchPreference().showPopupOnOpen) ?? true
                await reminderVM.checkPendingReminders(showPopupEnabled: showPopup)
            }
        }
        .sheet(isPresented: $reminderVM.isPresentingPopup) {
            PendingReminderPopupView(
                viewModel: reminderVM,
                onReviewNow: {
                    selectedTab = .studyHub
                },
                onPinSuggestedDeck: { deckId in
                    try? await container.lockScreen.startOrUpdateLiveActivity(forDeckId: deckId)
                }
            )
        }
    }
}
