// ThemePalette.swift — Định nghĩa mô hình ThemePalette và 6 theme tối giản cài sẵn cho LockIn.
// Dùng chung giữa Backend/ThemeModule, Frontend/DesignSystem và LockInWidgetsExtension.

import Foundation

public enum ThemeFontDesign: String, Codable, CaseIterable, Sendable {
    case `default`
    case rounded
    case monospaced
    case serif
}

public struct ThemePalette: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let backgroundHex: String
    public let cardHex: String
    public let textPrimaryHex: String
    public let textSecondaryHex: String
    public let accentHex: String
    public let fontDesign: ThemeFontDesign
    public let isDarkSurface: Bool

    public init(
        id: String,
        displayName: String,
        backgroundHex: String,
        cardHex: String,
        textPrimaryHex: String,
        textSecondaryHex: String,
        accentHex: String,
        fontDesign: ThemeFontDesign,
        isDarkSurface: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.backgroundHex = backgroundHex
        self.cardHex = cardHex
        self.textPrimaryHex = textPrimaryHex
        self.textSecondaryHex = textSecondaryHex
        self.accentHex = accentHex
        self.fontDesign = fontDesign
        self.isDarkSurface = isDarkSurface
    }

    public static let minimalPaper = ThemePalette(
        id: "minimal_paper",
        displayName: "Minimal Paper",
        backgroundHex: "#FAF9F6",
        cardHex: "#FFFFFF",
        textPrimaryHex: "#1E293B",
        textSecondaryHex: "#475569",
        accentHex: "#2563EB",
        fontDesign: .default,
        isDarkSurface: false
    )

    public static let darkFocus = ThemePalette(
        id: "dark_focus",
        displayName: "Dark Focus",
        backgroundHex: "#0D0D0F",
        cardHex: "#18181B",
        textPrimaryHex: "#F8FAFC",
        textSecondaryHex: "#94A3B8",
        accentHex: "#14B8A6",
        fontDesign: .default,
        isDarkSurface: true
    )

    public static let pastelMatcha = ThemePalette(
        id: "pastel_matcha",
        displayName: "Pastel Matcha",
        backgroundHex: "#ECF5EE",
        cardHex: "#F7FBF8",
        textPrimaryHex: "#1B3B2B",
        textSecondaryHex: "#436855",
        accentHex: "#16A34A",
        fontDesign: .rounded,
        isDarkSurface: false
    )

    public static let examHighContrast = ThemePalette(
        id: "exam_high_contrast",
        displayName: "Exam High-Contrast",
        backgroundHex: "#000000",
        cardHex: "#111111",
        textPrimaryHex: "#FFFFFF",
        textSecondaryHex: "#FACC15",
        accentHex: "#FACC15",
        fontDesign: .monospaced,
        isDarkSurface: true
    )

    public static let midnightInk = ThemePalette(
        id: "midnight_ink",
        displayName: "Midnight Ink",
        backgroundHex: "#0F172A",
        cardHex: "#1E293B",
        textPrimaryHex: "#F8F4EC",
        textSecondaryHex: "#CBD5E1",
        accentHex: "#F59E0B",
        fontDesign: .serif,
        isDarkSurface: true
    )

    public static let warmSand = ThemePalette(
        id: "warm_sand",
        displayName: "Warm Sand",
        backgroundHex: "#F5EFE6",
        cardHex: "#FFFBF5",
        textPrimaryHex: "#3E2723",
        textSecondaryHex: "#6D4C41",
        accentHex: "#C2410C",
        fontDesign: .rounded,
        isDarkSurface: false
    )

    public static let allBuiltIn: [ThemePalette] = [
        .minimalPaper,
        .darkFocus,
        .pastelMatcha,
        .examHighContrast,
        .midnightInk,
        .warmSand
    ]

    public static func palette(for id: String) -> ThemePalette {
        allBuiltIn.first { $0.id == id } ?? .minimalPaper
    }
}
