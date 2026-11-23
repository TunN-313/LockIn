// SecuritySettingsView.swift — Màn hình tài khoản cục bộ, khóa sinh trắc học/PIN, Backup và xóa dữ liệu 2 bước.
// Thuộc Frontend/Features/SecurityAndBackup; kết nối SecurityAndBackupViewModel và EncryptedBackupSheetView.

import SwiftUI

public struct SecuritySettingsView: View {
    @Environment(\.lockInPalette) private var palette
    @Bindable var viewModel: SecurityAndBackupViewModel

    @State private var isPresentingPinSheet = false
    @State private var isPresentingBackupSheet = false
    @State private var isPresentingSwitchProfile = false
    @State private var isConfirmingPurgeStep1 = false
    @State private var isConfirmingPurgeStep2 = false

    @State private var draftPin = ""
    @State private var selectedProfileToSwitch: UserProfileDTO?
    @State private var switchPassword = ""

    public init(viewModel: SecurityAndBackupViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Tài khoản & Bảo mật cục bộ", systemImage: "shield.lefthalf.filled")
                .font(.headline)

            if let statusMessage = viewModel.statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color(lockInHex: palette.accentHex))
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let user = viewModel.activeUser {
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color(lockInHex: palette.accentHex))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                            .font(.subheadline.weight(.bold))
                        Text("@\(user.username) • Lưu cục bộ")
                            .font(.caption)
                            .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                    }
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                Button {
                    isPresentingSwitchProfile = true
                } label: {
                    Label("Đổi hồ sơ", systemImage: "person.2")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.allProfiles.count <= 1)

                Button(role: .destructive) {
                    Task { await viewModel.logout() }
                } label: {
                    Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            Toggle(
                "Khóa App bằng Face ID / Touch ID",
                isOn: Binding(
                    get: { viewModel.isBiometricEnabled },
                    set: { newValue in
                        Task { await viewModel.setBiometricEnabled(newValue) }
                    }
                )
            )

            Button {
                draftPin = ""
                isPresentingPinSheet = true
            } label: {
                Label(
                    viewModel.hasFallbackPin ? "Đổi mã PIN 6 số dự phòng" : "Thiết lập mã PIN 6 số dự phòng",
                    systemImage: "number.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Divider()

            Button {
                isPresentingBackupSheet = true
            } label: {
                Label("Sao lưu / Khôi phục mã hóa (.lockinbackup)", systemImage: "lock.doc.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                isConfirmingPurgeStep1 = true
            } label: {
                Label("Xóa dữ liệu học tập của hồ sơ này", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .minimalCardStyle()
        .task {
            await viewModel.refresh()
        }
        .sheet(isPresented: $isPresentingPinSheet) {
            pinEditorSheet
        }
        .sheet(isPresented: $isPresentingBackupSheet) {
            EncryptedBackupSheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $isPresentingSwitchProfile) {
            switchProfileSheet
        }
        .alert("Xóa dữ liệu học tập?", isPresented: $isConfirmingPurgeStep1) {
            Button("Tiếp tục", role: .destructive) {
                isConfirmingPurgeStep2 = true
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Thao tác này sẽ xóa tất cả bộ đề, thẻ ôn, tác vụ, lịch học và tiến độ của hồ sơ hiện tại.")
        }
        .alert("Xác nhận lần cuối", isPresented: $isConfirmingPurgeStep2) {
            Button("Xóa vĩnh viễn", role: .destructive) {
                Task { await viewModel.purgeCurrentUserStudyData() }
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Dữ liệu đã xóa không thể hoàn tác nếu bạn chưa xuất file .lockinbackup.")
        }
    }

    private var pinEditorSheet: some View {
        NavigationStack {
            Form {
                Section("Mã PIN 6 số (PBKDF2 600,000 vòng)") {
                    SecureField("Nhập đúng 6 chữ số", text: $draftPin)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Cài đặt mã PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { isPresentingPinSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu PIN") {
                        Task {
                            if await viewModel.setFallbackPin(draftPin) {
                                isPresentingPinSheet = false
                            }
                        }
                    }
                }
            }
        }
    }

    private var switchProfileSheet: some View {
        NavigationStack {
            Form {
                Section("Chọn hồ sơ khác trên máy") {
                    ForEach(viewModel.allProfiles.filter { $0.id != viewModel.activeUser?.id }) { profile in
                        Button {
                            selectedProfileToSwitch = profile
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.displayName)
                                    Text("@\(profile.username)")
                                        .font(.caption)
                                        .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                                }
                                Spacer()
                                if selectedProfileToSwitch?.id == profile.id {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                        }
                    }
                }

                if selectedProfileToSwitch != nil {
                    Section("Xác thực mật khẩu hồ sơ đích") {
                        SecureField("Mật khẩu của hồ sơ", text: $switchPassword)
                    }
                }
            }
            .navigationTitle("Chuyển hồ sơ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { isPresentingSwitchProfile = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đăng nhập") {
                        guard let target = selectedProfileToSwitch else { return }
                        Task {
                            let ok = await viewModel.switchProfile(userId: target.id, password: switchPassword)
                            switchPassword = ""
                            if ok { isPresentingSwitchProfile = false }
                        }
                    }
                    .disabled(selectedProfileToSwitch == nil || switchPassword.isEmpty)
                }
            }
        }
    }
}
