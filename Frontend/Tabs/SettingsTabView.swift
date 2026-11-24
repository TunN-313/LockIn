// SettingsTabView.swift — Tab 3 ghép LockScreenWizard, tùy chọn hiển thị và SecurityAndBackup.
// Thuộc Frontend/Tabs; tuân thủ bảng ánh xạ agents.md §3.4 giữa Frontend Features và Backend Modules.

import SwiftUI

public struct SettingsTabView: View {
    @Environment(\.lockInPalette) private var palette

    @State private var wizardVM: LockScreenWizardViewModel
    @State private var securityVM: SecurityAndBackupViewModel

    public init(container: DependencyContainer) {
        _wizardVM = State(initialValue: LockScreenWizardViewModel(
            lockScreenModule: container.lockScreen,
            themeModule: container.theme,
            syncEventBus: container.syncEventBus
        ))
        _securityVM = State(initialValue: SecurityAndBackupViewModel(
            securityModule: container.security,
            authModule: container.auth,
            backupModule: container.backup,
            storageMaintenance: container.storageMaintenance
        ))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    LockScreenWizardView(viewModel: wizardVM)
                    SecuritySettingsView(viewModel: securityVM)
                }
                .padding()
            }
            .background(Color(lockInHex: palette.backgroundHex).ignoresSafeArea())
            .navigationTitle("Cài đặt & Kết nối")
            .onAppear {
                wizardVM.startObserving()
            }
            .onDisappear {
                wizardVM.stopObserving()
            }
        }
    }
}
