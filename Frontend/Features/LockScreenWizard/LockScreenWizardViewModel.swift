// LockScreenWizardViewModel.swift — Đọc trạng thái Bridge, chỉnh tùy chọn hiển thị Lock Screen và lưu ảnh Wallpaper vào Photos.
// Thuộc Frontend/Features/LockScreenWizard; chỉ gọi LockScreenModuleProtocol, ThemeModuleProtocol, SyncEventBus và Photos khi lưu ảnh.

import Foundation
import Observation
import Photos
import UIKit

@MainActor
@Observable
public final class LockScreenWizardViewModel {
    private let lockScreenModule: LockScreenModuleProtocol
    private let themeModule: ThemeModuleProtocol
    private let syncEventBus: SyncEventBus
    private var observerTask: Task<Void, Never>?

    public var status = LockScreenBridgeStatus(
        areLiveActivitiesEnabled: false,
        isNotificationAuthorized: false,
        isAppGroupAvailable: false,
        isLiveActivityActive: false,
        activeDeckId: nil,
        activeDeckTitle: nil
    )

    public var fontScale: LockScreenFontScale = .standard
    public var hideAnswerByDefault: Bool = true
    public var privacyModeEnabled: Bool = false
    private var savedShowPopupOnOpen: Bool = true

    public var wallpaperPayload: WallpaperRenderPayload?
    public var wallpaperPreviewImage: UIImage?
    public var statusMessage: String?
    public var errorMessage: String?

    public init(
        lockScreenModule: LockScreenModuleProtocol,
        themeModule: ThemeModuleProtocol,
        syncEventBus: SyncEventBus
    ) {
        self.lockScreenModule = lockScreenModule
        self.themeModule = themeModule
        self.syncEventBus = syncEventBus
    }

    public func startObserving() {
        guard observerTask == nil else { return }
        let stream = syncEventBus.subscribe()
        observerTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self else { break }
                switch event {
                case .cardsChanged, .themeRotated, .externalStateRefreshed, .userSessionChanged:
                    await self.refreshAll()
                case .tasksChanged, .progressUpdated:
                    break
                }
            }
        }
    }

    public func stopObserving() {
        observerTask?.cancel()
        observerTask = nil
    }

    public func refreshAll() async {
        status = await lockScreenModule.checkBridgeStatus()
        do {
            let pref = try await themeModule.fetchPreference()
            fontScale = pref.lockScreenFontScale
            hideAnswerByDefault = pref.hideAnswerByDefault
            privacyModeEnabled = pref.privacyModeEnabled
            savedShowPopupOnOpen = pref.showPopupOnOpen
        } catch {
            // Giữ cấu hình mặc định nếu chưa có hồ sơ hoạt động.
        }
    }

    public func saveDisplayOptions() async {
        errorMessage = nil
        do {
            let updated = try await themeModule.updateLockScreenDisplayOptions(
                fontScale: fontScale,
                hideAnswerByDefault: hideAnswerByDefault,
                privacyModeEnabled: privacyModeEnabled,
                showPopupOnOpen: savedShowPopupOnOpen
            )
            fontScale = updated.lockScreenFontScale
            hideAnswerByDefault = updated.hideAnswerByDefault
            privacyModeEnabled = updated.privacyModeEnabled
            try await lockScreenModule.syncSnapshotFromStore()
            status = await lockScreenModule.checkBridgeStatus()
            statusMessage = "Đã cập nhật hiển thị Lock Screen."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func restartLiveActivityIfDeckPinned() async {
        errorMessage = nil
        guard let deckId = status.activeDeckId else {
            errorMessage = "Hãy ghim một bộ đề từ Tab 1 (Học & Tác vụ) trước."
            return
        }
        do {
            try await lockScreenModule.startOrUpdateLiveActivity(forDeckId: deckId)
            status = await lockScreenModule.checkBridgeStatus()
            statusMessage = "Đã bật / làm mới phiên Live Activity."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func stopLiveActivity() async {
        await lockScreenModule.stopActiveLiveActivity()
        status = await lockScreenModule.checkBridgeStatus()
        statusMessage = "Đã dừng Live Activity trên Lock Screen."
    }

    public func generateWallpaper(maxLines: Int = 5) async {
        errorMessage = nil
        do {
            let payload = try await lockScreenModule.renderStudyWallpaperPNG(
                deckId: status.activeDeckId,
                maxLines: maxLines
            )
            wallpaperPayload = payload
            wallpaperPreviewImage = UIImage(data: payload.pngData)
            statusMessage = "Đã tạo ảnh tóm tắt bài ôn (\(payload.deckTitle))."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func saveWallpaperToPhotos() async {
        errorMessage = nil
        if wallpaperPayload == nil {
            await generateWallpaper()
        }
        guard let pngData = wallpaperPayload?.pngData else { return }

        let authStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authStatus == .authorized || authStatus == .limited else {
            errorMessage = "Ứng dụng chưa được cấp quyền Thêm vào Ảnh (Photos) trong Cài đặt."
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: pngData, options: nil)
            }
            statusMessage = "Đã lưu ảnh tóm tắt vào Thư viện ảnh. Bạn có thể đặt làm hình nền thủ công."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
