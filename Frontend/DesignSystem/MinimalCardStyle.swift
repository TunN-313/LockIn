// MinimalCardStyle.swift — Component Modifier tạo thẻ bo góc tối giản, viền mỏng thống nhất toàn ứng dụng LockIn.
// Thuộc Frontend/DesignSystem; đọc màu bề mặt và chữ từ EnvironmentValues.lockInPalette.

import SwiftUI

public struct MinimalCardStyle: ViewModifier {
    @Environment(\.lockInPalette) private var palette
    private let padding: CGFloat

    public init(padding: CGFloat = 16) {
        self.padding = padding
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(lockInHex: palette.cardHex), in: shape)
            .overlay(
                shape.stroke(
                    Color(lockInHex: palette.textSecondaryHex).opacity(palette.isDarkSurface ? 0.22 : 0.14),
                    lineWidth: 1
                )
            )
            .shadow(
                color: Color.black.opacity(palette.isDarkSurface ? 0.22 : 0.05),
                radius: 8,
                x: 0,
                y: 3
            )
    }
}

public extension View {
    func minimalCardStyle(padding: CGFloat = 16) -> some View {
        modifier(MinimalCardStyle(padding: padding))
    }
}
