// ThemeGalleryViewModel.swift — Quản lý 6 theme tối giản, cấu hình Shuffle Pool và bật/tắt Pop-up nhắc việc.
// Thuộc Frontend/Features/ThemeGallery; chỉ phụ thuộc ThemeModuleProtocol, LockScreenModuleProtocol và SyncEventBus.

import Foundation
import Observation

@MainActor
@Observable
public final class ThemeGalleryViewModel {
    private let themeModule: ThemeModuleProtocol
    private let lockScreenModule: LockScreenModuleProtocol
    private let syncEventBus: SyncEventBus
    private var observerTask: Task<Void, Never>?

    public var builtInThemes: [ThemePalette] = []
    public var activeThemeId: String = ThemePalette.minimalPaper.id
    public var isShuffleEnabled: Bool = false
    public var shufflePoolIds: Set<String> = [ThemePalette.minimalPaper.id, ThemePalette.darkFocus.id]
    public var rotateOnAppOpen: Bool = false
    public var rotateOnShortcutTrigger: Bool = false
    public var showPopupOnOpen: Bool = true

    private var savedFontScale: LockScreenFontScale = .standard
    private var savedHideAnswerByDefault: Bool = true
    private var savedPrivacyModeEnabled: Bool = false

    public var statusMessage: String?
    public var errorMessage: String?

    public init(
        themeModule: ThemeModuleProtocol,
        lockScreenModule: LockScreenModuleProtocol,
        syncEventBus: SyncEventBus
    ) {
        self.themeModule = themeModule
        self.lockScreenModule = lockScreenModule
        self.syncEventBus = syncEventBus
        self.builtInThemes = themeModule.builtInThemes()
    }

    public func startObserving() {
        guard observerTask == nil else { return }
        let stream = syncEventBus.subscribe()
        observerTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self else { break }
                switch event {
                case .themeRotated, .externalStateRefreshed, .userSessionChanged:
                    await self.refresh()
                case .cardsChanged, .tasksChanged, .progressUpdated, .appLockPolicyChanged:
                    break
                }
            }
        }
    }

    public func stopObserving() {
        observerTask?.cancel()
        observerTask = nil
    }

    public func refresh() async {
        builtInThemes = themeModule.builtInThemes()
        do {
            let pref = try await themeModule.fetchPreference()
            applyPreferenceDTO(pref)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectTheme(_ themeId: String) async {
        errorMessage = nil
        do {
            let pref = try await themeModule.selectTheme(themeId: themeId)
            applyPreferenceDTO(pref)
            try? await lockScreenModule.syncSnapshotFromStore()
            statusMessage = "Đã áp dụng theme \(ThemePalette.palette(for: themeId).displayName)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func togglePoolMembership(themeId: String) async {
        if shufflePoolIds.contains(themeId) {
            if isShuffleEnabled && shufflePoolIds.count <= 2 {
                errorMessage = "Shuffle Pool cần ít nhất 2 theme khi đang bật xoay ngẫu nhiên."
                return
            }
            shufflePoolIds.remove(themeId)
        } else {
            shufflePoolIds.insert(themeId)
        }
        await persistShuffleConfiguration()
    }

    public func persistShuffleConfiguration() async {
        errorMessage = nil
        if isShuffleEnabled && shufflePoolIds.count < 2 {
            isShuffleEnabled = false
            errorMessage = "Vui lòng chọn tối thiểu 2 theme vào Shuffle Pool trước khi bật xoay vòng."
            return
        }
        do {
            let pref = try await themeModule.updateShuffleConfiguration(
                isEnabled: isShuffleEnabled,
                poolIds: Array(shufflePoolIds),
                rotateOnAppOpen: rotateOnAppOpen,
                rotateOnShortcutTrigger: rotateOnShortcutTrigger
            )
            applyPreferenceDTO(pref)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func persistShowPopupOnOpen(_ enabled: Bool) async {
        errorMessage = nil
        do {
            let pref = try await themeModule.updateLockScreenDisplayOptions(
                fontScale: savedFontScale,
                hideAnswerByDefault: savedHideAnswerByDefault,
                privacyModeEnabled: savedPrivacyModeEnabled,
                showPopupOnOpen: enabled
            )
            applyPreferenceDTO(pref)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func rotateThemePreviewNow() async {
        errorMessage = nil
        do {
            let palette = try await themeModule.rotateThemeIfNeeded(triggerOnAppOpen: false)
            activeThemeId = palette.id
            try? await lockScreenModule.syncSnapshotFromStore()
            statusMessage = "Đã xoay sang theme \(palette.displayName)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyPreferenceDTO(_ pref: ThemePreferenceDTO) {
        activeThemeId = pref.activeThemeId
        isShuffleEnabled = pref.isShuffleEnabled
        shufflePoolIds = Set(pref.shufflePoolIds)
        rotateOnAppOpen = pref.rotateOnAppOpen
        rotateOnShortcutTrigger = pref.rotateOnShortcutTrigger
        savedFontScale = pref.lockScreenFontScale
        savedHideAnswerByDefault = pref.hideAnswerByDefault
        savedPrivacyModeEnabled = pref.privacyModeEnabled
        showPopupOnOpen = pref.showPopupOnOpen
    }
}
