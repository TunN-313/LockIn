// LocalAuthService.swift — Quản lý đăng ký, đăng nhập, chuyển đổi hồ sơ cục bộ và đăng xuất sạch snapshot.
// Triển khai AuthModuleProtocol; dùng PBKDF2 600,000 vòng, lưu session Keychain thường và phát SyncEventBus.

import ActivityKit
import Foundation
import SwiftData
import WidgetKit

public final class LocalAuthService: AuthModuleProtocol, @unchecked Sendable {
    private let studyStore: SwiftDataStudyStore
    private let isolationGuard: UserDataIsolationGuardProtocol
    private let keychain: KeychainStorageProtocol
    private let crypto: PasswordCryptoServiceProtocol
    private let notificationService: LocalNotificationServiceProtocol
    private let snapshotStore: AppGroupSnapshotStoreProtocol
    private let syncEventBus: SyncEventBus
    private let schedulerPreferencesStore: SchedulerPreferencesFileStore?

    public init(
        studyStore: SwiftDataStudyStore,
        isolationGuard: UserDataIsolationGuardProtocol,
        keychain: KeychainStorageProtocol,
        crypto: PasswordCryptoServiceProtocol,
        notificationService: LocalNotificationServiceProtocol,
        snapshotStore: AppGroupSnapshotStoreProtocol,
        syncEventBus: SyncEventBus,
        schedulerPreferencesStore: SchedulerPreferencesFileStore? = nil
    ) {
        self.studyStore = studyStore
        self.isolationGuard = isolationGuard
        self.keychain = keychain
        self.crypto = crypto
        self.notificationService = notificationService
        self.snapshotStore = snapshotStore
        self.syncEventBus = syncEventBus
        self.schedulerPreferencesStore = schedulerPreferencesStore
    }

    public func register(username: String, displayName: String, password: String) async throws -> UserProfileDTO {
        let normalizedUsername = try validateAndNormalizeUsername(username)
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayName.isEmpty, trimmedDisplayName.count <= 80 else {
            throw LockInDomainError.validationFailed("Tên hiển thị phải từ 1 đến 80 ký tự.")
        }
        try validatePassword(password)

        let salt = try crypto.generateRandomSalt(byteCount: AppConstants.saltByteCount)
        let hash = try crypto.deriveKeyPBKDF2(
            secret: password,
            salt: salt,
            iterations: AppConstants.pbkdf2Iterations,
            keyByteCount: 32
        )

        let createdProfile = try await studyStore.perform { context in
            let uname = normalizedUsername
            let existingDescriptor = FetchDescriptor<UserProfile>(
                predicate: #Predicate<UserProfile> { $0.username == uname }
            )
            if try !context.fetch(existingDescriptor).isEmpty {
                throw LockInDomainError.duplicateUsername
            }

            let now = Date()
            let profile = UserProfile(
                username: normalizedUsername,
                displayName: trimmedDisplayName,
                passwordHash: hash,
                passwordSalt: salt,
                isBiometricEnabled: false,
                createdAt: now,
                lastLoginAt: now
            )
            context.insert(profile)

            let defaultThemePref = ThemePreference(ownerUserId: profile.id)
            context.insert(defaultThemePref)

            let todayProgress = DailyProgress(
                ownerUserId: profile.id,
                dateKey: SharedDailyProgressHelper.dateKey(for: now)
            )
            context.insert(todayProgress)

            try context.save()
            return Self.toDTO(profile)
        }

        try await activateSession(for: createdProfile.id)
        return createdProfile
    }

    public func login(username: String, password: String) async throws -> UserProfileDTO {
        let normalizedUsername = try validateAndNormalizeUsername(username)
        guard !password.isEmpty else {
            throw LockInDomainError.invalidCredentials
        }

        let matchedProfile: UserProfileDTO = try await studyStore.perform { context in
            let uname = normalizedUsername
            let descriptor = FetchDescriptor<UserProfile>(
                predicate: #Predicate<UserProfile> { $0.username == uname }
            )
            guard let profile = try context.fetch(descriptor).first else {
                throw LockInDomainError.invalidCredentials
            }
            let verified = try crypto.verifySecret(
                password,
                salt: profile.passwordSalt,
                expectedHash: profile.passwordHash,
                iterations: AppConstants.pbkdf2Iterations
            )
            guard verified else {
                throw LockInDomainError.invalidCredentials
            }
            profile.lastLoginAt = Date()
            try context.save()
            return Self.toDTO(profile)
        }

        try await activateSession(for: matchedProfile.id)
        return matchedProfile
    }

    public func logout() async throws {
        try keychain.deleteStandardData(account: KeychainAccountKeys.activeUserId)
        try keychain.deleteStandardData(account: KeychainAccountKeys.activeSessionEpoch)

        await notificationService.cancelAllLockInNotifications()

        for activity in Activity<StudySessionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let clearedSnapshot = try snapshotStore.clearAllForLogout()
        WidgetCenter.shared.reloadAllTimelines()
        CrossProcessNotifier.postStateDidChange()

        let marker = SnapshotStateMarker(
            version: clearedSnapshot.snapshotVersion,
            revisionId: clearedSnapshot.snapshotRevisionId
        )
        await MainActor.run {
            syncEventBus.publish(.userSessionChanged(activeUserId: nil), observedMarker: marker)
        }
    }

    public func currentActiveUser() async -> UserProfileDTO? {
        guard let userId = isolationGuard.currentUserId() else { return nil }
        return try? await studyStore.perform { context in
            let uid = userId
            let descriptor = FetchDescriptor<UserProfile>(
                predicate: #Predicate<UserProfile> { $0.id == uid }
            )
            return try context.fetch(descriptor).first.map(Self.toDTO)
        }
    }

    public func listProfiles() async throws -> [UserProfileDTO] {
        try await studyStore.perform { context in
            let descriptor = FetchDescriptor<UserProfile>(
                sortBy: [SortDescriptor(\UserProfile.createdAt, order: .forward)]
            )
            return try context.fetch(descriptor).map(Self.toDTO)
        }
    }

    public func switchProfile(userId: UUID, password: String) async throws -> UserProfileDTO {
        guard !password.isEmpty else {
            throw LockInDomainError.invalidCredentials
        }
        let matched: UserProfileDTO = try await studyStore.perform { context in
            let uid = userId
            let descriptor = FetchDescriptor<UserProfile>(
                predicate: #Predicate<UserProfile> { $0.id == uid }
            )
            guard let profile = try context.fetch(descriptor).first else {
                throw LockInDomainError.entityNotFound
            }
            let verified = try crypto.verifySecret(
                password,
                salt: profile.passwordSalt,
                expectedHash: profile.passwordHash,
                iterations: AppConstants.pbkdf2Iterations
            )
            guard verified else {
                throw LockInDomainError.invalidCredentials
            }
            profile.lastLoginAt = Date()
            try context.save()
            return Self.toDTO(profile)
        }

        try await activateSession(for: matched.id)
        return matched
    }

    private func activateSession(for userId: UUID) async throws {
        await notificationService.cancelAllLockInNotifications()

        for activity in Activity<StudySessionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let initialSession = try snapshotStore.beginSession(userId: userId)
        guard let sessionEpoch = initialSession.sessionEpoch else {
            throw LockInDomainError.persistenceFailure("Không khởi tạo được sessionEpoch cho phiên đăng nhập.")
        }

        try keychain.saveStandardData(Data(userId.uuidString.utf8), account: KeychainAccountKeys.activeUserId)
        try keychain.saveStandardData(Data(sessionEpoch.uuidString.utf8), account: KeychainAccountKeys.activeSessionEpoch)

        let metadata: (
            activeThemeId: String?,
            isShuffleEnabled: Bool?,
            shufflePoolIds: [String]?,
            privacyModeEnabled: Bool?,
            fontScaleRaw: String?,
            progressRatio: Double,
            streak: Int,
            nextTaskId: UUID?,
            nextTaskTitle: String?,
            schedules: [StudyScheduleDTO],
            deckTitlesById: [UUID: String]
        ) = try await studyStore.perform { context in
            let uid = userId
            let pref = try context.fetch(
                FetchDescriptor<ThemePreference>(predicate: #Predicate<ThemePreference> { $0.ownerUserId == uid })
            ).first
            let todayProgress = try SharedDailyProgressHelper.fetchOrCreateTodayProgress(for: uid, in: context)
            let pendingTasks = try context.fetch(
                FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.ownerUserId == uid && $0.isCompleted == false })
            ).sorted(by: SharedTaskQuickActionEngine.sortTasks)

            let schedules = try context.fetch(
                FetchDescriptor<StudySchedule>(predicate: #Predicate<StudySchedule> { $0.ownerUserId == uid })
            ).map {
                StudyScheduleDTO(
                    id: $0.id,
                    ownerUserId: $0.ownerUserId,
                    deckId: $0.deckId,
                    title: $0.title,
                    hour: $0.hour,
                    minute: $0.minute,
                    weekdaysMask: $0.weekdaysMask,
                    isEnabled: $0.isEnabled,
                    autoRotateTheme: $0.autoRotateTheme
                )
            }
            let decks = try context.fetch(
                FetchDescriptor<StudyDeck>(predicate: #Predicate<StudyDeck> { $0.ownerUserId == uid })
            )
            var deckTitles: [UUID: String] = [:]
            for deck in decks {
                deckTitles[deck.id] = deck.title
            }

            try context.save()
            return (
                pref?.activeThemeId,
                pref?.isShuffleEnabled,
                pref?.shufflePoolIds,
                pref?.privacyModeEnabled,
                pref?.lockScreenFontScale,
                SharedDailyProgressHelper.completionRatio(for: todayProgress),
                todayProgress.streakCount,
                pendingTasks.first?.id,
                pendingTasks.first?.title,
                schedules,
                deckTitles
            )
        }

        let syncedSnapshot = try snapshotStore.mutateSnapshotIfSessionMatches(
            expectedUserId: userId,
            expectedSessionEpoch: sessionEpoch
        ) { state in
            if let themeId = metadata.activeThemeId { state.activeThemeId = themeId }
            if let shuffle = metadata.isShuffleEnabled { state.isShuffleEnabled = shuffle }
            if let pool = metadata.shufflePoolIds { state.shufflePoolIds = pool }
            if let privacy = metadata.privacyModeEnabled { state.privacyModeEnabled = privacy }
            if let fontScale = metadata.fontScaleRaw { state.fontScaleRaw = fontScale }
            state.dailyProgressRatio = metadata.progressRatio
            state.streakCount = metadata.streak
            state.nextTaskId = metadata.nextTaskId
            state.nextTaskTitle = metadata.nextTaskTitle
        }

        let frequency = schedulerPreferencesStore?.reminderFrequency(for: userId) ?? .off
        try await notificationService.resyncNotifications(
            forUserId: userId,
            schedules: metadata.schedules,
            deckTitlesById: metadata.deckTitlesById,
            reminderFrequency: frequency
        )

        WidgetCenter.shared.reloadAllTimelines()
        CrossProcessNotifier.postStateDidChange()

        let marker = SnapshotStateMarker(
            version: syncedSnapshot.snapshotVersion,
            revisionId: syncedSnapshot.snapshotRevisionId
        )
        await MainActor.run {
            syncEventBus.publish(.userSessionChanged(activeUserId: userId), observedMarker: marker)
        }
    }

    private func validateAndNormalizeUsername(_ raw: String) throws -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (AppConstants.minUsernameLength...AppConstants.maxUsernameLength).contains(normalized.count) else {
            throw LockInDomainError.invalidUsername(
                "Tên đăng nhập phải dài từ \(AppConstants.minUsernameLength) đến \(AppConstants.maxUsernameLength) ký tự."
            )
        }
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
        guard normalized.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            throw LockInDomainError.invalidUsername("Tên đăng nhập chỉ chấp nhận chữ thường, số và ký tự . _ -")
        }
        return normalized
    }

    private func validatePassword(_ password: String) throws {
        guard password.count >= AppConstants.minPasswordLength else {
            throw LockInDomainError.invalidPassword(
                "Mật khẩu phải có ít nhất \(AppConstants.minPasswordLength) ký tự."
            )
        }
    }

    private static func toDTO(_ profile: UserProfile) -> UserProfileDTO {
        UserProfileDTO(
            id: profile.id,
            username: profile.username,
            displayName: profile.displayName,
            isBiometricEnabled: profile.isBiometricEnabled,
            createdAt: profile.createdAt,
            lastLoginAt: profile.lastLoginAt
        )
    }
}
