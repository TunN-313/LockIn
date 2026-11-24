// StudyScheduleServiceTests.swift — Kiểm thử tạo/sửa/xóa lịch ôn tập, tính mốc tiếp theo và đồng bộ thông báo cục bộ.
// Thuộc LockInTests (M4b); dùng InMemoryLocalNotificationService để xác minh resync và hủy thông báo theo từng ngày lặp.

import XCTest
@testable import LockInApp

final class StudyScheduleServiceTests: XCTestCase {
    @MainActor
    func testScheduleValidationCrudAndNotificationResync() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "SchedulerPass#2026"

        _ = try await env.container.auth.register(
            username: "schedule_owner",
            displayName: "Schedule Owner",
            password: userCredential
        )
        let deck = try await env.container.study.createDeck(
            title: "Japanese N3",
            subjectTag: "Language",
            accentHex: "#2563EB",
            examDate: nil,
            dailyGoal: 20
        )

        do {
            _ = try await env.container.scheduler.saveSchedule(
                scheduleId: nil,
                deckId: deck.id,
                title: "Lịch sai giờ",
                hour: 24,
                minute: 0,
                weekdaysMask: 0b0000010,
                isEnabled: true,
                autoRotateTheme: false
            )
            XCTFail("Giờ = 24 phải bị từ chối.")
        } catch let error as LockInDomainError {
            guard case .validationFailed = error else {
                return XCTFail("Kỳ vọng validationFailed, nhận: \(error)")
            }
        }

        do {
            _ = try await env.container.scheduler.saveSchedule(
                scheduleId: nil,
                deckId: deck.id,
                title: "Không chọn ngày",
                hour: 9,
                minute: 30,
                weekdaysMask: 0,
                isEnabled: true,
                autoRotateTheme: false
            )
            XCTFail("weekdaysMask = 0 phải bị từ chối.")
        } catch let error as LockInDomainError {
            guard case .validationFailed = error else {
                return XCTFail("Kỳ vọng validationFailed, nhận: \(error)")
            }
        }

        do {
            _ = try await env.container.scheduler.saveSchedule(
                scheduleId: nil,
                deckId: UUID(),
                title: "Deck không tồn tại",
                hour: 9,
                minute: 30,
                weekdaysMask: 0b0000111,
                isEnabled: true,
                autoRotateTheme: false
            )
            XCTFail("Bộ đề không tồn tại phải ném entityNotFound.")
        } catch let error as LockInDomainError {
            XCTAssertEqual(error, .entityNotFound)
        }

        // Tạo lịch bật trên 3 ngày trong tuần (bitmask = 0b0101010 -> 3 pending identifiers).
        let created = try await env.container.scheduler.saveSchedule(
            scheduleId: nil,
            deckId: deck.id,
            title: "Ôn Kanji tối",
            hour: 21,
            minute: 0,
            weekdaysMask: 0b0101010,
            isEnabled: true,
            autoRotateTheme: true
        )
        XCTAssertEqual(env.notificationService.pendingIdentifiers.count, 3)

        let fetched = try await env.container.scheduler.fetchSchedules()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, created.id)

        // Tắt lịch -> xóa toàn bộ pending notification cho lịch đó.
        _ = try await env.container.scheduler.saveSchedule(
            scheduleId: created.id,
            deckId: deck.id,
            title: "Ôn Kanji tối (Tạm tắt)",
            hour: 21,
            minute: 0,
            weekdaysMask: 0b0101010,
            isEnabled: false,
            autoRotateTheme: true
        )
        XCTAssertTrue(env.notificationService.pendingIdentifiers.isEmpty)

        // Bật lại 2 ngày rồi xóa lịch -> cũng phải sạch pending notifications.
        _ = try await env.container.scheduler.saveSchedule(
            scheduleId: created.id,
            deckId: deck.id,
            title: "Ôn Kanji tối",
            hour: 21,
            minute: 15,
            weekdaysMask: 0b0000011,
            isEnabled: true,
            autoRotateTheme: false
        )
        XCTAssertEqual(env.notificationService.pendingIdentifiers.count, 2)

        let resyncCallsBeforeDelete = env.notificationService.resyncCallCount
        let cancelCallsBeforeDelete = env.notificationService.cancelAllCallCount
        try await env.container.scheduler.deleteSchedule(scheduleId: created.id)
        let schedulesAfterDelete = try await env.container.scheduler.fetchSchedules()
        XCTAssertTrue(schedulesAfterDelete.isEmpty)
        XCTAssertTrue(env.notificationService.pendingIdentifiers.isEmpty)
        XCTAssertGreaterThan(env.notificationService.resyncCallCount, resyncCallsBeforeDelete)
        XCTAssertEqual(env.notificationService.cancelAllCallCount, cancelCallsBeforeDelete)
    }

    @MainActor
    func testNextScheduledDateCalculationSameDayWrapAroundAndDisabled() throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let reference10AM = try XCTUnwrap(
            calendar.date(bySettingHour: 10, minute: 0, second: 0, of: todayStart)
        )
        let weekday = calendar.component(.weekday, from: reference10AM)
        let todayBitMask = 1 << (weekday - 1)
        let dummyOwner = UUID()
        let dummyDeck = UUID()

        let laterTodaySchedule = StudyScheduleDTO(
            id: UUID(),
            ownerUserId: dummyOwner,
            deckId: dummyDeck,
            title: "Chiều nay",
            hour: 18,
            minute: 30,
            weekdaysMask: todayBitMask,
            isEnabled: true,
            autoRotateTheme: false
        )
        let expectedSameDay = try XCTUnwrap(
            calendar.date(bySettingHour: 18, minute: 30, second: 0, of: todayStart)
        )
        XCTAssertEqual(
            env.container.scheduler.nextScheduledDate(for: laterTodaySchedule, after: reference10AM),
            expectedSameDay
        )

        let alreadyPassedTodaySchedule = StudyScheduleDTO(
            id: UUID(),
            ownerUserId: dummyOwner,
            deckId: dummyDeck,
            title: "Sáng tuần sau",
            hour: 8,
            minute: 15,
            weekdaysMask: todayBitMask,
            isEnabled: true,
            autoRotateTheme: false
        )
        let nextWeekDayStart = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: todayStart))
        let expectedNextWeek = try XCTUnwrap(
            calendar.date(bySettingHour: 8, minute: 15, second: 0, of: nextWeekDayStart)
        )
        XCTAssertEqual(
            env.container.scheduler.nextScheduledDate(for: alreadyPassedTodaySchedule, after: reference10AM),
            expectedNextWeek
        )

        let disabledSchedule = StudyScheduleDTO(
            id: UUID(),
            ownerUserId: dummyOwner,
            deckId: dummyDeck,
            title: "Đã tắt",
            hour: 18,
            minute: 30,
            weekdaysMask: todayBitMask,
            isEnabled: false,
            autoRotateTheme: false
        )
        XCTAssertNil(env.container.scheduler.nextScheduledDate(for: disabledSchedule, after: reference10AM))
    }

    @MainActor
    func testReminderFrequencyAndSnoozeNotifications() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "FreqOwner#2026"

        _ = try await env.container.auth.register(
            username: "freq_tester",
            displayName: "Freq Tester",
            password: userCredential
        )
        let deck = try await env.container.study.createDeck(
            title: "Periodic Study",
            subjectTag: "CS",
            accentHex: "#2563EB",
            examDate: nil,
            dailyGoal: 10
        )

        env.notificationService.authorized = false
        do {
            _ = try await env.container.scheduler.updateReminderFrequency(.daily)
            XCTFail("Không có quyền thông báo phải bị từ chối.")
        } catch let error as LockInDomainError {
            guard case .validationFailed = error else {
                return XCTFail("Kỳ vọng validationFailed, nhận: \(error)")
            }
        }

        do {
            _ = try await env.container.scheduler.scheduleSnoozeReminder(afterMinutes: 30, suggestedDeckTitle: deck.title)
            XCTFail("Hẹn nhắc lại khi chưa có quyền thông báo phải bị từ chối.")
        } catch let error as LockInDomainError {
            guard case .validationFailed = error else {
                return XCTFail("Kỳ vọng validationFailed, nhận: \(error)")
            }
        }

        env.notificationService.authorized = true
        let updated = try await env.container.scheduler.updateReminderFrequency(.twiceDaily)
        XCTAssertEqual(updated, .twiceDaily)
        let fetched = try await env.container.scheduler.fetchReminderFrequency()
        XCTAssertEqual(fetched, .twiceDaily)
        XCTAssertEqual(env.notificationService.pendingIdentifiers.count, 2)

        let cleared = try await env.container.scheduler.updateReminderFrequency(.off)
        XCTAssertEqual(cleared, .off)
        XCTAssertTrue(env.notificationService.pendingIdentifiers.isEmpty)

        let snoozeDate = try await env.container.scheduler.scheduleSnoozeReminder(
            afterMinutes: 30,
            suggestedDeckTitle: deck.title
        )
        XCTAssertGreaterThan(snoozeDate, Date())
        XCTAssertEqual(env.notificationService.snoozeIdentifiers.count, 1)

        do {
            _ = try await env.container.scheduler.scheduleSnoozeReminder(afterMinutes: 2, suggestedDeckTitle: deck.title)
            XCTFail("Thời gian snooze dưới 5 phút phải bị từ chối.")
        } catch let error as LockInDomainError {
            guard case .validationFailed = error else {
                return XCTFail("Kỳ vọng validationFailed, nhận: \(error)")
            }
        }
    }

    @MainActor
    func testDueScheduleActivationAutoRotateThemeOncePerDayAndReminderSuggestion() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let userCredential = "AutoRotateOwner#2026"

        _ = try await env.container.auth.register(
            username: "auto_rotate_sched",
            displayName: "Auto Rotate",
            password: userCredential
        )
        _ = try await env.container.theme.updateShuffleConfiguration(
            isEnabled: false,
            poolIds: [ThemePalette.minimalPaper.id, ThemePalette.midnightInk.id],
            rotateOnAppOpen: false,
            rotateOnShortcutTrigger: true
        )

        let deckA = try await env.container.study.createDeck(
            title: "General Deck",
            subjectTag: "Misc",
            accentHex: "#2563EB",
            examDate: Date().addingTimeInterval(86_400),
            dailyGoal: 10
        )
        let deckB = try await env.container.study.createDeck(
            title: "Scheduled Priority Deck",
            subjectTag: "OS",
            accentHex: "#16A34A",
            examDate: nil,
            dailyGoal: 10
        )
        _ = try await env.container.study.upsertCard(
            cardId: nil,
            deckId: deckB.id,
            question: "What is Mutex?",
            answer: "Mutual exclusion primitive",
            hintOrNote: "",
            status: .new
        )

        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .weekday], from: now)
        let todayBit = 1 << ((comps.weekday ?? 1) - 1)
        let hour = comps.hour ?? 10
        let minute = comps.minute ?? 0
        guard let scheduleTimestamp = cal.date(bySettingHour: hour, minute: minute, second: 0, of: cal.startOfDay(for: now)) else {
            return XCTFail("Không tạo được mốc thời gian lịch.")
        }
        let checkDate = scheduleTimestamp.addingTimeInterval(5)

        let dueSchedule = try await env.container.scheduler.saveSchedule(
            scheduleId: nil,
            deckId: deckB.id,
            title: "Phiên ôn ưu tiên",
            hour: hour,
            minute: minute,
            weekdaysMask: todayBit,
            isEnabled: true,
            autoRotateTheme: true
        )

        let summary = try await env.container.study.fetchPendingReminderSummary()
        XCTAssertEqual(summary.suggestedDeckId, deckB.id)
        XCTAssertEqual(summary.suggestedDeckTitle, "Scheduled Priority Deck")

        let applied = try await env.container.scheduler.applyDueScheduleIfNeeded(at: checkDate)
        let result = try XCTUnwrap(applied)
        XCTAssertEqual(result.schedule.id, dueSchedule.id)
        XCTAssertEqual(result.prioritizedDeckId, deckB.id)
        XCTAssertTrue(result.didRotateTheme)
        XCTAssertEqual(result.activeThemeId, ThemePalette.midnightInk.id)

        let snapshot = try env.snapshotStore.loadSnapshot()
        XCTAssertEqual(snapshot.activeDeckId, deckB.id)
        XCTAssertEqual(snapshot.activeThemeId, ThemePalette.midnightInk.id)

        // Gọi lại lần hai trong cùng ngày không được xoay theme hoặc áp dụng lặp lại.
        let secondApply = try await env.container.scheduler.applyDueScheduleIfNeeded(at: checkDate.addingTimeInterval(60))
        XCTAssertNil(secondApply)

        // Kích hoạt thủ công một lịch có autoRotateTheme = false -> ưu tiên bộ đề nhưng giữ nguyên theme.
        let manualSchedule = try await env.container.scheduler.saveSchedule(
            scheduleId: nil,
            deckId: deckA.id,
            title: "Ôn thủ công không đổi theme",
            hour: hour,
            minute: minute,
            weekdaysMask: todayBit,
            isEnabled: false,
            autoRotateTheme: false
        )
        let manualResult = try await env.container.scheduler.activateScheduledSession(scheduleId: manualSchedule.id)
        XCTAssertEqual(manualResult.prioritizedDeckId, deckA.id)
        XCTAssertFalse(manualResult.didRotateTheme)
        XCTAssertEqual(manualResult.activeThemeId, ThemePalette.midnightInk.id)
        let snapshotAfterManual = try env.snapshotStore.loadSnapshot()
        XCTAssertEqual(snapshotAfterManual.activeDeckId, deckA.id)
    }

    @MainActor
    func testSnoozeSurvivesSameProfileResyncAndClearsOnLogoutOrProfileSwitch() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let credential = "SnoozeOwner#2026"

        let userA = try await env.container.auth.register(
            username: "snooze_user_a",
            displayName: "Snooze User A",
            password: credential
        )
        let deckA = try await env.container.study.createDeck(
            title: "Snooze Deck A",
            subjectTag: "Math",
            accentHex: "#2563EB",
            examDate: nil,
            dailyGoal: 10
        )

        _ = try await env.container.scheduler.scheduleSnoozeReminder(
            afterMinutes: 30,
            suggestedDeckTitle: deckA.title
        )
        let expectedSnoozeId = "\(LocalNotificationService.snoozeReminderPrefix)\(userA.id.uuidString)"
        XCTAssertEqual(env.notificationService.snoozeIdentifiers, [expectedSnoozeId])

        // Lưu lịch học mới và đổi tần suất nhắc trên cùng hồ sơ -> snooze vẫn phải được giữ nguyên.
        _ = try await env.container.scheduler.saveSchedule(
            scheduleId: nil,
            deckId: deckA.id,
            title: "Lịch tối cùng hồ sơ",
            hour: 21,
            minute: 0,
            weekdaysMask: 0b0000100,
            isEnabled: true,
            autoRotateTheme: false
        )
        XCTAssertEqual(env.notificationService.snoozeIdentifiers, [expectedSnoozeId])

        _ = try await env.container.scheduler.updateReminderFrequency(.daily)
        XCTAssertEqual(env.notificationService.snoozeIdentifiers, [expectedSnoozeId])

        // Hẹn snooze mới -> thay thế đúng một lượt snooze cho hồ sơ đó.
        _ = try await env.container.scheduler.scheduleSnoozeReminder(
            afterMinutes: 45,
            suggestedDeckTitle: deckA.title
        )
        XCTAssertEqual(env.notificationService.snoozeIdentifiers, [expectedSnoozeId])

        // Đăng xuất -> xóa sạch snooze.
        try await env.container.auth.logout()
        XCTAssertTrue(env.notificationService.snoozeIdentifiers.isEmpty)

        // Chuyển hồ sơ từ A sang B -> xóa sạch snooze của hồ sơ A.
        let userB = try await env.container.auth.register(
            username: "snooze_user_b",
            displayName: "Snooze User B",
            password: credential
        )
        _ = try await env.container.auth.switchProfile(userId: userA.id, password: credential)
        _ = try await env.container.scheduler.scheduleSnoozeReminder(
            afterMinutes: 20,
            suggestedDeckTitle: deckA.title
        )
        XCTAssertEqual(env.notificationService.snoozeIdentifiers, [expectedSnoozeId])

        _ = try await env.container.auth.switchProfile(userId: userB.id, password: credential)
        XCTAssertTrue(env.notificationService.snoozeIdentifiers.isEmpty)
    }

    @MainActor
    func testMidnightWrapAroundDueScheduleWindowAndNoDoubleApply() async throws {
        let cal = Calendar.current
        let dayD = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12, minute: 0)))
        let dayD2345 = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23, minute: 45)))
        let dayDPlus10015 = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 0, minute: 15)))
        let dayDPlus10030 = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 0, minute: 30)))
        let dayDPlus10145 = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 1, minute: 45)))
        let dayDBit = 1 << (cal.component(.weekday, from: dayD) - 1)

        // Kịch bản 1: Mở app lúc 23:45 ngày D rồi mở lại lúc 00:15 ngày D+1 -> chỉ kích hoạt 1 lần, không lặp qua nửa đêm.
        do {
            let env = try LockInTestEnvironment()
            defer { env.cleanup() }
            let credential = "MidnightPass#2026"

            _ = try await env.container.auth.register(
                username: "midnight_no_dup",
                displayName: "Midnight No Dup",
                password: credential
            )
            _ = try await env.container.theme.updateShuffleConfiguration(
                isEnabled: false,
                poolIds: [ThemePalette.minimalPaper.id, ThemePalette.midnightInk.id],
                rotateOnAppOpen: false,
                rotateOnShortcutTrigger: true
            )
            let deck = try await env.container.study.createDeck(
                title: "Late Night Deck",
                subjectTag: "Review",
                accentHex: "#2563EB",
                examDate: nil,
                dailyGoal: 10
            )
            _ = try await env.container.study.upsertCard(
                cardId: nil,
                deckId: deck.id,
                question: "Late Q",
                answer: "Late A",
                hintOrNote: "",
                status: .new
            )
            let schedule = try await env.container.scheduler.saveSchedule(
                scheduleId: nil,
                deckId: deck.id,
                title: "Ôn khuya 23:30",
                hour: 23,
                minute: 30,
                weekdaysMask: dayDBit,
                isEnabled: true,
                autoRotateTheme: true
            )

            let activeAt0015 = try await env.container.scheduler.activeOrDueSchedule(at: dayDPlus10015)
            XCTAssertEqual(activeAt0015?.id, schedule.id)

            let expiredAt0145 = try await env.container.scheduler.activeOrDueSchedule(at: dayDPlus10145)
            XCTAssertNil(expiredAt0145)

            let firstApply = try await env.container.scheduler.applyDueScheduleIfNeeded(at: dayD2345)
            XCTAssertEqual(firstApply?.prioritizedDeckId, deck.id)
            XCTAssertEqual(firstApply?.didRotateTheme, true)

            let secondApplyAfterMidnight = try await env.container.scheduler.applyDueScheduleIfNeeded(at: dayDPlus10015)
            XCTAssertNil(secondApplyAfterMidnight)
        }

        // Kịch bản 2: Bỏ qua lúc 23:45 và chỉ mới mở app lúc 00:15 ngày D+1 -> vẫn nhận diện lịch 23:30 hôm qua trong cửa sổ 2 giờ.
        do {
            let env = try LockInTestEnvironment()
            defer { env.cleanup() }
            let credential = "MidnightCross#2026"

            _ = try await env.container.auth.register(
                username: "midnight_cross_open",
                displayName: "Midnight Cross",
                password: credential
            )
            _ = try await env.container.theme.updateShuffleConfiguration(
                isEnabled: false,
                poolIds: [ThemePalette.minimalPaper.id, ThemePalette.midnightInk.id],
                rotateOnAppOpen: false,
                rotateOnShortcutTrigger: true
            )
            let deck = try await env.container.study.createDeck(
                title: "Cross Midnight Deck",
                subjectTag: "Exam",
                accentHex: "#16A34A",
                examDate: nil,
                dailyGoal: 10
            )
            _ = try await env.container.study.upsertCard(
                cardId: nil,
                deckId: deck.id,
                question: "Cross Q",
                answer: "Cross A",
                hintOrNote: "",
                status: .new
            )
            _ = try await env.container.scheduler.saveSchedule(
                scheduleId: nil,
                deckId: deck.id,
                title: "Ôn khuya hôm trước",
                hour: 23,
                minute: 30,
                weekdaysMask: dayDBit,
                isEnabled: true,
                autoRotateTheme: true
            )

            let appliedAcrossMidnight = try await env.container.scheduler.applyDueScheduleIfNeeded(at: dayDPlus10015)
            let result = try XCTUnwrap(appliedAcrossMidnight)
            XCTAssertEqual(result.prioritizedDeckId, deck.id)
            XCTAssertTrue(result.didRotateTheme)
            XCTAssertEqual(result.activeThemeId, ThemePalette.midnightInk.id)

            let snap = try env.snapshotStore.loadSnapshot()
            XCTAssertEqual(snap.activeDeckId, deck.id)
            XCTAssertEqual(snap.activeThemeId, ThemePalette.midnightInk.id)

            let duplicateCheck = try await env.container.scheduler.applyDueScheduleIfNeeded(at: dayDPlus10030)
            XCTAssertNil(duplicateCheck)
        }
    }

    @MainActor
    func testActivateScheduledSessionPreservesLivePrivacyModeAndFontScale() async throws {
        let env = try LockInTestEnvironment()
        defer { env.cleanup() }
        let credential = "PrivacySchedule#2026"

        let user = try await env.container.auth.register(
            username: "privacy_schedule_user",
            displayName: "Privacy Owner",
            password: credential
        )
        _ = try await env.container.theme.updateShuffleConfiguration(
            isEnabled: false,
            poolIds: [ThemePalette.minimalPaper.id, ThemePalette.midnightInk.id],
            rotateOnAppOpen: false,
            rotateOnShortcutTrigger: true
        )
        // Bảo đảm ThemePreference ban đầu đang tắt Privacy Mode và cỡ chữ standard.
        _ = try await env.container.theme.updateLockScreenDisplayOptions(
            fontScale: .standard,
            hideAnswerByDefault: true,
            privacyModeEnabled: false,
            showPopupOnOpen: true
        )

        let deck = try await env.container.study.createDeck(
            title: "Confidential Deck",
            subjectTag: "Law",
            accentHex: "#2563EB",
            examDate: nil,
            dailyGoal: 10
        )
        _ = try await env.container.study.upsertCard(
            cardId: nil,
            deckId: deck.id,
            question: "Secret Clause",
            answer: "Protected Answer",
            hintOrNote: "",
            status: .new
        )
        let schedule = try await env.container.scheduler.saveSchedule(
            scheduleId: nil,
            deckId: deck.id,
            title: "Ôn bảo mật",
            hour: 20,
            minute: 0,
            weekdaysMask: 0b1111111,
            isEnabled: true,
            autoRotateTheme: true
        )

        // Mô phỏng người dùng vừa bật Privacy Mode + Large font trong snapshot mới nhất.
        let beforeSnap = try env.snapshotStore.loadSnapshot()
        let epoch = try XCTUnwrap(beforeSnap.sessionEpoch)
        _ = try env.snapshotStore.mutateSnapshotIfSessionMatches(
            expectedUserId: user.id,
            expectedSessionEpoch: epoch
        ) { state in
            state.privacyModeEnabled = true
            state.fontScaleRaw = LockScreenFontScale.large.rawValue
        }

        let activation = try await env.container.scheduler.activateScheduledSession(scheduleId: schedule.id)
        XCTAssertEqual(activation.prioritizedDeckId, deck.id)
        XCTAssertTrue(activation.didRotateTheme)
        XCTAssertEqual(activation.activeThemeId, ThemePalette.midnightInk.id)

        let afterSnap = try env.snapshotStore.loadSnapshot()
        XCTAssertEqual(afterSnap.activeDeckId, deck.id)
        XCTAssertEqual(afterSnap.activeThemeId, ThemePalette.midnightInk.id)
        XCTAssertTrue(afterSnap.privacyModeEnabled)
        XCTAssertEqual(afterSnap.fontScaleRaw, LockScreenFontScale.large.rawValue)
    }

    @MainActor
    func testActivateScheduledSessionCoordinatesSwiftDataAndSnapshotUnderRevisionConflictAndConcurrency() async throws {
        // Phần 1: Tiêm xung đột revision đúng lúc activateScheduledSession sắp ghi snapshot -> phải rollback bản stale,
        // thử lại trên revision mới và giữ cho SwiftData ThemePreference.activeThemeId khớp 100% với snapshot.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LockInConflictTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let modelContainer = try SharedStoreContainer.makeInMemoryForTesting()
        let baseStore = try AppGroupSnapshotStore.makeForTesting(directoryURL: tempDir)
        let injectingStore = ConcurrentRevisionInjectingSnapshotStore(base: baseStore)
        let container = DependencyContainer.makeForTesting(
            modelContainer: modelContainer,
            snapshotStore: injectingStore,
            keychain: InMemoryKeychainStorage(),
            notificationService: InMemoryLocalNotificationService(),
            enableDarwinObserver: false,
            settingsDirectoryURL: tempDir
        )

        let credential = "AtomicConflict#2026"
        let user = try await container.auth.register(
            username: "atomic_conflict_user",
            displayName: "Atomic Conflict User",
            password: credential
        )
        _ = try await container.theme.updateShuffleConfiguration(
            isEnabled: false,
            poolIds: [ThemePalette.minimalPaper.id, ThemePalette.darkFocus.id],
            rotateOnAppOpen: false,
            rotateOnShortcutTrigger: false
        )
        let deck = try await container.study.createDeck(
            title: "Concurrency Deck",
            subjectTag: "Systems",
            accentHex: "#2563EB",
            examDate: nil,
            dailyGoal: 10
        )
        _ = try await container.study.upsertCard(
            cardId: nil,
            deckId: deck.id,
            question: "Atomic Q",
            answer: "Atomic A",
            hintOrNote: "",
            status: .new
        )
        let schedule = try await container.scheduler.saveSchedule(
            scheduleId: nil,
            deckId: deck.id,
            title: "Lịch tranh chấp",
            hour: 19,
            minute: 0,
            weekdaysMask: 0b1111111,
            isEnabled: true,
            autoRotateTheme: true
        )

        let snapBefore = try baseStore.loadSnapshot()
        let epoch = try XCTUnwrap(snapBefore.sessionEpoch)
        injectingStore.armOneShotBeforeRevisionCheck {
            _ = try baseStore.mutateSnapshotIfSessionMatches(
                expectedUserId: user.id,
                expectedSessionEpoch: epoch
            ) { state in
                state.activeThemeId = ThemePalette.darkFocus.id
                state.privacyModeEnabled = true
            }
        }

        // Lần thử 1 thấy minimalPaper -> định xoay sang darkFocus nhưng gặp staleSnapshotRevision;
        // lần thử 2 đọc snapshot mới nhất (đang là darkFocus) -> xoay về minimalPaper và giữ Privacy Mode.
        let conflictActivation = try await container.scheduler.activateScheduledSession(scheduleId: schedule.id)
        XCTAssertEqual(conflictActivation.activeThemeId, ThemePalette.minimalPaper.id)
        let snapAfterConflict = try baseStore.loadSnapshot()
        let prefAfterConflict = try await container.theme.fetchPreference()
        XCTAssertEqual(snapAfterConflict.activeThemeId, ThemePalette.minimalPaper.id)
        XCTAssertEqual(prefAfterConflict.activeThemeId, snapAfterConflict.activeThemeId)
        XCTAssertTrue(snapAfterConflict.privacyModeEnabled)

        // Phần 2: Chạy song song activateScheduledSession và selectTheme nhiều vòng -> SwiftData và snapshot luôn đồng bộ.
        let raceEnv = try LockInTestEnvironment()
        defer { raceEnv.cleanup() }
        _ = try await raceEnv.container.auth.register(
            username: "atomic_race_user",
            displayName: "Atomic Race User",
            password: credential
        )
        _ = try await raceEnv.container.theme.updateShuffleConfiguration(
            isEnabled: true,
            poolIds: [ThemePalette.minimalPaper.id, ThemePalette.darkFocus.id, ThemePalette.midnightInk.id],
            rotateOnAppOpen: false,
            rotateOnShortcutTrigger: true
        )
        let raceDeck = try await raceEnv.container.study.createDeck(
            title: "Race Deck",
            subjectTag: "OS",
            accentHex: "#16A34A",
            examDate: nil,
            dailyGoal: 10
        )
        _ = try await raceEnv.container.study.upsertCard(
            cardId: nil,
            deckId: raceDeck.id,
            question: "Race Q",
            answer: "Race A",
            hintOrNote: "",
            status: .new
        )
        let raceSchedule = try await raceEnv.container.scheduler.saveSchedule(
            scheduleId: nil,
            deckId: raceDeck.id,
            title: "Lịch song song",
            hour: 21,
            minute: 0,
            weekdaysMask: 0b1111111,
            isEnabled: true,
            autoRotateTheme: true
        )

        let schedulerService = raceEnv.container.scheduler
        let themeService = raceEnv.container.theme
        let scheduleId = raceSchedule.id
        let chosenThemes = [
            ThemePalette.warmSand.id,
            ThemePalette.pastelMatcha.id,
            ThemePalette.examHighContrast.id,
            ThemePalette.midnightInk.id,
            ThemePalette.darkFocus.id,
            ThemePalette.minimalPaper.id
        ]

        for chosenTheme in chosenThemes {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = try await schedulerService.activateScheduledSession(scheduleId: scheduleId)
                }
                group.addTask {
                    _ = try await themeService.selectTheme(themeId: chosenTheme)
                }
                try await group.waitForAll()
            }

            let snap = try raceEnv.snapshotStore.loadSnapshot()
            let pref = try await raceEnv.container.theme.fetchPreference()
            XCTAssertEqual(snap.activeThemeId, pref.activeThemeId)
        }
    }
}

private final class ConcurrentRevisionInjectingSnapshotStore: AppGroupSnapshotStoreProtocol, @unchecked Sendable {
    private let base: AppGroupSnapshotStore
    private let lock = NSLock()
    private var oneShotHook: (@Sendable () throws -> Void)?

    init(base: AppGroupSnapshotStore) {
        self.base = base
    }

    func armOneShotBeforeRevisionCheck(_ hook: @escaping @Sendable () throws -> Void) {
        lock.lock()
        defer { lock.unlock() }
        oneShotHook = hook
    }

    func loadSnapshot() throws -> LockScreenSnapshot {
        try base.loadSnapshot()
    }

    func currentStateMarker() throws -> SnapshotStateMarker {
        try base.currentStateMarker()
    }

    @discardableResult
    func beginSession(userId: UUID) throws -> LockScreenSnapshot {
        try base.beginSession(userId: userId)
    }

    @discardableResult
    func saveSnapshotIfSessionMatches(
        _ snapshot: LockScreenSnapshot,
        expectedUserId: UUID,
        expectedSessionEpoch: UUID,
        expectedRevisionId: UUID
    ) throws -> LockScreenSnapshot {
        try base.saveSnapshotIfSessionMatches(
            snapshot,
            expectedUserId: expectedUserId,
            expectedSessionEpoch: expectedSessionEpoch,
            expectedRevisionId: expectedRevisionId
        )
    }

    @discardableResult
    func mutateSnapshotIfSessionMatches(
        expectedUserId: UUID,
        expectedSessionEpoch: UUID,
        expectedRevisionId: UUID?,
        _ transform: (inout LockScreenSnapshot) throws -> Void
    ) throws -> LockScreenSnapshot {
        if expectedRevisionId != nil {
            let hookToRun: (@Sendable () throws -> Void)? = {
                lock.lock()
                defer { lock.unlock() }
                let hook = oneShotHook
                oneShotHook = nil
                return hook
            }()
            try hookToRun?()
        }
        return try base.mutateSnapshotIfSessionMatches(
            expectedUserId: expectedUserId,
            expectedSessionEpoch: expectedSessionEpoch,
            expectedRevisionId: expectedRevisionId,
            transform
        )
    }

    @discardableResult
    func clearAllForLogout() throws -> LockScreenSnapshot {
        try base.clearAllForLogout()
    }
}
