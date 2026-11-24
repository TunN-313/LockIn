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
    @State private var isVerifyingForegroundLock: Bool = false
    @State private var isPrivacyCoverVisible: Bool = false
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
                        isVerifyingForegroundLock = false
                        isPrivacyCoverVisible = false
                        Task {
                            isAppLockRequiredCached = await container.security.isAppLockRequired()
                            await handleForegroundStudyTriggers()
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
                        isVerifyingForegroundLock = false
                        isPrivacyCoverVisible = false
                        Task {
                            isAppLockRequiredCached = await container.security.isAppLockRequired()
                            await handleForegroundStudyTriggers()
                            await reloadActivePalette()
                        }
                    }
                )
                .id(activeUser?.id)
            } else {
                ZStack {
                    MainTabContainerView(container: container)
                        .id(activeUser?.id)

                    if isPrivacyCoverVisible || isVerifyingForegroundLock {
                        privacyLockCoverView
                            .transition(.opacity)
                            .zIndex(10)
                    }
                }
            }
        }
        .lockInTheme(activePalette)
        .task {
            await bootstrapInitialSession()
            await observeSyncEvents()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .inactive:
                if activeUser != nil && isAppUnlocked && isAppLockRequiredCached {
                    isPrivacyCoverVisible = true
                }
            case .active:
                container.syncEventBus.refreshAll()
                let returningFromBackground = didEnterBackground
                if returningFromBackground && activeUser != nil {
                    isVerifyingForegroundLock = true
                    isPrivacyCoverVisible = true
                }
                Task {
                    defer {
                        isVerifyingForegroundLock = false
                        isPrivacyCoverVisible = false
                    }
                    let lockRequired = await container.security.isAppLockRequired()
                    isAppLockRequiredCached = lockRequired
                    if returningFromBackground {
                        didEnterBackground = false
                        if activeUser != nil && lockRequired {
                            isAppUnlocked = false
                        } else if activeUser != nil && isAppUnlocked {
                            await handleForegroundStudyTriggers()
                        }
                    } else if activeUser != nil && isAppUnlocked {
                        await handleForegroundStudyTriggers()
                    }
                    await reloadActivePalette()
                }
            case .background:
                didEnterBackground = true
                if activeUser != nil {
                    isPrivacyCoverVisible = true
                    if isAppLockRequiredCached {
                        isAppUnlocked = false
                    }
                }
            @unknown default:
                break
            }
        }
    }

    private var privacyLockCoverView: some View {
        ZStack {
            Color(lockInHex: activePalette.backgroundHex)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(lockInHex: activePalette.accentHex))
                Text("LockIn đang bảo vệ phiên học")
                    .font(.headline)
            }
        }
    }

    private func handleForegroundStudyTriggers() async {
        let dueResult = try? await container.scheduler.applyDueScheduleIfNeeded(at: Date())
        if dueResult?.didRotateTheme != true {
            _ = try? await container.theme.rotateThemeIfNeeded(triggerOnAppOpen: true)
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
                await handleForegroundStudyTriggers()
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
                    isVerifyingForegroundLock = false
                    isPrivacyCoverVisible = false
                    activePalette = .minimalPaper
                } else {
                    activeUser = await container.auth.currentActiveUser()
                    isAppUnlocked = true
                    didEnterBackground = false
                    isVerifyingForegroundLock = false
                    isPrivacyCoverVisible = false
                    isAppLockRequiredCached = await container.security.isAppLockRequired()
                    await reloadActivePalette()
                }
            case .appLockPolicyChanged(let isRequired):
                isAppLockRequiredCached = isRequired
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
