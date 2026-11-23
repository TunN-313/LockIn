// SharedStoreContainer.swift — Khởi tạo SwiftData ModelContainer dùng chung trên Shared App Group.
// Luồng chạy thật bắt buộc có App Group container hợp lệ (ném lỗi rõ ràng nếu thiếu); hỗ trợ store in-memory riêng cho test.

import Foundation
import SwiftData

public enum AppGroupStorageError: Error, LocalizedError, Equatable, Sendable {
    case appGroupContainerUnavailable(groupId: String)
    case lockFileOpenFailed(errnoCode: Int32)
    case fileLockFailed(errnoCode: Int32)
    case sessionInvalidatedOrLoggedOut
    case staleSnapshotRevision(expected: UUID, actual: UUID)
    case storageIOFailure(String)

    public var errorDescription: String? {
        switch self {
        case .appGroupContainerUnavailable(let groupId):
            return "Không truy cập được Shared App Group (\(groupId)). Vui lòng kiểm tra entitlements và cấu hình ký."
        case .lockFileOpenFailed(let code):
            return "Không thể mở tệp khóa App Group (errno: \(code))."
        case .fileLockFailed(let code):
            return "Không thể khóa đồng bộ liên tiến trình App Group (errno: \(code))."
        case .sessionInvalidatedOrLoggedOut:
            return "Phiên làm việc đã đăng xuất hoặc thay đổi; thao tác ghi bị từ chối."
        case .staleSnapshotRevision:
            return "Trạng thái snapshot đã được tiến trình khác cập nhật; vui lòng đọc lại bản mới nhất trước khi ghi."
        case .storageIOFailure(let detail):
            return "Lỗi đọc/ghi Shared App Group: \(detail)"
        }
    }
}

public enum SharedStoreContainer {
    public static let schema = Schema([
        UserProfile.self,
        StudyDeck.self,
        StudyCard.self,
        TaskItem.self,
        StudySchedule.self,
        ThemePreference.self,
        DailyProgress.self
    ])

    /// Tạo ModelContainer trên Shared App Group; ném AppGroupStorageError nếu thiếu container thay vì rơi về thư mục riêng.
    public static func makeShared(appGroupId: String = AppConstants.resolvedAppGroupIdentifier) throws -> ModelContainer {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            throw AppGroupStorageError.appGroupContainerUnavailable(groupId: appGroupId)
        }
        let storeURL = containerURL.appendingPathComponent("LockInStore.sqlite")
        let configuration = ModelConfiguration(
            "LockInSharedStore",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Tạo ModelContainer tạm trên RAM dành riêng cho kiểm thử đơn vị (LockInTests).
    public static func makeInMemoryForTesting() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "LockInInMemoryStore",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
