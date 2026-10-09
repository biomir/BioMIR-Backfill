import Foundation

enum CSVCellState: Equatable, Sendable {
    case missing
    case explicitZero
    case value(Double)
}

struct CSVRow: Equatable, Sendable {
    let rowNumber: Int
    let sourceDate: DateComponents
    let cells: [String: CSVCellState]
}

struct ParsedCSV: Equatable, Sendable {
    let headers: [String]
    let rows: [CSVRow]
    let sourceTimeZoneIdentifier: String
    let encoding: String
}

enum CSVParseError: Error, Equatable, CustomStringConvertible {
    case invalidUTF8
    case emptyFile
    case missingDateHeader
    case duplicateHeader(String)
    case unterminatedQuotedField
    case columnCountMismatch(row: Int, expected: Int, actual: Int)
    case invalidDate(row: Int, value: String)
    case duplicateDate(row: Int, value: String)
    case invalidNumeric(row: Int, column: String, value: String)

    var description: String {
        switch self {
        case .invalidUTF8:
            return "Source is not valid UTF-8."
        case .emptyFile:
            return "Source CSV is empty."
        case .missingDateHeader:
            return "Source CSV must contain a Date column."
        case .duplicateHeader(let header):
            return "Duplicate CSV header: \(header)"
        case .unterminatedQuotedField:
            return "CSV contains an unterminated quoted field."
        case .columnCountMismatch(let row, let expected, let actual):
            return "CSV row \(row) has \(actual) columns; expected \(expected)."
        case .invalidDate(let row, let value):
            return "CSV row \(row) contains invalid ISO date: \(value)"
        case .duplicateDate(let row, let value):
            return "CSV row \(row) duplicates source date: \(value)"
        case .invalidNumeric(let row, let column, let value):
            return "CSV row \(row), column \(column), contains invalid numeric value: \(value)"
        }
    }
}

enum CalendarDayIntervalError: Error, Equatable {
    case incompleteDate
    case invalidDate
    case cannotAdvanceDay
}

enum CalendarDayInterval {
    /// Canonical point-in-time anchor for historical daily aggregates.
    /// 12:00 local time is an indexing anchor only; it is not an observed consumption time.
    static func noonAnchor(for components: DateComponents, calendar inputCalendar: Calendar) throws -> Date {
        guard let year = components.year, let month = components.month, let day = components.day else {
            throw CalendarDayIntervalError.incompleteDate
        }

        let calendar = inputCalendar
        var noon = DateComponents()
        noon.calendar = calendar
        noon.timeZone = calendar.timeZone
        noon.year = year
        noon.month = month
        noon.day = day
        noon.hour = 12
        noon.minute = 0
        noon.second = 0

        guard let anchor = calendar.date(from: noon) else {
            throw CalendarDayIntervalError.invalidDate
        }

        let check = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: anchor)
        guard check.year == year, check.month == month, check.day == day,
              check.hour == 12, check.minute == 0, check.second == 0 else {
            throw CalendarDayIntervalError.invalidDate
        }

        return anchor
    }

    static func dayInterval(for components: DateComponents, calendar inputCalendar: Calendar) throws -> DateInterval {
        guard let year = components.year, let month = components.month, let day = components.day else {
            throw CalendarDayIntervalError.incompleteDate
        }

        let calendar = inputCalendar
        var midnight = DateComponents()
        midnight.calendar = calendar
        midnight.timeZone = calendar.timeZone
        midnight.year = year
        midnight.month = month
        midnight.day = day
        midnight.hour = 0
        midnight.minute = 0
        midnight.second = 0

        guard let start = calendar.date(from: midnight) else {
            throw CalendarDayIntervalError.invalidDate
        }

        let check = calendar.dateComponents([.year, .month, .day], from: start)
        guard check.year == year, check.month == month, check.day == day else {
            throw CalendarDayIntervalError.invalidDate
        }

        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw CalendarDayIntervalError.cannotAdvanceDay
        }

        return DateInterval(start: start, end: end)
    }
}
