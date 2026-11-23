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

        let cancelCallsBeforeDelete = env.notificationService.cancelAllCallCount
        try await env.container.scheduler.deleteSchedule(scheduleId: created.id)
        XCTAssertTrue(try await env.container.scheduler.fetchSchedules().isEmpty)
        XCTAssertTrue(env.notificationService.pendingIdentifiers.isEmpty)
        XCTAssertGreaterThan(env.notificationService.cancelAllCallCount, cancelCallsBeforeDelete)
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
}
