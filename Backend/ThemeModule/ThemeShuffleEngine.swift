// ThemeShuffleEngine.swift — Triển khai ThemeModuleProtocol bằng cách kết hợp ThemeCatalogService và SharedThemeRotationEngine.
// Không nhân đôi thuật toán xoay vòng theme; ủy quyền chọn theme tiếp theo cho Shared/ExtensionCore.

import Foundation

public final class ThemeShuffleEngine: ThemeModuleProtocol, @unchecked Sendable {
    private let catalogService: ThemeCatalogServiceProtocol
    private let sharedRotationEngine: SharedThemeRotationEngineProtocol

    public init(
        catalogService: ThemeCatalogServiceProtocol,
        sharedRotationEngine: SharedThemeRotationEngineProtocol
    ) {
        self.catalogService = catalogService
        self.sharedRotationEngine = sharedRotationEngine
    }

    public func builtInThemes() -> [ThemePalette] {
        catalogService.builtInThemes()
    }

    public func fetchPreference() async throws -> ThemePreferenceDTO {
        try await catalogService.fetchPreference()
    }

    public func selectTheme(themeId: String) async throws -> ThemePreferenceDTO {
        try await catalogService.selectTheme(themeId: themeId)
    }

    public func updateShuffleConfiguration(
        isEnabled: Bool,
        poolIds: [String],
        rotateOnAppOpen: Bool,
        rotateOnShortcutTrigger: Bool
    ) async throws -> ThemePreferenceDTO {
        try await catalogService.updateShuffleConfiguration(
            isEnabled: isEnabled,
            poolIds: poolIds,
            rotateOnAppOpen: rotateOnAppOpen,
            rotateOnShortcutTrigger: rotateOnShortcutTrigger
        )
    }

    public func updateLockScreenDisplayOptions(
        fontScale: LockScreenFontScale,
        hideAnswerByDefault: Bool,
        privacyModeEnabled: Bool,
        showPopupOnOpen: Bool
    ) async throws -> ThemePreferenceDTO {
        try await catalogService.updateLockScreenDisplayOptions(
            fontScale: fontScale,
            hideAnswerByDefault: hideAnswerByDefault,
            privacyModeEnabled: privacyModeEnabled,
            showPopupOnOpen: showPopupOnOpen
        )
    }

    public func rotateThemeIfNeeded(triggerOnAppOpen: Bool) async throws -> ThemePalette {
        let pref = try await catalogService.fetchPreference()
        guard pref.isShuffleEnabled else {
            return ThemePalette.palette(for: pref.activeThemeId)
        }
        if triggerOnAppOpen && !pref.rotateOnAppOpen {
            return ThemePalette.palette(for: pref.activeThemeId)
        }
        let nextId = sharedRotationEngine.selectNextThemeId(
            currentThemeId: pref.activeThemeId,
            shufflePoolIds: pref.shufflePoolIds
        )
        let updated = try await catalogService.selectTheme(themeId: nextId)
        return ThemePalette.palette(for: updated.activeThemeId)
    }
}
