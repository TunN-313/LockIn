// ProgressBarComponent.swift — Thanh tiến độ hoàn thành tái sử dụng cho Header, StudyDeck và Task.
// Thuộc Frontend/DesignSystem; chỉ dùng SwiftUI, SF Symbols và ThemePalette.

import SwiftUI

public struct ProgressBarComponent: View {
    @Environment(\.lockInPalette) private var palette

    private let title: String
    private let subtitle: String?
    private let progress: Double
    private let customAccentHex: String?
    private let height: CGFloat

    public init(
        title: String,
        subtitle: String? = nil,
        progress: Double,
        accentHex: String? = nil,
        height: CGFloat = 10
    ) {
        self.title = title
        self.subtitle = subtitle
        self.progress = min(1.0, max(0.0, progress))
        self.customAccentHex = accentHex
        self.height = height
    }

    public var body: some View {
        let accent = Color(lockInHex: customAccentHex ?? palette.accentHex)
        let secondary = Color(lockInHex: palette.textSecondaryHex)
        let primary = Color(lockInHex: palette.textPrimaryHex)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primary)
                    .lineLimit(1)

                Spacer()

                Text(subtitle ?? "\(Int((progress * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondary)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                let totalWidth = max(0, proxy.size.width)
                let fillWidth = max(progress > 0 ? height : 0, totalWidth * progress)
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(secondary.opacity(0.18))
                    Capsule(style: .continuous)
                        .fill(accent)
                        .frame(width: fillWidth)
                        .animation(.easeInOut(duration: 0.25), value: progress)
                }
            }
            .frame(height: height)
        }
    }
}
