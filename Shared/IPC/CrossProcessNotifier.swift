// CrossProcessNotifier.swift — Kênh thông báo liên tiến trình dùng Darwin Notification Center (CFNotificationCenter).
// Đồng bộ tức thì giữa LockInWidgetsExtension (khi bấm nút Lock Screen) và LockInApp đang mở ở foreground.

import CoreFoundation
import Foundation

public final class CrossProcessObserverToken: @unchecked Sendable {
    private let id: UUID
    private let onInvalidate: @Sendable (UUID) -> Void

    fileprivate init(id: UUID, onInvalidate: @escaping @Sendable (UUID) -> Void) {
        self.id = id
        self.onInvalidate = onInvalidate
    }

    public func invalidate() {
        onInvalidate(id)
    }

    deinit {
        onInvalidate(id)
    }
}

public enum CrossProcessNotifier {
    /// Gửi Darwin notification báo hiệu dữ liệu trong Shared App Group đã thay đổi.
    public static func postStateDidChange(
        notificationName: String = AppConstants.darwinStateDidChangeNotificationName
    ) {
        guard let center = CFNotificationCenterGetDarwinNotifyCenter() else { return }
        let cfName = CFNotificationName(notificationName as CFString)
        CFNotificationCenterPostNotification(center, cfName, nil, nil, true)
    }

    /// Đăng ký lắng nghe sự kiện Darwin notification và trả về token tự hủy khi giải phóng.
    public static func observeStateDidChange(
        notificationName: String = AppConstants.darwinStateDidChangeNotificationName,
        handler: @escaping @Sendable () -> Void
    ) -> CrossProcessObserverToken {
        DarwinObserverRegistry.shared.register(notificationName: notificationName, handler: handler)
    }
}

private final class DarwinObserverRegistry: @unchecked Sendable {
    static let shared = DarwinObserverRegistry()

    private let lock = NSLock()
    private var handlersByName: [String: [UUID: @Sendable () -> Void]] = [:]
    private var registeredCenterNames: Set<String> = []

    private init() {}

    func register(
        notificationName: String,
        handler: @escaping @Sendable () -> Void
    ) -> CrossProcessObserverToken {
        let tokenId = UUID()
        lock.lock()
        var group = handlersByName[notificationName] ?? [:]
        group[tokenId] = handler
        handlersByName[notificationName] = group

        if !registeredCenterNames.contains(notificationName),
           let center = CFNotificationCenterGetDarwinNotifyCenter() {
            registeredCenterNames.insert(notificationName)
            let observerPtr = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterAddObserver(
                center,
                observerPtr,
                darwinNotificationCallback,
                notificationName as CFString,
                nil,
                .deliverImmediately
            )
        }
        lock.unlock()

        return CrossProcessObserverToken(id: tokenId) { [weak self] id in
            self?.unregister(tokenId: id, notificationName: notificationName)
        }
    }

    private func unregister(tokenId: UUID, notificationName: String) {
        lock.lock()
        guard var group = handlersByName[notificationName] else {
            lock.unlock()
            return
        }
        group.removeValue(forKey: tokenId)
        if group.isEmpty {
            handlersByName.removeValue(forKey: notificationName)
            if registeredCenterNames.remove(notificationName) != nil,
               let center = CFNotificationCenterGetDarwinNotifyCenter() {
                let observerPtr = Unmanaged.passUnretained(self).toOpaque()
                CFNotificationCenterRemoveObserver(
                    center,
                    observerPtr,
                    CFNotificationName(notificationName as CFString),
                    nil
                )
            }
        } else {
            handlersByName[notificationName] = group
        }
        lock.unlock()
    }

    fileprivate func dispatch(notificationName: String) {
        lock.lock()
        let handlers = Array((handlersByName[notificationName] ?? [:]).values)
        lock.unlock()

        for handler in handlers {
            handler()
        }
    }
}

private let darwinNotificationCallback: CFNotificationCallback = { _, observer, name, _, _ in
    guard let observer, let rawName = name?.rawValue as String? else { return }
    let registry = Unmanaged<DarwinObserverRegistry>.fromOpaque(observer).takeUnretainedValue()
    registry.dispatch(notificationName: rawName)
}
