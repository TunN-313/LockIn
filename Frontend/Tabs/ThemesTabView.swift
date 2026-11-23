// ThemesTabView.swift — Tab 2 ghép ThemeGallery, ShufflePoolConfig và cài đặt Pop-up nhắc việc.
// Thuộc Frontend/Tabs; đọc/ghi cấu hình Theme qua ThemeModuleProtocol & LockScreenModuleProtocol.

import SwiftUI

public struct ThemesTabView: View {
    @Environment(\.lockInPalette) private var palette
    @State private var themeVM: ThemeGalleryViewModel
    private let onPreviewReminderPopup: () -> Void

    public init(container: DependencyContainer, onPreviewReminderPopup: @escaping () -> Void) {
        _themeVM = State(initialValue: ThemeGalleryViewModel(
            themeModule: container.theme,
            lockScreenModule: container.lockScreen,
            syncEventBus: container.syncEventBus
        ))
        self.onPreviewReminderPopup = onPreviewReminderPopup
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ThemeGalleryView(viewModel: themeVM)
                    ShufflePoolConfigView(viewModel: themeVM)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Pop-up Nhắc việc khi mở app", systemImage: "bell.and.waves.left.and.right")
                            .font(.headline)

                        Toggle("Tự động hiện nhắc việc nếu còn bài chưa xong", isOn: $themeVM.showPopupOnOpen)
                            .onChange(of: themeVM.showPopupOnOpen) { _, newValue in
                                Task { await themeVM.persistShowPopupOnOpen(newValue) }
                            }

                        Button {
                            onPreviewReminderPopup()
                        } label: {
                            Label("Xem bảng nhắc việc hiện tại", systemImage: "eye")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .minimalCardStyle()
                }
                .padding()
            }
            .background(Color(lockInHex: palette.backgroundHex).ignoresSafeArea())
            .navigationTitle("Giao diện & Nhắc nhở")
        }
    }
}
