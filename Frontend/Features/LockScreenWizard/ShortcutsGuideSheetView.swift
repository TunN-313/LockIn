// ShortcutsGuideSheetView.swift — Hướng dẫn thiết lập iOS Shortcuts Automation với các trigger có thật trên iOS.
// Thuộc Frontend/Features/LockScreenWizard; tuân thủ spec.md mục 3 & 4.1 về Shortcuts và vòng đời Live Activity 8–12h.

import SwiftUI

public struct ShortcutsGuideSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lockInPalette) private var palette

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Tự động xoay Theme qua iOS Shortcuts", systemImage: "wand.and.stars")
                            .font(.headline)
                        Text("iOS Shortcuts hỗ trợ các trigger thực tế sau để gọi action \"Xoay Theme LockIn\" (RotateLockInThemeIntent) chạy ngầm mà không cần mở app:")
                            .font(.subheadline)
                            .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))

                        bullet("Theo giờ trong ngày (Time of Day) — ví dụ đổi theme sáng/chiều/tối.")
                        bullet("Chế độ Tập trung (Focus Mode) — ví dụ khi bật Study Focus.")
                        bullet("Khi mở hoặc đóng ứng dụng (App Opened / Closed).")
                        bullet("Khi cắm hoặc rút sạc (Charger).")
                    }
                    .minimalCardStyle()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Khởi động lại Live Activity sau 8–12 giờ", systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                        Text("Hệ điều hành iOS tự kết thúc Live Activity sau tối đa 8–12 giờ. Để bật lại phiên mới, hãy mở app LockIn hoặc chạy Shortcut \"Khởi động lại phiên ôn trên Lock Screen\" (StartStudyActivityIntent — sẽ mở app lên foreground để iOS cho phép Activity.request).")
                            .font(.subheadline)
                            .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                    }
                    .minimalCardStyle()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Mẹo ghim Widget lên màn hình khóa", systemImage: "rectangle.grid.1x2")
                            .font(.headline)
                        bullet("Nhấn giữ màn hình khóa iPhone → Tùy chỉnh → Màn hình khóa.")
                        bullet("Thêm widget \"Vòng tiến độ LockIn\" (tròn) và \"Ôn nhanh / Tác vụ LockIn\" (chữ nhật) dưới đồng hồ.")
                    }
                    .minimalCardStyle()
                }
                .padding()
            }
            .background(Color(lockInHex: palette.backgroundHex).ignoresSafeArea())
            .navigationTitle("Hướng dẫn iOS Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .padding(.top, 6)
                .foregroundStyle(Color(lockInHex: palette.accentHex))
            Text(text)
                .font(.footnote)
        }
    }
}
