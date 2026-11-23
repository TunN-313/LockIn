// AppGroupSnapshotStore.swift — Lưu snapshot nhẹ trong Shared App Group kèm khóa liên tiến trình POSIX flock và sessionEpoch.
// Ngăn mất cập nhật khi ghi đồng thời giữa app/extension, chặn ghi chồng sau đăng xuất và báo lỗi rõ nếu thiếu App Group.

import Darwin
import Foundation

public struct SnapshotStateMarker: Equatable, Sendable {
    public let version: Int
    public let revisionId: UUID

    public init(version: Int, revisionId: UUID) {
        self.version = version
        self.revisionId = revisionId
    }
}

public struct LockScreenSnapshot: Codable, Equatable, Sendable {
    public var snapshotVersion: Int
    public var snapshotRevisionId: UUID
    public var activeUserId: UUID?
    public var sessionEpoch: UUID?
    public var activeDeckId: UUID?
    public var activeDeckTitle: String
    public var currentCardId: UUID?
    public var currentCardQuestion: String
    public var currentCardAnswer: String
    public var currentCardIndex: Int
    public var totalCardsInDeck: Int
    public var masteredCountInDeck: Int
    public var isAnswerVisible: Bool
    public var activeThemeId: String
    public var isShuffleEnabled: Bool
    public var shufflePoolIds: [String]
    public var privacyModeEnabled: Bool
    public var fontScaleRaw: String
    public var dailyProgressRatio: Double
    public var streakCount: Int
    public var nextTaskId: UUID?
    public var nextTaskTitle: String?
    public var updatedAt: Date

    public init(
        snapshotVersion: Int = 0,
        snapshotRevisionId: UUID = UUID(),
        activeUserId: UUID? = nil,
        sessionEpoch: UUID? = nil,
        activeDeckId: UUID? = nil,
        activeDeckTitle: String = "",
        currentCardId: UUID? = nil,
        currentCardQuestion: String = "",
        currentCardAnswer: String = "",
        currentCardIndex: Int = 0,
        totalCardsInDeck: Int = 0,
        masteredCountInDeck: Int = 0,
        isAnswerVisible: Bool = false,
        activeThemeId: String = "minimal_paper",
        isShuffleEnabled: Bool = false,
        shufflePoolIds: [String] = ["minimal_paper", "dark_focus"],
        privacyModeEnabled: Bool = false,
        fontScaleRaw: String = LockScreenFontScale.standard.rawValue,
        dailyProgressRatio: Double = 0.0,
        streakCount: Int = 0,
        nextTaskId: UUID? = nil,
        nextTaskTitle: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.snapshotVersion = snapshotVersion
        self.snapshotRevisionId = snapshotRevisionId
        self.activeUserId = activeUserId
        self.sessionEpoch = sessionEpoch
        self.activeDeckId = activeDeckId
        self.activeDeckTitle = activeDeckTitle
        self.currentCardId = currentCardId
        self.currentCardQuestion = currentCardQuestion
        self.currentCardAnswer = currentCardAnswer
        self.currentCardIndex = currentCardIndex
        self.totalCardsInDeck = totalCardsInDeck
        self.masteredCountInDeck = masteredCountInDeck
        self.isAnswerVisible = isAnswerVisible
        self.activeThemeId = activeThemeId
        self.isShuffleEnabled = isShuffleEnabled
        self.shufflePoolIds = shufflePoolIds
        self.privacyModeEnabled = privacyModeEnabled
        self.fontScaleRaw = fontScaleRaw
        self.dailyProgressRatio = dailyProgressRatio
        self.streakCount = streakCount
        self.nextTaskId = nextTaskId
        self.nextTaskTitle = nextTaskTitle
        self.updatedAt = updatedAt
    }

    public static let empty = LockScreenSnapshot()
}

public protocol AppGroupSnapshotStoreProtocol: Sendable {
    func loadSnapshot() throws -> LockScreenSnapshot
    func currentStateMarker() throws -> SnapshotStateMarker
    @discardableResult func beginSession(userId: UUID) throws -> LockScreenSnapshot
    /// Thay thế toàn bộ snapshot với điều kiện khớp phiên và đúng revision vừa đọc (optimistic concurrency).
    /// Ưu tiên dùng `mutateSnapshotIfSessionMatches` cho cập nhật từng phần trên bản mới nhất bên trong flock.
    @discardableResult func saveSnapshotIfSessionMatches(
        _ snapshot: LockScreenSnapshot,
        expectedUserId: UUID,
        expectedSessionEpoch: UUID,
        expectedRevisionId: UUID
    ) throws -> LockScreenSnapshot
    @discardableResult func mutateSnapshotIfSessionMatches(
        expectedUserId: UUID,
        expectedSessionEpoch: UUID,
        expectedRevisionId: UUID?,
        _ transform: (inout LockScreenSnapshot) throws -> Void
    ) throws -> LockScreenSnapshot
    @discardableResult func clearAllForLogout() throws -> LockScreenSnapshot
}

public extension AppGroupSnapshotStoreProtocol {
    @discardableResult
    func mutateSnapshotIfSessionMatches(
        expectedUserId: UUID,
        expectedSessionEpoch: UUID,
        _ transform: (inout LockScreenSnapshot) throws -> Void
    ) throws -> LockScreenSnapshot {
        try mutateSnapshotIfSessionMatches(
            expectedUserId: expectedUserId,
            expectedSessionEpoch: expectedSessionEpoch,
            expectedRevisionId: nil,
            transform
        )
    }
}

public final class AppGroupSnapshotStore: AppGroupSnapshotStoreProtocol, @unchecked Sendable {
    private static let snapshotFileName = "LockInSnapshot.json"
    private static let lockFileName = "LockInSnapshot.lock"

    private let directoryURL: URL
    private let snapshotFileURL: URL
    private let lockFileURL: URL
    private let inProcessLock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init(directoryURL: URL) throws {
        self.directoryURL = directoryURL
        self.snapshotFileURL = directoryURL.appendingPathComponent(Self.snapshotFileName)
        self.lockFileURL = directoryURL.appendingPathComponent(Self.lockFileName)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw AppGroupStorageError.storageIOFailure(error.localizedDescription)
        }
    }

    /// Tạo snapshot store trên Shared App Group; ném lỗi ngay nếu App Group container không khả dụng.
    public static func makeShared(
        appGroupId: String = AppConstants.resolvedAppGroupIdentifier
    ) throws -> AppGroupSnapshotStore {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            throw AppGroupStorageError.appGroupContainerUnavailable(groupId: appGroupId)
        }
        return try AppGroupSnapshotStore(directoryURL: containerURL)
    }

    /// Tạo snapshot store trỏ tới thư mục riêng dành cho Unit Tests (giữ nguyên cơ chế khóa flock thật).
    public static func makeForTesting(directoryURL: URL) throws -> AppGroupSnapshotStore {
        try AppGroupSnapshotStore(directoryURL: directoryURL)
    }

    public func loadSnapshot() throws -> LockScreenSnapshot {
        try withExclusiveCrossProcessLock {
            try readSnapshotLocked()
        }
    }

    public func currentStateMarker() throws -> SnapshotStateMarker {
        try withExclusiveCrossProcessLock {
            let snapshot = try readSnapshotLocked()
            return SnapshotStateMarker(version: snapshot.snapshotVersion, revisionId: snapshot.snapshotRevisionId)
        }
    }

    @discardableResult
    public func beginSession(userId: UUID) throws -> LockScreenSnapshot {
        try withExclusiveCrossProcessLock {
            let current = try readSnapshotLocked()
            let next = LockScreenSnapshot(
                snapshotVersion: current.snapshotVersion + 1,
                snapshotRevisionId: UUID(),
                activeUserId: userId,
                sessionEpoch: UUID(),
                updatedAt: Date()
            )
            try writeSnapshotLocked(next)
            return next
        }
    }

    @discardableResult
    public func saveSnapshotIfSessionMatches(
        _ snapshot: LockScreenSnapshot,
        expectedUserId: UUID,
        expectedSessionEpoch: UUID,
        expectedRevisionId: UUID
    ) throws -> LockScreenSnapshot {
        try withExclusiveCrossProcessLock {
            let current = try readSnapshotLocked()
            guard current.activeUserId == expectedUserId,
                  let activeEpoch = current.sessionEpoch,
                  activeEpoch == expectedSessionEpoch else {
                throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
            }
            guard current.snapshotRevisionId == expectedRevisionId else {
                throw AppGroupStorageError.staleSnapshotRevision(
                    expected: expectedRevisionId,
                    actual: current.snapshotRevisionId
                )
            }
            var next = snapshot
            next.activeUserId = expectedUserId
            next.sessionEpoch = expectedSessionEpoch
            next.snapshotVersion = current.snapshotVersion + 1
            next.snapshotRevisionId = UUID()
            next.updatedAt = Date()
            try writeSnapshotLocked(next)
            return next
        }
    }

    @discardableResult
    public func mutateSnapshotIfSessionMatches(
        expectedUserId: UUID,
        expectedSessionEpoch: UUID,
        expectedRevisionId: UUID? = nil,
        _ transform: (inout LockScreenSnapshot) throws -> Void
    ) throws -> LockScreenSnapshot {
        try withExclusiveCrossProcessLock {
            var current = try readSnapshotLocked()
            guard current.activeUserId == expectedUserId,
                  let activeEpoch = current.sessionEpoch,
                  activeEpoch == expectedSessionEpoch else {
                throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
            }
            if let expectedRevisionId, current.snapshotRevisionId != expectedRevisionId {
                throw AppGroupStorageError.staleSnapshotRevision(
                    expected: expectedRevisionId,
                    actual: current.snapshotRevisionId
                )
            }
            try transform(&current)
            current.activeUserId = expectedUserId
            current.sessionEpoch = expectedSessionEpoch
            current.snapshotVersion += 1
            current.snapshotRevisionId = UUID()
            current.updatedAt = Date()
            try writeSnapshotLocked(current)
            return current
        }
    }

    /// Xóa toàn bộ dữ liệu hiển thị và hủy sessionEpoch trên Shared App Group khi người dùng đăng xuất.
    @discardableResult
    public func clearAllForLogout() throws -> LockScreenSnapshot {
        try withExclusiveCrossProcessLock {
            let current = try readSnapshotLocked()
            let cleared = LockScreenSnapshot(
                snapshotVersion: current.snapshotVersion + 1,
                snapshotRevisionId: UUID(),
                activeUserId: nil,
                sessionEpoch: nil,
                updatedAt: Date()
            )
            try writeSnapshotLocked(cleared)
            return cleared
        }
    }

    private func withExclusiveCrossProcessLock<T>(_ body: () throws -> T) throws -> T {
        inProcessLock.lock()
        defer { inProcessLock.unlock() }

        let fd = open(lockFileURL.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            throw AppGroupStorageError.lockFileOpenFailed(errnoCode: errno)
        }
        defer { close(fd) }

        while flock(fd, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            throw AppGroupStorageError.fileLockFailed(errnoCode: errno)
        }
        defer { _ = flock(fd, LOCK_UN) }

        return try body()
    }

    private func readSnapshotLocked() throws -> LockScreenSnapshot {
        guard FileManager.default.fileExists(atPath: snapshotFileURL.path) else {
            return .empty
        }
        do {
            let data = try Data(contentsOf: snapshotFileURL)
            return try decoder.decode(LockScreenSnapshot.self, from: data)
        } catch {
            throw AppGroupStorageError.storageIOFailure(error.localizedDescription)
        }
    }

    private func writeSnapshotLocked(_ snapshot: LockScreenSnapshot) throws {
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: snapshotFileURL, options: [.atomic])
        } catch {
            throw AppGroupStorageError.storageIOFailure(error.localizedDescription)
        }
    }
}
