// ShufflePoolConfigView.swift — Bảng cấu hình Shuffle Pool xoay vòng theme ngẫu nhiên và Pop-up nhắc việc.
// Thuộc Frontend/Features/ThemeGallery; chỉ dẫn đúng các iOS Shortcuts trigger thực tế hợp lệ.

import SwiftUI

public struct ShufflePoolConfigView: View {
    @Environment(\.lockInPalette) private var palette
    @Bindable var viewModel: ThemeGalleryViewModel

    public init(viewModel: ThemeGalleryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Xoay Theme Ngẫu nhiên (Shuffle Pool)", systemImage: "shuffle")
                .font(.headline)

            Toggle("Bật xoay ngẫu nhiên giữa các theme đã chọn", isOn: $viewModel.isShuffleEnabled)
                .onChange(of: viewModel.isShuffleEnabled) { _, _ in
                    Task { await viewModel.persistShuffleConfiguration() }
                }

            VStack(alignment: .leading, spacing: 8) {
                Text("Chọn ít nhất 2 theme vào Shuffle Pool:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))

                ForEach(viewModel.builtInThemes) { theme in
                    let included = viewModel.shufflePoolIds.contains(theme.id)
                    Button {
                        Task { await viewModel.togglePoolMembership(themeId: theme.id) }
                    } label: {
                        HStack {
                            Image(systemName: included ? "checkmark.square.fill" : "square")
                                .foregroundStyle(included ? Color(lockInHex: palette.accentHex) : Color(lockInHex: palette.textSecondaryHex))
                            Circle()
                                .fill(Color(lockInHex: theme.accentHex))
                                .frame(width: 10, height: 10)
                            Text(theme.displayName)
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Toggle("Tự động đổi theme mỗi khi mở app", isOn: $viewModel.rotateOnAppOpen)
                .onChange(of: viewModel.rotateOnAppOpen) { _, _ in
                    Task { await viewModel.persistShuffleConfiguration() }
                }

            Toggle("Cho phép xoay theme qua iOS Shortcuts", isOn: $viewModel.rotateOnShortcutTrigger)
                .onChange(of: viewModel.rotateOnShortcutTrigger) { _, _ in
                    Task { await viewModel.persistShuffleConfiguration() }
                }

            Text("iOS Shortcuts hỗ trợ các trigger thực tế: Theo giờ trong ngày, Chế độ Tập trung (Focus Mode), Khi mở/đóng app, hoặc Khi cắm/rút sạc (gọi intent \"Xoay Theme LockIn\").")
                .font(.caption)
                .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))

            Button {
                Task { await viewModel.rotateThemePreviewNow() }
            } label: {
                Label("Xoay sang theme kế tiếp ngay", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isShuffleEnabled)
        }
        .minimalCardStyle()
    }
}
