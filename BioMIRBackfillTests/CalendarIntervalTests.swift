import XCTest
@testable import BioMIRBackfill

final class CalendarIntervalTests: XCTestCase {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    func testSpringDSTDayUsesCalendarDayNotFixed86400Seconds() throws {
        let interval = try CalendarDayInterval.dayInterval(
            for: DateComponents(year: 2026, month: 3, day: 8),
            calendar: calendar()
        )
        XCTAssertEqual(interval.duration, 23 * 60 * 60, accuracy: 0.001)
    }

    func testFallDSTDayUsesCalendarDayNotFixed86400Seconds() throws {
        let interval = try CalendarDayInterval.dayInterval(
            for: DateComponents(year: 2026, month: 11, day: 1),
            calendar: calendar()
        )
        XCTAssertEqual(interval.duration, 25 * 60 * 60, accuracy: 0.001)
    }

    func testIntervalStartsOnRequestedLocalCalendarDate() throws {
        let cal = calendar()
        let requested = DateComponents(year: 2025, month: 1, day: 8)
        let interval = try CalendarDayInterval.dayInterval(for: requested, calendar: cal)
        let observed = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: interval.start)

        XCTAssertEqual(observed.year, 2025)
        XCTAssertEqual(observed.month, 1)
        XCTAssertEqual(observed.day, 8)
        XCTAssertEqual(observed.hour, 0)
        XCTAssertEqual(observed.minute, 0)
        XCTAssertEqual(observed.second, 0)
    }
    func testHistoricalAggregateNoonAnchorUsesTwelveLocalTime() throws {
        let cal = calendar()
        let anchor = try CalendarDayInterval.noonAnchor(
            for: DateComponents(year: 2021, month: 8, day: 22),
            calendar: cal
        )
        let observed = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: anchor)

        XCTAssertEqual(observed.year, 2021)
        XCTAssertEqual(observed.month, 8)
        XCTAssertEqual(observed.day, 22)
        XCTAssertEqual(observed.hour, 12)
        XCTAssertEqual(observed.minute, 0)
        XCTAssertEqual(observed.second, 0)
    }

    func testHistoricalAggregateNoonAnchorIsStableAcrossDSTTransitionDates() throws {
        let cal = calendar()
        for requested in [
            DateComponents(year: 2026, month: 3, day: 8),
            DateComponents(year: 2026, month: 11, day: 1)
        ] {
            let anchor = try CalendarDayInterval.noonAnchor(for: requested, calendar: cal)
            let observed = cal.dateComponents([.year, .month, .day, .hour], from: anchor)
            XCTAssertEqual(observed.year, requested.year)
            XCTAssertEqual(observed.month, requested.month)
            XCTAssertEqual(observed.day, requested.day)
            XCTAssertEqual(observed.hour, 12)
        }
    }

}
