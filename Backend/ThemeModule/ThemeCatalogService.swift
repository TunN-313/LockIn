// ThemeCatalogService.swift — Quản lý danh mục 6 theme chuẩn và lưu ThemePreference cô lập theo ownerUserId.
// Thuộc ThemeModule; đồng bộ thay đổi theme/display options sang AppGroupSnapshotStore, Live Activity và SyncEventBus.

import Foundation
import SwiftData
import WidgetKit

public protocol ThemeCatalogServiceProtocol: Sendable {
    func builtInThemes() -> [ThemePalette]
    func fetchPreference() async throws -> ThemePreferenceDTO
    func selectTheme(themeId: String) async throws -> ThemePreferenceDTO
    func updateShuffleConfiguration(isEnabled: Bool, poolIds: [String], rotateOnAppOpen: Bool, rotateOnShortcutTrigger: Bool) async throws -> ThemePreferenceDTO
    func updateLockScreenDisplayOptions(fontScale: LockScreenFontScale, hideAnswerByDefault: Bool, privacyModeEnabled: Bool, showPopupOnOpen: Bool) async throws -> ThemePreferenceDTO
}

public final class ThemeCatalogService: ThemeCatalogServiceProtocol, @unchecked Sendable {
    private let studyStore: SwiftDataStudyStore
    private let isolationGuard: UserDataIsolationGuardProtocol
    private let snapshotStore: AppGroupSnapshotStoreProtocol
    private let syncEventBus: SyncEventBus

    public init(
        studyStore: SwiftDataStudyStore,
        isolationGuard: UserDataIsolationGuardProtocol,
        snapshotStore: AppGroupSnapshotStoreProtocol,
        syncEventBus: SyncEventBus
    ) {
        self.studyStore = studyStore
        self.isolationGuard = isolationGuard
        self.snapshotStore = snapshotStore
        self.syncEventBus = syncEventBus
    }

    public func builtInThemes() -> [ThemePalette] {
        ThemePalette.allBuiltIn
    }

    public func fetchPreference() async throws -> ThemePreferenceDTO {
        let userId = try isolationGuard.requireActiveUserId()
        return try await studyStore.perform { context in
            let pref = try Self.fetchOrCreatePreference(for: userId, in: context)
            try context.save()
            return Self.toDTO(pref)
        }
    }

    private struct ThemePreferenceCommitResult: Sendable {
        let dto: ThemePreferenceDTO
        let snapshot: LockScreenSnapshot
    }

    public func selectTheme(themeId: String) async throws -> ThemePreferenceDTO {
        let validPalette = ThemePalette.palette(for: themeId)
        return try await mutatePreference(
            { pref in
                pref.activeThemeId = validPalette.id
            },
            syncSnapshot: { pref, state in
                state.activeThemeId = pref.activeThemeId
            }
        )
    }

    public func updateShuffleConfiguration(
        isEnabled: Bool,
        poolIds: [String],
        rotateOnAppOpen: Bool,
        rotateOnShortcutTrigger: Bool
    ) async throws -> ThemePreferenceDTO {
        let validIdSet = Set(ThemePalette.allBuiltIn.map(\.id))
        var cleanPool: [String] = []
        var seen: Set<String> = []
        for id in poolIds where validIdSet.contains(id) && !seen.contains(id) {
            seen.insert(id)
            cleanPool.append(id)
        }
        if isEnabled && cleanPool.count < 2 {
            throw LockInDomainError.validationFailed("Chế độ xoay ngẫu nhiên cần chọn ít nhất 2 theme trong Shuffle Pool.")
        }
        if cleanPool.isEmpty {
            cleanPool = [ThemePalette.minimalPaper.id, ThemePalette.darkFocus.id]
        }

        let finalPool = cleanPool
        return try await mutatePreference(
            { pref in
                pref.isShuffleEnabled = isEnabled
                pref.shufflePoolIds = finalPool
                pref.rotateOnAppOpen = rotateOnAppOpen
                pref.rotateOnShortcutTrigger = rotateOnShortcutTrigger
            },
            syncSnapshot: { pref, state in
                state.isShuffleEnabled = pref.isShuffleEnabled
                state.shufflePoolIds = pref.shufflePoolIds
            }
        )
    }

    public func updateLockScreenDisplayOptions(
        fontScale: LockScreenFontScale,
        hideAnswerByDefault: Bool,
        privacyModeEnabled: Bool,
        showPopupOnOpen: Bool
    ) async throws -> ThemePreferenceDTO {
        return try await mutatePreference(
            { pref in
                pref.fontScale = fontScale
                pref.hideAnswerByDefault = hideAnswerByDefault
                pref.privacyModeEnabled = privacyModeEnabled
                pref.showPopupOnOpen = showPopupOnOpen
            },
            syncSnapshot: { pref, state in
                state.privacyModeEnabled = pref.privacyModeEnabled
                state.fontScaleRaw = pref.fontScale.rawValue
            }
        )
    }

    private func mutatePreference(
        _ update: @Sendable (ThemePreference) -> Void,
        syncSnapshot: @Sendable (ThemePreference, inout LockScreenSnapshot) -> Void
    ) async throws -> ThemePreferenceDTO {
        let session = try isolationGuard.requireActiveSession()
        let guardService = self.isolationGuard
        let store = self.snapshotStore

        let commitResult: ThemePreferenceCommitResult = try await studyStore.perform { context -> ThemePreferenceCommitResult in
            guard guardService.currentUserId() == session.userId,
                  guardService.currentSessionEpoch() == session.sessionEpoch else {
                throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
            }

            var committedDTO: ThemePreferenceDTO?
            let updatedSnapshot = try store.mutateSnapshotIfSessionMatches(
                expectedUserId: session.userId,
                expectedSessionEpoch: session.sessionEpoch
            ) { state in
                guard guardService.currentUserId() == session.userId,
                      guardService.currentSessionEpoch() == session.sessionEpoch else {
                    throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
                }
                let pref = try Self.fetchOrCreatePreference(for: session.userId, in: context)
                update(pref)
                try context.save()
                syncSnapshot(pref, &state)
                committedDTO = Self.toDTO(pref)
            }

            guard let dto = committedDTO else {
                throw AppGroupStorageError.storageIOFailure("Không lưu được ThemePreference.")
            }
            return ThemePreferenceCommitResult(dto: dto, snapshot: updatedSnapshot)
        }

        let dto = commitResult.dto
        let updatedSnapshot = commitResult.snapshot
        let liveSnapshotForActivity = (try? store.loadSnapshot()).flatMap {
            ($0.activeUserId == session.userId && $0.sessionEpoch == session.sessionEpoch) ? $0 : nil
        } ?? updatedSnapshot

        if liveSnapshotForActivity.activeDeckId != nil {
            let contentState = SharedCardNavigationEngine.makeContentState(from: liveSnapshotForActivity)
            await SharedCardNavigationEngine.updateRunningLiveActivities(
                deckId: liveSnapshotForActivity.activeDeckId,
                state: contentState
            )
        }

        WidgetCenter.shared.reloadAllTimelines()
        CrossProcessNotifier.postStateDidChange()

        await MainActor.run {
            let liveSnapshot = try? store.loadSnapshot()
            guard let liveSnapshot,
                  liveSnapshot.activeUserId == session.userId,
                  liveSnapshot.sessionEpoch == session.sessionEpoch else {
                return
            }

            if liveSnapshot.snapshotRevisionId == updatedSnapshot.snapshotRevisionId {
                let marker = SnapshotStateMarker(
                    version: updatedSnapshot.snapshotVersion,
                    revisionId: updatedSnapshot.snapshotRevisionId
                )
                syncEventBus.publish(.themeRotated(themeId: updatedSnapshot.activeThemeId), observedMarker: marker)
            } else {
                let liveMarker = SnapshotStateMarker(
                    version: liveSnapshot.snapshotVersion,
                    revisionId: liveSnapshot.snapshotRevisionId
                )
                syncEventBus.publish(.themeRotated(themeId: liveSnapshot.activeThemeId), observedMarker: liveMarker)
                syncEventBus.publish(.externalStateRefreshed(snapshotVersion: liveSnapshot.snapshotVersion), observedMarker: liveMarker)
            }
        }
        return dto
    }

    public static func fetchOrCreatePreference(for userId: UUID, in context: ModelContext) throws -> ThemePreference {
        let uid = userId
        let descriptor = FetchDescriptor<ThemePreference>(
            predicate: #Predicate<ThemePreference> { $0.ownerUserId == uid }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let created = ThemePreference(ownerUserId: uid)
        context.insert(created)
        return created
    }

    private static func toDTO(_ pref: ThemePreference) -> ThemePreferenceDTO {
        ThemePreferenceDTO(
            id: pref.id,
            ownerUserId: pref.ownerUserId,
            activeThemeId: pref.activeThemeId,
            isShuffleEnabled: pref.isShuffleEnabled,
            shufflePoolIds: pref.shufflePoolIds,
            rotateOnAppOpen: pref.rotateOnAppOpen,
            rotateOnShortcutTrigger: pref.rotateOnShortcutTrigger,
            lockScreenFontScale: pref.fontScale,
            hideAnswerByDefault: pref.hideAnswerByDefault,
            privacyModeEnabled: pref.privacyModeEnabled,
            showPopupOnOpen: pref.showPopupOnOpen
        )
    }
}
