// AppLockGateView.swift — Màn hình khóa ứng dụng hỗ trợ Face ID/Touch ID, mã PIN 6 số và khôi phục bằng mật khẩu.
// Thuộc Frontend/Features/Auth; chỉ gọi AppLockGateViewModel và không import LocalAuthentication hay Security.

import SwiftUI

public struct AppLockGateView: View {
    @Environment(\.lockInPalette) private var palette
    @Bindable var viewModel: AppLockGateViewModel

    public init(viewModel: AppLockGateViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "faceid")
                    .font(.system(size: 52))
                    .foregroundStyle(Color(lockInHex: palette.accentHex))

                Text("LockIn đang khóa")
                    .font(.title2.weight(.bold))

                Text("Xác thực sinh trắc học hoặc nhập mã PIN dự phòng để tiếp tục ôn thi.")
                    .font(.subheadline)
                    .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                Button {
                    Task { await viewModel.attemptBiometricUnlock() }
                } label: {
                    Label("Mở khóa bằng Face ID / Touch ID", systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isProcessing || viewModel.biometricInvalidatedMode)

                if viewModel.hasPinConfigured {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mã PIN 6 số dự phòng")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))

                        SecureField("••••••", text: $viewModel.pinInput)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            Task { await viewModel.submitPin() }
                        } label: {
                            Text("Xác nhận mã PIN")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isProcessing || viewModel.cooldownSeconds > 0)
                    }
                }

                if viewModel.cooldownSeconds > 0 {
                    Label("Tạm khóa thử PIN (\(viewModel.cooldownSeconds)s)", systemImage: "clock.badge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if viewModel.requiresPasswordRecovery || !viewModel.hasPinConfigured {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Khôi phục bằng mật khẩu tài khoản")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(lockInHex: palette.textSecondaryHex))

                        SecureField("Mật khẩu tài khoản cục bộ", text: $viewModel.passwordInput)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            Task { await viewModel.submitPasswordRecovery() }
                        } label: {
                            Text("Mở khóa bằng mật khẩu")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isProcessing)
                    }
                } else {
                    Button("Quên PIN / Cần dùng mật khẩu tài khoản?") {
                        viewModel.requiresPasswordRecovery = true
                    }
                    .font(.footnote)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .minimalCardStyle()

            Spacer()
        }
        .padding()
        .background(Color(lockInHex: palette.backgroundHex).ignoresSafeArea())
        .task {
            await viewModel.loadInitialState()
        }
    }
}
