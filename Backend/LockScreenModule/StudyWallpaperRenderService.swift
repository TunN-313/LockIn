// StudyWallpaperRenderService.swift — Render ảnh PNG tóm tắt 3–5 dòng ôn thi theo ThemePalette để lưu Photos.
// Ngoại lệ duy nhất trong Backend/ dùng SwiftUI ImageRenderer (không chứa màn hình điều hướng hay UI tương tác).

import Foundation
import SwiftUI
import UIKit

public protocol StudyWallpaperRenderServiceProtocol: Sendable {
    @MainActor func renderSummaryPNG(
        deckTitle: String,
        summaryLines: [String],
        palette: ThemePalette
    ) throws -> WallpaperRenderPayload
}

public final class StudyWallpaperRenderService: StudyWallpaperRenderServiceProtocol {
    public init() {}

    @MainActor
    public func renderSummaryPNG(
        deckTitle: String,
        summaryLines: [String],
        palette: ThemePalette
    ) throws -> WallpaperRenderPayload {
        let clampedLines = Array(summaryLines.prefix(5))
        let canvas = StudyWallpaperCanvas(
            deckTitle: deckTitle,
            lines: clampedLines,
            palette: palette
        )

        let renderer = ImageRenderer(content: canvas)
        renderer.proposedSize = ProposedViewSize(width: 1179, height: 2556)
        renderer.scale = 1.0

        guard let uiImage = renderer.uiImage,
              let pngData = uiImage.pngData() else {
            throw LockInDomainError.persistenceFailure("Không tạo được ảnh PNG cho hình nền tóm tắt.")
        }

        return WallpaperRenderPayload(deckTitle: deckTitle, pngData: pngData)
    }
}

private struct StudyWallpaperCanvas: View {
    let deckTitle: String
    let lines: [String]
    let palette: ThemePalette

    var body: some View {
        let bg = Color(hex: palette.backgroundHex)
        let card = Color(hex: palette.cardHex)
        let primary = Color(hex: palette.textPrimaryHex)
        let secondary = Color(hex: palette.textSecondaryHex)
        let accent = Color(hex: palette.accentHex)

        ZStack {
            bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                // Chừa khoảng an toàn cho đồng hồ và widgets Lock Screen iOS ở phía trên.
                Spacer().frame(height: 540)

                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 14) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(accent)
                        Text(deckTitle.isEmpty ? "LockIn Ôn Thi" : deckTitle)
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(accent)
                            .lineLimit(2)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 14) {
                                Text("\(index + 1).")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(accent)
                                Text(line)
                                    .font(.system(size: 30, weight: .medium))
                                    .foregroundStyle(primary)
                                    .lineLimit(3)
                            }
                            if index < lines.count - 1 {
                                Divider()
                                    .overlay(secondary.opacity(0.25))
                            }
                        }
                    }
                }
                .padding(40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(card, in: RoundedRectangle(cornerRadius: 36, style: .continuous))

                Spacer()

                // Chừa khoảng an toàn phía dưới cho nút đèn pin và camera trên Lock Screen.
                Spacer().frame(height: 240)
            }
            .padding(.horizontal, 64)
        }
        .frame(width: 1179, height: 2556)
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
