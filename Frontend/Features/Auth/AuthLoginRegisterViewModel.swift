// AuthLoginRegisterViewModel.swift — Quản lý trạng thái đăng nhập, đăng ký và chọn hồ sơ cục bộ cho Auth gate.
// Thuộc Frontend/Features/Auth; chỉ giao tiếp với Backend qua AuthModuleProtocol.

import Foundation
import Observation

public enum AuthFormMode: String, CaseIterable, Identifiable {
    case login
    case register

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .login:
            return "Đăng nhập"
        case .register:
            return "Tạo tài khoản"
        }
    }
}

@MainActor
@Observable
public final class AuthLoginRegisterViewModel {
    private let authModule: AuthModuleProtocol
    private let onAuthenticated: (UserProfileDTO) -> Void

    public var mode: AuthFormMode = .login
    public var username: String = ""
    public var displayName: String = ""
    public var password: String = ""
    public var confirmPassword: String = ""
    public var existingProfiles: [UserProfileDTO] = []
    public var isSubmitting: Bool = false
    public var errorMessage: String?

    public init(
        authModule: AuthModuleProtocol,
        onAuthenticated: @escaping (UserProfileDTO) -> Void
    ) {
        self.authModule = authModule
        self.onAuthenticated = onAuthenticated
    }

    public func loadProfiles() async {
        do {
            let profiles = try await authModule.listProfiles()
            existingProfiles = profiles
            if profiles.isEmpty {
                mode = .register
            } else if username.isEmpty {
                username = profiles[0].username
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func prefillProfile(_ profile: UserProfileDTO) {
        mode = .login
        username = profile.username
        password = ""
        errorMessage = nil
    }

    public func submit() async {
        errorMessage = nil
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty else {
            errorMessage = "Vui lòng nhập tên đăng nhập."
            return
        }
        guard !password.isEmpty else {
            errorMessage = "Vui lòng nhập mật khẩu."
            return
        }

        if mode == .register {
            let cleanDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanDisplayName.isEmpty else {
                errorMessage = "Vui lòng nhập tên hiển thị."
                return
            }
            guard password == confirmPassword else {
                errorMessage = "Mật khẩu xác nhận chưa trùng khớp."
                return
            }
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let user: UserProfileDTO
            switch mode {
            case .login:
                user = try await authModule.login(username: cleanUsername, password: password)
            case .register:
                user = try await authModule.register(
                    username: cleanUsername,
                    displayName: displayName,
                    password: password
                )
            }
            password = ""
            confirmPassword = ""
            onAuthenticated(user)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
