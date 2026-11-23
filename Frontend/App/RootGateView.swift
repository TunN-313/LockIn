// RootGateView.swift — Điều phối luồng AuthLoginRegisterView → AppLockGateView → MainTabContainerView và SyncEventBus.
// Thuộc Frontend/App; làm mới trạng thái khi scenePhase == .active và lắng nghe thay đổi theme/session.

import SwiftUI

public struct RootGateView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let container: DependencyContainer

    @State private var activeUser: UserProfileDTO?
    @State private var isAppUnlocked: Bool = false
    @State private var isBootstrapping: Bool = true
    @State private var activePalette: ThemePalette = .minimalPaper

    public init(container: DependencyContainer) {
        self.container = container
    }

    public var body: some View {
        Group {
            if isBootstrapping {
                ZStack {
                    Color(lockInHex: activePalette.backgroundHex).ignoresSafeArea()
                    ProgressView("Đang khởi tạo LockIn...")
                }
            } else if activeUser == nil {
                AuthLoginRegisterView(
                    viewModel: AuthLoginRegisterViewModel(
                        authModule: container.auth,
                        onAuthenticated: { profile in
                            activeUser = profile
                            isAppUnlocked = true
                            Task { await reloadActivePalette() }
                        }
                    )
                )
            } else if !isAppUnlocked {
                AppLockGateView(
                    viewModel: AppLockGateViewModel(
                        securityModule: container.security,
                        onUnlocked: {
                            isAppUnlocked = true
                            Task {
                                _ = try? await container.theme.rotateThemeIfNeeded(triggerOnAppOpen: true)
                                await reloadActivePalette()
                            }
                        }
                    )
                )
            } else {
                MainTabContainerView(container: container)
            }
        }
        .lockInTheme(activePalette)
        .task {
            await bootstrapInitialSession()
            await observeSyncEvents()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                container.syncEventBus.refreshAll()
                Task {
                    if activeUser != nil && isAppUnlocked {
                        _ = try? await container.theme.rotateThemeIfNeeded(triggerOnAppOpen: true)
                    }
                    await reloadActivePalette()
                }
            case .background:
                Task {
                    if activeUser != nil, await container.security.isAppLockRequired() {
                        isAppUnlocked = false
                    }
                }
            default:
                break
            }
        }
    }

    private func bootstrapInitialSession() async {
        defer { isBootstrapping = false }
        let user = await container.auth.currentActiveUser()
        activeUser = user
        if user != nil {
            let lockRequired = await container.security.isAppLockRequired()
            isAppUnlocked = !lockRequired
            if isAppUnlocked {
                _ = try? await container.theme.rotateThemeIfNeeded(triggerOnAppOpen: true)
            }
            await reloadActivePalette()
        } else {
            isAppUnlocked = false
            activePalette = .minimalPaper
        }
    }

    private func reloadActivePalette() async {
        guard activeUser != nil else {
            activePalette = .minimalPaper
            return
        }
        if let pref = try? await container.theme.fetchPreference() {
            activePalette = ThemePalette.palette(for: pref.activeThemeId)
        }
    }

    private func observeSyncEvents() async {
        let stream = container.syncEventBus.subscribe()
        for await event in stream {
            switch event {
            case .userSessionChanged(let newUserId):
                if newUserId == nil {
                    activeUser = nil
                    isAppUnlocked = false
                    activePalette = .minimalPaper
                } else {
                    activeUser = await container.auth.currentActiveUser()
                    isAppUnlocked = true
                    await reloadActivePalette()
                }
            case .themeRotated(let themeId):
                activePalette = ThemePalette.palette(for: themeId)
            case .externalStateRefreshed:
                await reloadActivePalette()
            case .cardsChanged, .tasksChanged, .progressUpdated:
                break
            }
        }
    }
}
