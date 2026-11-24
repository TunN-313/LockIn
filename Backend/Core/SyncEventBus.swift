// SyncEventBus.swift — Điều phối đồng bộ trạng thái giữa Backend modules, Frontend Tabs và LockInWidgetsExtension.
// Lắng nghe Darwin Notification (foreground) và gọi refreshAll() khi scenePhase == .active đối chiếu SnapshotStateMarker.

import Foundation
import Observation

public enum SyncDomainEvent: Equatable, Sendable {
    case cardsChanged(deckId: UUID?)
    case tasksChanged
    case progressUpdated
    case themeRotated(themeId: String)
    case userSessionChanged(activeUserId: UUID?)
    case appLockPolicyChanged(isRequired: Bool)
    case externalStateRefreshed(snapshotVersion: Int)
}

@MainActor
@Observable
public final class SyncEventBus {
    public private(set) var lastEvent: SyncDomainEvent?
    public private(set) var lastObservedMarker: SnapshotStateMarker

    public var lastObservedSnapshotVersion: Int {
        lastObservedMarker.version
    }

    private let snapshotStore: AppGroupSnapshotStoreProtocol
    private var continuations: [UUID: AsyncStream<SyncDomainEvent>.Continuation] = [:]
    private var ipcObserverToken: CrossProcessObserverToken?

    public init(
        snapshotStore: AppGroupSnapshotStoreProtocol,
        enableDarwinObserver: Bool = true
    ) {
        self.snapshotStore = snapshotStore
        self.lastObservedMarker = (try? snapshotStore.currentStateMarker())
            ?? SnapshotStateMarker(version: 0, revisionId: UUID())

        if enableDarwinObserver {
            self.ipcObserverToken = CrossProcessNotifier.observeStateDidChange { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleIncomingDarwinNotification()
                }
            }
        }
    }

    public func subscribe() -> AsyncStream<SyncDomainEvent> {
        let subscriberId = UUID()
        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            self.continuations[subscriberId] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: subscriberId)
                }
            }
        }
    }

    /// Phát sự kiện domain. Chỉ cập nhật `lastObservedMarker` khi caller truyền đúng `observedMarker`
    /// vừa xử lý; tuyệt đối không tự đọc snapshot mới nhất để tránh nuốt nhầm sự kiện từ Extension.
    public func publish(_ event: SyncDomainEvent, observedMarker: SnapshotStateMarker? = nil) {
        if let observedMarker {
            lastObservedMarker = observedMarker
        }
        lastEvent = event
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    /// Gọi trực tiếp `syncEventBus.refreshAll()` từ `LockInAppEntry` khi `scenePhase == .active`
    /// để đồng bộ toàn bộ thay đổi đã diễn ra trên Lock Screen lúc app ở nền hoặc bị đóng.
    public func refreshAll(force: Bool = false) {
        guard let latestMarker = try? snapshotStore.currentStateMarker() else { return }
        guard force || latestMarker != lastObservedMarker else { return }
        publish(.externalStateRefreshed(snapshotVersion: latestMarker.version), observedMarker: latestMarker)
    }

    private func handleIncomingDarwinNotification() {
        refreshAll(force: false)
    }
}
