// LockInWidgetBundle.swift — Điểm đăng ký toàn bộ Live Activity và Lock Screen Widgets trong LockInWidgetsExtension.
// Chỉ phụ thuộc Shared/**, WidgetKit và SwiftUI.

import SwiftUI
import WidgetKit

@main
struct LockInWidgetBundle: WidgetBundle {
    var body: some Widget {
        StudyLiveActivityWidget()
        StudyProgressCircularWidget()
        StudyQuickActionRectangularWidget()
    }
}
