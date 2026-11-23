// LockScreenWizardView.swift — Setup Wizard kết nối thiết bị, tùy chỉnh hiển thị Lock Screen và lưu ảnh Wallpaper.
// Thuộc Frontend/Features/LockScreenWizard; không gọi trực tiếp ActivityKit hay UserNotifications.

import SwiftUI

public struct LockScreenWizardView: View {
    @Environment(\.lockInPalette) private var palette
    @Bindable var viewModel: LockScreenWizardViewModel
    private let onRequestNotificationPermission: () async -> Void

    @State private var isShowingShortcutsGuide = false

    public init(
        viewModel: LockScreenWizardViewModel,
        onRequestNotificationPermission: @escaping () async -> Void
    ) {
        self.viewModel = viewModel
        self.onRequestNotificationPermission = onRequestNotificationPermission
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Kết nối Màn hình khóa", systemImage: "iphone.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await viewModel.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color(lockInHex: palette.accentHex))
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 8) {
                statusRow(
                    title: "Live Activities",
                    passed: viewModel.status.areLiveActivitiesEnabled,
                    detail: viewModel.status.areLiveActivitiesEnabled ? "Đã bật" : "Đang tắt trong Cài đặt iOS"
                )
                statusRow(
                    title: "Thông báo nhắc học",
                    passed: viewModel.status.isNotificationAuthorized,
                    detail: viewModel.status.isNotificationAuthorized ? "Đã cấp quyền" : "Chưa cấp quyền"
                )
                statusRow(
                    title: "Shared App Group",
                    passed: viewModel.status.isAppGroupAvailable,
                    detail: viewModel.status.isAppGroupAvailable ? "Đồng bộ sẵn sàng" : "Chưa cấu hình entitlement"
                )
                statusRow(
                    title: "Phiên Lock Screen",
                    passed: viewModel.status.isLiveActivityActive,
                    detail: viewModel.status.isLiveActivityActive
                        ? (viewModel.status.activeDeckTitle ?? "Đang chạy")
                        : "Chưa chạy (hết hạn sau 8–12h cần mở app)"
                )
            }

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.restartLiveActivityIfDeckPinned() }
                } label: {
                    Label("Bật / Làm mới phiên", systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await viewModel.stopLiveActivity() }
                } label: {
                    Label("Dừng", systemImage: "stop.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.status.isLiveActivityActive)
            }

            if !viewModel.status.isNotificationAuthorized {
                Button {
                    Task {
                        await onRequestNotificationPermission()
                        await viewModel.refreshAll()
                    }
                } label: {
                    Label("Xin quyền Thông báo", systemImage: "bell.badge")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Hiển thị trên Lock Screen")
                    .font(.subheadline.weight(.semibold))

                Picker("Cỡ chữ", selection: $viewModel.fontScale) {
                    Text("Nhỏ").tag(LockScreenFontScale.compact)
                    Text("Chuẩn").tag(LockScreenFontScale.standard)
                    Text("Lớn").tag(LockScreenFontScale.large)
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.fontScale) { _, _ in
                    Task { await viewModel.saveDisplayOptions() }
                }

                Toggle("Chỉ hiện câu hỏi (chạm để lật đáp án)", isOn: $viewModel.hideAnswerByDefault)
                    .onChange(of: viewModel.hideAnswerByDefault) { _, _ in
                        Task { await viewModel.saveDisplayOptions() }
                    }

                Toggle("Privacy Mode (ẩn nội dung khi chưa nhìn Face ID)", isOn: $viewModel.privacyModeEnabled)
                    .onChange(of: viewModel.privacyModeEnabled) { _, _ in
                        Task { await viewModel.saveDisplayOptions() }
                    }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Hình nền tóm tắt ôn thi (đặt thủ công)")
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    Button {
                        Task { await viewModel.generateWallpaper() }
                    } label: {
                        Label("Tạo ảnh", systemImage: "photo.badge.plus")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await viewModel.saveWallpaperToPhotos() }
                    } label: {
                        Label("Lưu vào Ảnh", systemImage: "square.and.arrow.down")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let preview = viewModel.wallpaperPreviewImage {
                    HStack(spacing: 12) {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        let swiftUIImage = Image(uiImage: preview)
                        ShareLink(
                            item: swiftUIImage,
                            preview: SharePreview("LockIn Study Wallpaper", image: swiftUIImage)
                        ) {
                            Label("Chia sẻ ảnh", systemImage: "square.and.arrow.up")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Button {
                isShowingShortcutsGuide = true
            } label: {
                Label("Hướng dẫn iOS Shortcuts Automation", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .minimalCardStyle()
        .task {
            viewModel.startObserving()
            await viewModel.refreshAll()
        }
        .onDisappear {
            viewModel.stopObserving()
        }
        .sheet(isPresented: $isShowingShortcutsGuide) {
            ShortcutsGuideSheetView()
        }
    }

    private func statusRow(title: String, passed: Bool, detail: String) -> some View {
        HStack {
            Image(systemName: passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(passed ? .green : .orange)
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
        }
    }
}
