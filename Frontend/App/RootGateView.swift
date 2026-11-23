// RootGateView.swift — Điều phối luồng AuthLoginRegisterView → AppLockGateView → MainTabContainerView và SyncEventBus.
// Thuộc Frontend/App; làm mới trạng thái khi scenePhase == .active và lắng nghe thay đổi theme/session.

import SwiftUI

public struct RootGateView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let container: DependencyContainer

    @State private var activeUser: UserProfileDTO?
    @State private var isAppUnlocked: Bool = false
    @State private var isBootstrapping: Bool = true
    @State private var didEnterBackground: Bool = false
    @State private var isAppLockRequiredCached: Bool = false
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
                AuthGateHostView(
                    authModule: container.auth,
                    onAuthenticated: { profile in
                        activeUser = profile
                        isAppUnlocked = true
                        didEnterBackground = false
                        Task {
                            isAppLockRequiredCached = await container.security.isAppLockRequired()
                            await reloadActivePalette()
                        }
                    }
                )
            } else if !isAppUnlocked {
                AppLockGateHostView(
                    securityModule: container.security,
                    onUnlocked: {
                        isAppUnlocked = true
                        didEnterBackground = false
                        Task {
                            isAppLockRequiredCached = await container.security.isAppLockRequired()
                            _ = try? await container.theme.rotateThemeIfNeeded(triggerOnAppOpen: true)
                            await reloadActivePalette()
                        }
                    }
                )
                .id(activeUser?.id)
            } else {
                MainTabContainerView(container: container)
                    .id(activeUser?.id)
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
                    let lockRequired = await container.security.isAppLockRequired()
                    isAppLockRequiredCached = lockRequired
                    if didEnterBackground {
                        didEnterBackground = false
                        if activeUser != nil && lockRequired {
                            isAppUnlocked = false
                        } else if activeUser != nil && isAppUnlocked {
                            _ = try? await container.theme.rotateThemeIfNeeded(triggerOnAppOpen: true)
                        }
                    } else if activeUser != nil && isAppUnlocked {
                        _ = try? await container.theme.rotateThemeIfNeeded(triggerOnAppOpen: true)
                    }
                    await reloadActivePalette()
                }
            case .background:
                didEnterBackground = true
                if activeUser != nil && isAppLockRequiredCached {
                    isAppUnlocked = false
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
            isAppLockRequiredCached = lockRequired
            isAppUnlocked = !lockRequired
            if isAppUnlocked {
                _ = try? await container.theme.rotateThemeIfNeeded(triggerOnAppOpen: true)
            }
            await reloadActivePalette()
        } else {
            isAppLockRequiredCached = false
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
                    isAppLockRequiredCached = false
                    didEnterBackground = false
                    activePalette = .minimalPaper
                } else {
                    activeUser = await container.auth.currentActiveUser()
                    isAppUnlocked = true
                    didEnterBackground = false
                    isAppLockRequiredCached = await container.security.isAppLockRequired()
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

private struct AuthGateHostView: View {
    @State private var viewModel: AuthLoginRegisterViewModel

    init(
        authModule: AuthModuleProtocol,
        onAuthenticated: @escaping (UserProfileDTO) -> Void
    ) {
        _viewModel = State(initialValue: AuthLoginRegisterViewModel(
            authModule: authModule,
            onAuthenticated: onAuthenticated
        ))
    }

    var body: some View {
        AuthLoginRegisterView(viewModel: viewModel)
    }
}

private struct AppLockGateHostView: View {
    @State private var viewModel: AppLockGateViewModel

    init(
        securityModule: SecurityModuleProtocol,
        onUnlocked: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: AppLockGateViewModel(
            securityModule: securityModule,
            onUnlocked: onUnlocked
        ))
    }

    var body: some View {
        AppLockGateView(viewModel: viewModel)
    }
}
