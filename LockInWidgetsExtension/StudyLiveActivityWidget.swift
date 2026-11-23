// StudyLiveActivityWidget.swift — Giao diện Interactive Live Activity và Dynamic Island hiển thị thẻ ôn thi.
// Tích hợp 4 nút LiveActivityIntent (Trước, Lật, Đã thuộc, Tiếp), hỗ trợ Privacy Mode và 6 ThemePalette.

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct StudyLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StudySessionAttributes.self) { context in
            LockScreenStudyBannerView(state: context.state)
        } dynamicIsland: { context in
            let palette = ThemePalette.palette(for: context.state.activeThemeId)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.deckTitle, systemImage: "book.closed.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hexString: palette.accentHex))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(cardPositionLabel(for: context.state))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color(hexString: palette.textSecondaryHex))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayText(for: context.state))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color(hexString: palette.textPrimaryHex))
                            .lineLimit(3)
                            .privacySensitive(context.state.privacyModeEnabled)

                        StudyActionButtonsRow(state: context.state, palette: palette)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(Color(hexString: palette.accentHex))
            } compactTrailing: {
                Text(cardPositionLabel(for: context.state))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(Color(hexString: palette.accentHex))
            }
            .keylineTint(Color(hexString: palette.accentHex))
        }
    }

    private func cardPositionLabel(for state: StudySessionAttributes.ContentState) -> String {
        guard state.totalCards > 0 else { return "0/0" }
        let displayIndex = min(state.currentIndex + 1, state.totalCards)
        return "\(displayIndex)/\(state.totalCards)"
    }

    private func displayText(for state: StudySessionAttributes.ContentState) -> String {
        state.isAnswerVisible && !state.answerText.isEmpty ? state.answerText : state.questionText
    }
}

private struct LockScreenStudyBannerView: View {
    let state: StudySessionAttributes.ContentState

    var body: some View {
        let palette = ThemePalette.palette(for: state.activeThemeId)
        let bgColor = Color(hexString: palette.backgroundHex)
        let cardColor = Color(hexString: palette.cardHex)
        let primaryColor = Color(hexString: palette.textPrimaryHex)
        let secondaryColor = Color(hexString: palette.textSecondaryHex)
        let accentColor = Color(hexString: palette.accentHex)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(state.deckTitle.isEmpty ? "LockIn" : state.deckTitle, systemImage: "book.closed.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .lineLimit(1)

                Spacer()

                Text(positionText)
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(secondaryColor)

                Label("\(state.masteredCount)", systemImage: "checkmark.seal.fill")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(accentColor)
            }

            ProgressView(value: masteryProgress)
                .tint(accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(state.isAnswerVisible ? "Đáp án" : "Câu hỏi")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(secondaryColor)

                Text(activeBodyText)
                    .font(bodyFont(for: palette))
                    .foregroundStyle(primaryColor)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .privacySensitive(state.privacyModeEnabled)
            }
            .padding(10)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            StudyActionButtonsRow(state: state, palette: palette)
        }
        .padding(12)
        .activityBackgroundTint(bgColor)
        .activitySystemActionForegroundColor(accentColor)
    }

    private var positionText: String {
        guard state.totalCards > 0 else { return "0/0" }
        return "\(min(state.currentIndex + 1, state.totalCards))/\(state.totalCards)"
    }

    private var masteryProgress: Double {
        guard state.totalCards > 0 else { return 0 }
        return min(1.0, Double(state.masteredCount) / Double(state.totalCards))
    }

    private var activeBodyText: String {
        if state.isAnswerVisible {
            return state.answerText.isEmpty ? "Chưa có đáp án." : state.answerText
        }
        return state.questionText.isEmpty ? "Chưa có câu hỏi." : state.questionText
    }

    private func bodyFont(for palette: ThemePalette) -> Font {
        let scale = LockScreenFontScale(rawValue: state.fontScaleRaw) ?? .standard
        let size: CGFloat
        switch scale {
        case .compact:
            size = 13
        case .standard:
            size = 15
        case .large:
            size = 17
        }
        let design: Font.Design
        switch palette.fontDesign {
        case .default:
            design = .default
        case .rounded:
            design = .rounded
        case .monospaced:
            design = .monospaced
        case .serif:
            design = .serif
        }
        return .system(size: size, weight: .medium, design: design)
    }
}

private struct StudyActionButtonsRow: View {
    let state: StudySessionAttributes.ContentState
    let palette: ThemePalette

    var body: some View {
        let accent = Color(hexString: palette.accentHex)
        let primary = Color(hexString: palette.textPrimaryHex)
        let card = Color(hexString: palette.cardHex)

        HStack(spacing: 6) {
            Button(intent: PrevCardIntent()) {
                Label("Trước", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(primary)
            .background(card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(intent: FlipCardIntent()) {
                Label(state.isAnswerVisible ? "Ẩn" : "Lật", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .background(card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(intent: MarkMasteredIntent()) {
                Label("Thuộc", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .background(card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(intent: NextCardIntent()) {
                Label("Tiếp", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(primary)
            .background(card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private extension Color {
    init(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var hexNumber: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&hexNumber)
        let r = Double((hexNumber & 0xFF0000) >> 16) / 255.0
        let g = Double((hexNumber & 0x00FF00) >> 8) / 255.0
        let b = Double(hexNumber & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
