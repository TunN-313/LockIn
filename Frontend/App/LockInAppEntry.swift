// LockInAppEntry.swift — Điểm vào ứng dụng LockIn, khóa hướng dọc Portrait-only và nạp DependencyContainer.
// Thuộc Frontend/App; gọi SyncEventBus.refreshAll() qua RootGateView và khởi tạo an toàn khi chạy XCTest host.

import SwiftUI
import UIKit

public final class LockInAppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
public struct LockInAppEntry: App {
    @UIApplicationDelegateAdaptor(LockInAppDelegate.self) private var appDelegate

    private let container: DependencyContainer?
    private let startupErrorMessage: String?

    public init() {
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        do {
            self.container = isRunningTests
                ? try DependencyContainer.makeForUnitTestHost()
                : try DependencyContainer.makeLive()
            self.startupErrorMessage = nil
        } catch {
            self.container = nil
            self.startupErrorMessage = error.localizedDescription
        }
    }

    public var body: some Scene {
        WindowGroup {
            if let container {
                RootGateView(container: container)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Không thể khởi động kho lưu trữ LockIn")
                        .font(.headline)
                    Text(startupErrorMessage ?? "Vui lòng kiểm tra cấu hình Shared App Group.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
    }
}
