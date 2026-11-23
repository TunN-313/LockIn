// ThemeStyleModifier.swift — Cung cấp Environment lockInPalette, Color(lockInHex:) và modifier áp dụng ThemePalette lên mọi View.
// Thuộc Frontend/DesignSystem; chỉ sử dụng SwiftUI và Shared/Themes/ThemePalette.

import SwiftUI

public extension Color {
    init(lockInHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value & 0xFF0000) >> 16) / 255.0
        let green = Double((value & 0x00FF00) >> 8) / 255.0
        let blue = Double(value & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

public extension ThemeFontDesign {
    var swiftUIDesign: Font.Design {
        switch self {
        case .default:
            return .default
        case .rounded:
            return .rounded
        case .monospaced:
            return .monospaced
        case .serif:
            return .serif
        }
    }
}

private struct LockInPaletteEnvironmentKey: EnvironmentKey {
    static let defaultValue: ThemePalette = .minimalPaper
}

public extension EnvironmentValues {
    var lockInPalette: ThemePalette {
        get { self[LockInPaletteEnvironmentKey.self] }
        set { self[LockInPaletteEnvironmentKey.self] = newValue }
    }
}

public struct ThemeStyleModifier: ViewModifier {
    let palette: ThemePalette

    public init(palette: ThemePalette) {
        self.palette = palette
    }

    public func body(content: Content) -> some View {
        content
            .environment(\.lockInPalette, palette)
            .preferredColorScheme(palette.isDarkSurface ? .dark : .light)
            .tint(Color(lockInHex: palette.accentHex))
            .fontDesign(palette.fontDesign.swiftUIDesign)
            .foregroundStyle(Color(lockInHex: palette.textPrimaryHex))
    }
}

public extension View {
    func lockInTheme(_ palette: ThemePalette) -> some View {
        modifier(ThemeStyleModifier(palette: palette))
    }
}
