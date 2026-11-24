// EncryptedBackupService.swift — Export/Import file .lockinbackup mã hóa AES-GCM bằng khóa PBKDF2 600,000 vòng.
// Triển khai BackupModuleProtocol; ghim phiên ban đầu, giao dịch 1 lần save kèm rollback, remap UUID chéo hồ sơ và đồng bộ Lock Screen.

import Foundation
import SwiftData

private struct EncryptedBackupEnvelope: Codable {
    let schemaVersion: Int
    let pbkdf2Iterations: Int
    let saltBase64: String
    let sealedCombinedBase64: String
    let exportedAt: Date
}

private struct BackupUserDataPayload: Codable {
    let decks: [StudyDeckDTO]
    let cards: [StudyCardDTO]
    let tasks: [TaskItemDTO]
    let schedules: [StudyScheduleDTO]
    let themePreference: ThemePreferenceDTO?
    let dailyProgresses: [DailyProgressDTO]
}

public final class EncryptedBackupService: BackupModuleProtocol, @unchecked Sendable {
    private let studyStore: SwiftDataStudyStore
    private let isolationGuard: UserDataIsolationGuardProtocol
    private let crypto: PasswordCryptoServiceProtocol
    private let lockScreenService: LockScreenModuleProtocol
    private let schedulerService: SchedulerModuleProtocol
    private let snapshotStore: AppGroupSnapshotStoreProtocol
    private let syncEventBus: SyncEventBus

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    public init(
        studyStore: SwiftDataStudyStore,
        isolationGuard: UserDataIsolationGuardProtocol,
        crypto: PasswordCryptoServiceProtocol,
        lockScreenService: LockScreenModuleProtocol,
        schedulerService: SchedulerModuleProtocol,
        snapshotStore: AppGroupSnapshotStoreProtocol,
        syncEventBus: SyncEventBus
    ) {
        self.studyStore = studyStore
        self.isolationGuard = isolationGuard
        self.crypto = crypto
        self.lockScreenService = lockScreenService
        self.schedulerService = schedulerService
        self.snapshotStore = snapshotStore
        self.syncEventBus = syncEventBus
    }

    public func exportEncryptedBackup(passphrase: String) async throws -> Data {
        let userId = try isolationGuard.requireActiveUserId()
        guard passphrase.count >= AppConstants.minBackupPassphraseLength else {
            throw LockInDomainError.invalidPassword(
                "Mật khẩu sao lưu phải có ít nhất \(AppConstants.minBackupPassphraseLength) ký tự."
            )
        }

        let payload: BackupUserDataPayload = try await studyStore.perform { context in
            let uid = userId
            let decks = try context.fetch(
                FetchDescriptor<StudyDeck>(predicate: #Predicate<StudyDeck> { $0.ownerUserId == uid })
            )
            let deckDTOs = decks.map { deck in
                let owned = deck.cards.filter { $0.ownerUserId == uid }
                return StudyDeckDTO(
                    id: deck.id,
                    ownerUserId: uid,
                    title: deck.title,
                    subjectTag: deck.subjectTag,
                    accentHex: deck.accentHex,
                    examDate: deck.examDate,
                    dailyGoal: deck.dailyGoal,
                    totalCards: owned.count,
                    masteredCards: owned.filter { $0.status == .mastered }.count,
                    createdAt: deck.createdAt,
                    updatedAt: deck.updatedAt
                )
            }
            let cardDTOs = decks.flatMap { deck in
                deck.cards.filter { $0.ownerUserId == uid }.map { card in
                    StudyCardDTO(
                        id: card.id,
                        ownerUserId: uid,
                        deckId: deck.id,
                        question: card.question,
                        answer: card.answer,
                        hintOrNote: card.hintOrNote,
                        status: card.status,
                        reviewCount: card.reviewCount,
                        lastReviewedAt: card.lastReviewedAt,
                        sortOrder: card.sortOrder
                    )
                }
            }
            let taskDTOs = try context.fetch(
                FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.ownerUserId == uid })
            ).map {
                TaskItemDTO(
                    id: $0.id,
                    ownerUserId: uid,
                    title: $0.title,
                    notes: $0.notes,
                    dueDate: $0.dueDate,
                    priority: $0.priority,
                    isCompleted: $0.isCompleted,
                    completedAt: $0.completedAt,
                    linkedDeckId: $0.linkedDeckId
                )
            }
            let scheduleDTOs = try context.fetch(
                FetchDescriptor<StudySchedule>(predicate: #Predicate<StudySchedule> { $0.ownerUserId == uid })
            ).map {
                StudyScheduleDTO(
                    id: $0.id,
                    ownerUserId: uid,
                    deckId: $0.deckId,
                    title: $0.title,
                    hour: $0.hour,
                    minute: $0.minute,
                    weekdaysMask: $0.weekdaysMask,
                    isEnabled: $0.isEnabled,
                    autoRotateTheme: $0.autoRotateTheme
                )
            }
            let pref = try context.fetch(
                FetchDescriptor<ThemePreference>(predicate: #Predicate<ThemePreference> { $0.ownerUserId == uid })
            ).first.map {
                ThemePreferenceDTO(
                    id: $0.id,
                    ownerUserId: uid,
                    activeThemeId: $0.activeThemeId,
                    isShuffleEnabled: $0.isShuffleEnabled,
                    shufflePoolIds: $0.shufflePoolIds,
                    rotateOnAppOpen: $0.rotateOnAppOpen,
                    rotateOnShortcutTrigger: $0.rotateOnShortcutTrigger,
                    lockScreenFontScale: $0.fontScale,
                    hideAnswerByDefault: $0.hideAnswerByDefault,
                    privacyModeEnabled: $0.privacyModeEnabled,
                    showPopupOnOpen: $0.showPopupOnOpen
                )
            }
            let progresses = try context.fetch(
                FetchDescriptor<DailyProgress>(predicate: #Predicate<DailyProgress> { $0.ownerUserId == uid })
            ).map {
                DailyProgressDTO(
                    dateKey: $0.dateKey,
                    cardsReviewed: $0.cardsReviewed,
                    cardsMastered: $0.cardsMastered,
                    tasksCompleted: $0.tasksCompleted,
                    dailyTargetCount: $0.dailyTargetCount,
                    streakCount: $0.streakCount
                )
            }

            return BackupUserDataPayload(
                decks: deckDTOs,
                cards: cardDTOs,
                tasks: taskDTOs,
                schedules: scheduleDTOs,
                themePreference: pref,
                dailyProgresses: progresses
            )
        }

        let plaintext = try encoder.encode(payload)
        let salt = try crypto.generateRandomSalt(byteCount: AppConstants.saltByteCount)
        let key = try crypto.deriveKeyPBKDF2(
            secret: passphrase,
            salt: salt,
            iterations: AppConstants.pbkdf2Iterations,
            keyByteCount: 32
        )
        let sealedCombined = try crypto.encryptAESGCM(plaintext: plaintext, keyData: key)

        let envelope = EncryptedBackupEnvelope(
            schemaVersion: AppConstants.backupSchemaVersion,
            pbkdf2Iterations: AppConstants.pbkdf2Iterations,
            saltBase64: salt.base64EncodedString(),
            sealedCombinedBase64: sealedCombined.base64EncodedString(),
            exportedAt: Date()
        )
        return try encoder.encode(envelope)
    }

    /// Kiểm tra kích thước metadata và chỉ đọc tối đa 10 MB + 1 byte từ FileHandle trước khi nạp toàn bộ vào RAM.
    public func readBoundedBackupFile(at url: URL) throws -> Data {
        if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let fileSize = resourceValues.fileSize,
           fileSize > AppConstants.maxBackupFileBytes {
            throw LockInDomainError.backupExceedsMaxSize
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let boundedData = try handle.read(upToCount: AppConstants.maxBackupFileBytes + 1) ?? Data()
        guard boundedData.count <= AppConstants.maxBackupFileBytes else {
            throw LockInDomainError.backupExceedsMaxSize
        }
        return boundedData
    }

    public func importEncryptedBackup(_ data: Data, passphrase: String, mode: BackupRestoreMode) async throws {
        // Ghim phiên ban đầu trước khi giải mã để chặn thao tác đổi hồ sơ giữa chừng ghi nhầm sang user khác.
        let initialSession = try isolationGuard.requireActiveSession()

        guard data.count <= AppConstants.maxBackupFileBytes else {
            throw LockInDomainError.backupExceedsMaxSize
        }
        guard !passphrase.isEmpty else {
            throw LockInDomainError.backupCorruptedOrWrongPassphrase
        }

        let envelope: EncryptedBackupEnvelope
        do {
            envelope = try decoder.decode(EncryptedBackupEnvelope.self, from: data)
        } catch {
            throw LockInDomainError.backupCorruptedOrWrongPassphrase
        }

        // Schema v1 chỉ chấp nhận đúng 600,000 vòng PBKDF2 và salt đủ 16 byte để chống DoS hoặc ép kiểu ngoài miền.
        guard envelope.schemaVersion == AppConstants.backupSchemaVersion,
              envelope.pbkdf2Iterations == AppConstants.pbkdf2Iterations,
              let salt = Data(base64Encoded: envelope.saltBase64),
              salt.count == AppConstants.saltByteCount,
              let sealedCombined = Data(base64Encoded: envelope.sealedCombinedBase64),
              !sealedCombined.isEmpty else {
            throw LockInDomainError.backupCorruptedOrWrongPassphrase
        }

        let key = try crypto.deriveKeyPBKDF2(
            secret: passphrase,
            salt: salt,
            iterations: AppConstants.pbkdf2Iterations,
            keyByteCount: 32
        )
        let plaintext = try crypto.decryptAESGCM(combined: sealedCombined, keyData: key)

        let payload: BackupUserDataPayload
        do {
            payload = try decoder.decode(BackupUserDataPayload.self, from: plaintext)
        } catch {
            throw LockInDomainError.backupCorruptedOrWrongPassphrase
        }

        guard Set(payload.decks.map(\.id)).count == payload.decks.count,
              Set(payload.cards.map(\.id)).count == payload.cards.count,
              Set(payload.tasks.map(\.id)).count == payload.tasks.count,
              Set(payload.schedules.map(\.id)).count == payload.schedules.count else {
            throw LockInDomainError.backupCorruptedOrWrongPassphrase
        }

        let sessionAfterDecrypt = try isolationGuard.requireActiveSession()
        guard sessionAfterDecrypt == initialSession else {
            throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
        }

        let uid = initialSession.userId

        try await studyStore.perform { context in
            guard try isolationGuard.requireActiveSession() == initialSession else {
                throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
            }

            do {
                // Quét toàn kho trong một giao dịch duy nhất trước khi biến đổi; rollback toàn bộ nếu bất kỳ bước nào lỗi.
                let allDecks = try context.fetch(FetchDescriptor<StudyDeck>())
                let allCards = try context.fetch(FetchDescriptor<StudyCard>())
                let allTasks = try context.fetch(FetchDescriptor<TaskItem>())
                let allSchedules = try context.fetch(FetchDescriptor<StudySchedule>())
                let ownProgresses = try context.fetch(
                    FetchDescriptor<DailyProgress>(predicate: #Predicate<DailyProgress> { $0.ownerUserId == uid })
                )

                let foreignDeckIds = Set(allDecks.filter { $0.ownerUserId != uid }.map(\.id))
                let foreignCardIds = Set(allCards.filter { $0.ownerUserId != uid }.map(\.id))
                let foreignTaskIds = Set(allTasks.filter { $0.ownerUserId != uid }.map(\.id))
                let foreignScheduleIds = Set(allSchedules.filter { $0.ownerUserId != uid }.map(\.id))

                var occupiedDeckIds = Set(allDecks.map(\.id))
                var occupiedCardIds = Set(allCards.map(\.id))
                var occupiedTaskIds = Set(allTasks.map(\.id))
                var occupiedScheduleIds = Set(allSchedules.map(\.id))

                var existingOwnDeckById: [UUID: StudyDeck] = [:]
                for deck in allDecks where deck.ownerUserId == uid {
                    existingOwnDeckById[deck.id] = deck
                }
                var existingOwnCardById: [UUID: StudyCard] = [:]
                for card in allCards where card.ownerUserId == uid {
                    existingOwnCardById[card.id] = card
                }
                var existingOwnTaskById: [UUID: TaskItem] = [:]
                for task in allTasks where task.ownerUserId == uid {
                    existingOwnTaskById[task.id] = task
                }
                var existingOwnScheduleById: [UUID: StudySchedule] = [:]
                for schedule in allSchedules where schedule.ownerUserId == uid {
                    existingOwnScheduleById[schedule.id] = schedule
                }
                var existingOwnProgressByDateKey: [String: DailyProgress] = [:]
                for progress in ownProgresses {
                    existingOwnProgressByDateKey[progress.dateKey] = progress
                }

                let hasForeignCollision =
                    payload.decks.contains { foreignDeckIds.contains($0.id) } ||
                    payload.cards.contains { foreignCardIds.contains($0.id) } ||
                    payload.tasks.contains { foreignTaskIds.contains($0.id) } ||
                    payload.schedules.contains { foreignScheduleIds.contains($0.id) }

                let hasDifferentSourceOwner =
                    payload.decks.contains { $0.ownerUserId != uid } ||
                    payload.cards.contains { $0.ownerUserId != uid } ||
                    payload.tasks.contains { $0.ownerUserId != uid } ||
                    payload.schedules.contains { $0.ownerUserId != uid } ||
                    (payload.themePreference.map { $0.ownerUserId != uid } ?? false)

                let shouldRemapAllIds = hasForeignCollision || hasDifferentSourceOwner

                var deckById: [UUID: StudyDeck] = mode == .merge ? existingOwnDeckById : [:]
                var deckIdMap: [UUID: UUID] = [:]
                var retainedDeckIds: Set<UUID> = []

                for deckDTO in payload.decks {
                    let mappedDeckId = Self.allocateSafeUUID(
                        preferred: deckDTO.id,
                        forceRemap: shouldRemapAllIds,
                        foreignIds: foreignDeckIds,
                        occupiedIds: &occupiedDeckIds
                    )
                    deckIdMap[deckDTO.id] = mappedDeckId
                    retainedDeckIds.insert(mappedDeckId)

                    if let existing = existingOwnDeckById[mappedDeckId] {
                        existing.title = deckDTO.title
                        existing.subjectTag = deckDTO.subjectTag
                        existing.accentHex = deckDTO.accentHex
                        existing.examDate = deckDTO.examDate
                        existing.dailyGoal = max(1, deckDTO.dailyGoal)
                        existing.createdAt = deckDTO.createdAt
                        existing.updatedAt = deckDTO.updatedAt
                        deckById[mappedDeckId] = existing
                    } else {
                        let created = StudyDeck(
                            id: mappedDeckId,
                            ownerUserId: uid,
                            title: deckDTO.title,
                            subjectTag: deckDTO.subjectTag,
                            accentHex: deckDTO.accentHex,
                            examDate: deckDTO.examDate,
                            dailyGoal: max(1, deckDTO.dailyGoal),
                            createdAt: deckDTO.createdAt,
                            updatedAt: deckDTO.updatedAt
                        )
                        context.insert(created)
                        deckById[mappedDeckId] = created
                    }
                }

                // Xử lý thẻ trước khi xóa các bộ đề cũ không còn trong backup để tránh cascade delete xóa nhầm thẻ được giữ lại.
                var retainedCardIds: Set<UUID> = []
                for cardDTO in payload.cards {
                    let mappedCardId = Self.allocateSafeUUID(
                        preferred: cardDTO.id,
                        forceRemap: shouldRemapAllIds,
                        foreignIds: foreignCardIds,
                        occupiedIds: &occupiedCardIds
                    )
                    retainedCardIds.insert(mappedCardId)

                    let parentDeck: StudyDeck?
                    if let mappedDeckId = deckIdMap[cardDTO.deckId] {
                        parentDeck = deckById[mappedDeckId]
                    } else if !shouldRemapAllIds {
                        parentDeck = deckById[cardDTO.deckId]
                    } else {
                        parentDeck = nil
                    }

                    if let existing = existingOwnCardById[mappedCardId] {
                        if mode == .overwrite {
                            existing.deck = parentDeck
                            existing.question = cardDTO.question
                            existing.answer = cardDTO.answer
                            existing.hintOrNote = cardDTO.hintOrNote
                            existing.status = cardDTO.status
                            existing.reviewCount = cardDTO.reviewCount
                            existing.lastReviewedAt = cardDTO.lastReviewedAt
                            existing.sortOrder = cardDTO.sortOrder
                        }
                    } else {
                        let card = StudyCard(
                            id: mappedCardId,
                            ownerUserId: uid,
                            deck: parentDeck,
                            question: cardDTO.question,
                            answer: cardDTO.answer,
                            hintOrNote: cardDTO.hintOrNote,
                            status: cardDTO.status,
                            reviewCount: cardDTO.reviewCount,
                            lastReviewedAt: cardDTO.lastReviewedAt,
                            sortOrder: cardDTO.sortOrder
                        )
                        context.insert(card)
                    }
                }

                var retainedTaskIds: Set<UUID> = []
                for taskDTO in payload.tasks {
                    let mappedTaskId = Self.allocateSafeUUID(
                        preferred: taskDTO.id,
                        forceRemap: shouldRemapAllIds,
                        foreignIds: foreignTaskIds,
                        occupiedIds: &occupiedTaskIds
                    )
                    retainedTaskIds.insert(mappedTaskId)

                    let remappedLinkedDeckId: UUID?
                    if let sourceDeckId = taskDTO.linkedDeckId {
                        if let mappedDeckId = deckIdMap[sourceDeckId], deckById[mappedDeckId] != nil {
                            remappedLinkedDeckId = mappedDeckId
                        } else if !shouldRemapAllIds, deckById[sourceDeckId] != nil {
                            remappedLinkedDeckId = sourceDeckId
                        } else {
                            remappedLinkedDeckId = nil
                        }
                    } else {
                        remappedLinkedDeckId = nil
                    }

                    if let existing = existingOwnTaskById[mappedTaskId] {
                        if mode == .overwrite {
                            existing.title = taskDTO.title
                            existing.notes = taskDTO.notes
                            existing.dueDate = taskDTO.dueDate
                            existing.priority = taskDTO.priority
                            existing.isCompleted = taskDTO.isCompleted
                            existing.completedAt = taskDTO.completedAt
                            existing.linkedDeckId = remappedLinkedDeckId
                        }
                    } else {
                        let task = TaskItem(
                            id: mappedTaskId,
                            ownerUserId: uid,
                            title: taskDTO.title,
                            notes: taskDTO.notes,
                            dueDate: taskDTO.dueDate,
                            priority: taskDTO.priority,
                            isCompleted: taskDTO.isCompleted,
                            completedAt: taskDTO.completedAt,
                            linkedDeckId: remappedLinkedDeckId
                        )
                        context.insert(task)
                    }
                }

                var retainedScheduleIds: Set<UUID> = []
                for scheduleDTO in payload.schedules {
                    let mappedScheduleId = Self.allocateSafeUUID(
                        preferred: scheduleDTO.id,
                        forceRemap: shouldRemapAllIds,
                        foreignIds: foreignScheduleIds,
                        occupiedIds: &occupiedScheduleIds
                    )

                    let remappedDeckId: UUID?
                    if let mappedId = deckIdMap[scheduleDTO.deckId], deckById[mappedId] != nil {
                        remappedDeckId = mappedId
                    } else if !shouldRemapAllIds, deckById[scheduleDTO.deckId] != nil {
                        remappedDeckId = scheduleDTO.deckId
                    } else {
                        remappedDeckId = nil
                    }
                    guard let validDeckId = remappedDeckId else { continue }

                    retainedScheduleIds.insert(mappedScheduleId)

                    if let existing = existingOwnScheduleById[mappedScheduleId] {
                        if mode == .overwrite {
                            existing.deckId = validDeckId
                            existing.title = scheduleDTO.title
                            existing.hour = scheduleDTO.hour
                            existing.minute = scheduleDTO.minute
                            existing.weekdaysMask = scheduleDTO.weekdaysMask
                            existing.isEnabled = scheduleDTO.isEnabled
                            existing.autoRotateTheme = scheduleDTO.autoRotateTheme
                        }
                    } else {
                        let schedule = StudySchedule(
                            id: mappedScheduleId,
                            ownerUserId: uid,
                            deckId: validDeckId,
                            title: scheduleDTO.title,
                            hour: scheduleDTO.hour,
                            minute: scheduleDTO.minute,
                            weekdaysMask: scheduleDTO.weekdaysMask,
                            isEnabled: scheduleDTO.isEnabled,
                            autoRotateTheme: scheduleDTO.autoRotateTheme
                        )
                        context.insert(schedule)
                    }
                }

                if let restoredPref = payload.themePreference {
                    let pref = try ThemeCatalogService.fetchOrCreatePreference(for: uid, in: context)
                    let validThemeIds = Set(ThemePalette.allBuiltIn.map(\.id))
                    let sanitizedPool = restoredPref.shufflePoolIds.filter { validThemeIds.contains($0) }
                    pref.activeThemeId = ThemePalette.palette(for: restoredPref.activeThemeId).id
                    pref.isShuffleEnabled = restoredPref.isShuffleEnabled
                    pref.shufflePoolIds = sanitizedPool.isEmpty ? [pref.activeThemeId] : sanitizedPool
                    pref.rotateOnAppOpen = restoredPref.rotateOnAppOpen
                    pref.rotateOnShortcutTrigger = restoredPref.rotateOnShortcutTrigger
                    pref.fontScale = restoredPref.lockScreenFontScale
                    pref.hideAnswerByDefault = restoredPref.hideAnswerByDefault
                    pref.privacyModeEnabled = restoredPref.privacyModeEnabled
                    pref.showPopupOnOpen = restoredPref.showPopupOnOpen
                }

                var retainedProgressKeys: Set<String> = []
                for progressDTO in payload.dailyProgresses {
                    guard !retainedProgressKeys.contains(progressDTO.dateKey) else { continue }
                    retainedProgressKeys.insert(progressDTO.dateKey)

                    if let existing = existingOwnProgressByDateKey[progressDTO.dateKey] {
                        if mode == .overwrite {
                            existing.cardsReviewed = progressDTO.cardsReviewed
                            existing.cardsMastered = progressDTO.cardsMastered
                            existing.tasksCompleted = progressDTO.tasksCompleted
                            existing.dailyTargetCount = progressDTO.dailyTargetCount
                            existing.streakCount = progressDTO.streakCount
                        }
                    } else {
                        let progress = DailyProgress(
                            ownerUserId: uid,
                            dateKey: progressDTO.dateKey,
                            cardsReviewed: progressDTO.cardsReviewed,
                            cardsMastered: progressDTO.cardsMastered,
                            tasksCompleted: progressDTO.tasksCompleted,
                            dailyTargetCount: progressDTO.dailyTargetCount,
                            streakCount: progressDTO.streakCount
                        )
                        context.insert(progress)
                    }
                }

                if mode == .overwrite {
                    for card in existingOwnCardById.values where !retainedCardIds.contains(card.id) {
                        context.delete(card)
                    }
                    for deck in existingOwnDeckById.values where !retainedDeckIds.contains(deck.id) {
                        context.delete(deck)
                    }
                    for task in existingOwnTaskById.values where !retainedTaskIds.contains(task.id) {
                        context.delete(task)
                    }
                    for schedule in existingOwnScheduleById.values where !retainedScheduleIds.contains(schedule.id) {
                        context.delete(schedule)
                    }
                    for progress in ownProgresses where !retainedProgressKeys.contains(progress.dateKey) {
                        context.delete(progress)
                    }
                }

                guard try isolationGuard.requireActiveSession() == initialSession else {
                    throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
                }
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }

        guard try isolationGuard.requireActiveSession() == initialSession else {
            throw AppGroupStorageError.sessionInvalidatedOrLoggedOut
        }

        // Dựng lại toàn bộ LockScreenSnapshot, cập nhật/kết thúc Live Activity và đồng bộ lịch thông báo sau import.
        try await lockScreenService.syncSnapshotFromStore()
        try await schedulerService.syncLocalNotifications()

        let latestSnapshot = try snapshotStore.loadSnapshot()
        let marker = SnapshotStateMarker(
            version: latestSnapshot.snapshotVersion,
            revisionId: latestSnapshot.snapshotRevisionId
        )
        await MainActor.run {
            syncEventBus.publish(.cardsChanged(deckId: nil), observedMarker: marker)
            syncEventBus.publish(.tasksChanged)
            syncEventBus.publish(.progressUpdated)
            syncEventBus.publish(.themeRotated(themeId: latestSnapshot.activeThemeId))
        }
    }

    private static func allocateSafeUUID(
        preferred: UUID,
        forceRemap: Bool,
        foreignIds: Set<UUID>,
        occupiedIds: inout Set<UUID>
    ) -> UUID {
        if !forceRemap && !foreignIds.contains(preferred) {
            occupiedIds.insert(preferred)
            return preferred
        }
        var candidate = UUID()
        while occupiedIds.contains(candidate) {
            candidate = UUID()
        }
        occupiedIds.insert(candidate)
        return candidate
    }
}
