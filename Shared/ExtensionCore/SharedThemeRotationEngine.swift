// SharedThemeRotationEngine.swift — Thuật toán xoay vòng theme trong Shuffle Pool dùng chung qua SharedAppGroup.
// Chỉ phụ thuộc Shared/**; cập nhật ThemePreference, AppGroupSnapshotStore, Live Activity, WidgetKit và CrossProcessNotifier.

import ActivityKit
import Foundation
import SwiftData
import WidgetKit

public struct ThemeRotationResult: Equatable, Sendable {
    public let previousThemeId: String
    public let nextTheme: ThemePalette
    public let snapshotVersion: Int

    public init(previousThemeId: String, nextTheme: ThemePalette, snapshotVersion: Int) {
        self.previousThemeId = previousThemeId
        self.nextTheme = nextTheme
        self.snapshotVersion = snapshotVersion
    }
}

public protocol SharedThemeRotationEngineProtocol: Sendable {
    func selectNextThemeId(currentThemeId: String, shufflePoolIds: [String]) -> String
    func rotateThemeInSharedStore() async throws -> ThemeRotationResult
}

public final class SharedThemeRotationEngine: SharedThemeRotationEngineProtocol, @unchecked Sendable {
    private let modelContainer: ModelContainer
    private let snapshotStore: AppGroupSnapshotStoreProtocol

    public init(modelContainer: ModelContainer, snapshotStore: AppGroupSnapshotStoreProtocol) {
        self.modelContainer = modelContainer
        self.snapshotStore = snapshotStore
    }

    public static func makeShared() throws -> SharedThemeRotationEngine {
        let container = try SharedStoreContainer.makeShared()
        let store = try AppGroupSnapshotStore.makeShared()
        return SharedThemeRotationEngine(modelContainer: container, snapshotStore: store)
    }

    public func selectNextThemeId(currentThemeId: String, shufflePoolIds: [String]) -> String {
        var generator = SystemRandomNumberGenerator()
        return selectNextThemeId(currentThemeId: currentThemeId, shufflePoolIds: shufflePoolIds, using: &generator)
    }

    public func selectNextThemeId<G: RandomNumberGenerator>(
        currentThemeId: String,
        shufflePoolIds: [String],
        using generator: inout G
    ) -> String {
        let validIds = Set(ThemePalette.allBuiltIn.map(\.id))
        var deduplicatedPool: [String] = []
        var seen: Set<String> = []

        for rawId in shufflePoolIds where validIds.contains(rawId) && !seen.contains(rawId) {
            seen.insert(rawId)
            deduplicatedPool.append(rawId)
        }

        if deduplicatedPool.isEmpty {
            return ThemePalette.minimalPaper.id
        }
        if deduplicatedPool.count == 1 {
            return deduplicatedPool[0]
        }

        let candidates = deduplicatedPool.filter { $0 != currentThemeId }
        if let chosen = candidates.randomElement(using: &generator) {
            return chosen
        }
        return deduplicatedPool[0]
    }

    public func rotateThemeInSharedStore() async throws -> ThemeRotationResult {
        let initialSnapshot = try snapshotStore.loadSnapshot()
        guard let userId = initialSnapshot.activeUserId,
              let sessionEpoch = initialSnapshot.sessionEpoch else {
            throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
        }

        let context = ModelContext(modelContainer)
        let uid = userId
        let prefDescriptor = FetchDescriptor<ThemePreference>(
            predicate: #Predicate<ThemePreference> { $0.ownerUserId == uid }
        )
        let preference = try context.fetch(prefDescriptor).first

        let currentThemeId = preference?.activeThemeId ?? initialSnapshot.activeThemeId
        let poolIds = preference?.shufflePoolIds ?? initialSnapshot.shufflePoolIds
        let nextThemeId = selectNextThemeId(currentThemeId: currentThemeId, shufflePoolIds: poolIds)
        let nextPalette = ThemePalette.palette(for: nextThemeId)

        if let preference {
            preference.activeThemeId = nextPalette.id
            try context.save()
        }

        let updatedSnapshot = try snapshotStore.mutateSnapshotIfSessionMatches(
            expectedUserId: userId,
            expectedSessionEpoch: sessionEpoch
        ) { state in
            state.activeThemeId = nextPalette.id
        }

        if updatedSnapshot.activeDeckId != nil {
            let contentState = SharedCardNavigationEngine.makeContentState(from: updatedSnapshot)
            await SharedCardNavigationEngine.updateRunningLiveActivities(
                deckId: updatedSnapshot.activeDeckId,
                state: contentState
            )
        }

        WidgetCenter.shared.reloadAllTimelines()
        CrossProcessNotifier.postStateDidChange()

        return ThemeRotationResult(
            previousThemeId: currentThemeId,
            nextTheme: nextPalette,
            snapshotVersion: updatedSnapshot.snapshotVersion
        )
    }
}
