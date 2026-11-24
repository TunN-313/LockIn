// ThemeGalleryView.swift — Lưới xem trước và chọn trực tiếp 6 ThemePalette tối giản trên Tab 2.
// Thuộc Frontend/Features/ThemeGallery; hiển thị màu nền, màu thẻ, chữ và accent thật của từng theme.

import SwiftUI

public struct ThemeGalleryView: View {
    @Environment(\.lockInPalette) private var currentPalette
    @Bindable var viewModel: ThemeGalleryViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    public init(viewModel: ThemeGalleryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Bộ sưu tập 6 Theme", systemImage: "paintpalette.fill")
                    .font(.headline)
                Spacer()
                Text(ThemePalette.palette(for: viewModel.activeThemeId).displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(lockInHex: currentPalette.accentHex))
            }

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(Color(lockInHex: currentPalette.accentHex))
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.builtInThemes) { theme in
                    themePreviewCard(theme)
                }
            }
        }
        .minimalCardStyle()
        .task {
            viewModel.startObserving()
            await viewModel.refresh()
        }
    }

    private func themePreviewCard(_ theme: ThemePalette) -> some View {
        let isSelected = viewModel.activeThemeId == theme.id
        return Button {
            Task { await viewModel.selectTheme(theme.id) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(theme.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(lockInHex: theme.textPrimaryHex))
                        .lineLimit(1)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(lockInHex: theme.accentHex))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Câu hỏi mẫu")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(lockInHex: theme.textPrimaryHex))
                    Text("Tương phản dễ đọc trên Lock Screen")
                        .font(.caption2)
                        .foregroundStyle(Color(lockInHex: theme.textSecondaryHex))
                        .lineLimit(2)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(lockInHex: theme.cardHex), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack {
                    Capsule()
                        .fill(Color(lockInHex: theme.accentHex))
                        .frame(width: 28, height: 5)
                    Spacer()
                    Text(theme.fontDesign.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(Color(lockInHex: theme.textSecondaryHex))
                }
            }
            .fontDesign(theme.fontDesign.swiftUIDesign)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(lockInHex: theme.backgroundHex), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color(lockInHex: theme.accentHex) : Color(lockInHex: theme.textSecondaryHex).opacity(0.25),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
