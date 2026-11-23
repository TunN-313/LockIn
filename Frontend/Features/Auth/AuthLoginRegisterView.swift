// AuthLoginRegisterView.swift — Màn hình đăng nhập và tạo hồ sơ cục bộ theo phong cách tối giản Portrait-only.
// Thuộc Frontend/Features/Auth; chỉ kết nối AuthLoginRegisterViewModel và Frontend/DesignSystem.

import SwiftUI

public struct AuthLoginRegisterView: View {
    @Environment(\.lockInPalette) private var palette
    @Bindable var viewModel: AuthLoginRegisterViewModel

    public init(viewModel: AuthLoginRegisterViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(lockInHex: palette.accentHex))

                    Text("LockIn")
                        .font(.largeTitle.weight(.bold))

                    Text("Ôn thi ngay trên màn hình khóa — Dữ liệu lưu cục bộ an toàn")
                        .font(.subheadline)
                        .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                Picker("Chế độ tài khoản", selection: $viewModel.mode) {
                    ForEach(AuthFormMode.allCases) { formMode in
                        Text(formMode.title).tag(formMode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tên đăng nhập")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                        TextField("vd: minh_on_thi", text: $viewModel.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                    }

                    if viewModel.mode == .register {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tên hiển thị")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                            TextField("Tên của bạn", text: $viewModel.displayName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mật khẩu")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                        SecureField("Tối thiểu 6 ký tự", text: $viewModel.password)
                            .textFieldStyle(.roundedBorder)
                    }

                    if viewModel.mode == .register {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nhập lại mật khẩu")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                            SecureField("Xác nhận mật khẩu", text: $viewModel.confirmPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await viewModel.submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isSubmitting {
                                ProgressView()
                            } else {
                                Text(viewModel.mode.title)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSubmitting)
                }
                .minimalCardStyle()

                if !viewModel.existingProfiles.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Hồ sơ có sẵn trên máy")
                            .font(.headline)

                        ForEach(viewModel.existingProfiles) { profile in
                            Button {
                                viewModel.prefillProfile(profile)
                            } label: {
                                HStack {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.displayName)
                                            .font(.subheadline.weight(.semibold))
                                        Text("@\(profile.username)")
                                            .font(.caption)
                                            .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right.circle")
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .minimalCardStyle()
                }
            }
            .padding()
        }
        .background(Color(lockInHex: palette.backgroundHex).ignoresSafeArea())
        .task {
            await viewModel.loadProfiles()
        }
    }
}
