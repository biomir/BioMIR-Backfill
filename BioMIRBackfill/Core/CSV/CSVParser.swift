import Foundation

enum CSVParser {
    static let version = "csv-v0.1"

    static func parse(data: Data, sourceTimeZone: TimeZone) throws -> ParsedCSV {
        guard var text = String(data: data, encoding: .utf8) else {
            throw CSVParseError.invalidUTF8
        }

        if text.unicodeScalars.first?.value == 0xFEFF {
            text.removeFirst()
        }

        var records = try tokenize(text)
        while records.last?.allSatisfy({ $0.isEmpty }) == true {
            records.removeLast()
        }

        guard let headerRecord = records.first, !headerRecord.isEmpty else {
            throw CSVParseError.emptyFile
        }

        let headers = headerRecord.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard headers.contains("Date") else {
            throw CSVParseError.missingDateHeader
        }

        var seenHeaders = Set<String>()
        for header in headers {
            if !seenHeaders.insert(header).inserted {
                throw CSVParseError.duplicateHeader(header)
            }
        }

        guard let dateIndex = headers.firstIndex(of: "Date") else {
            throw CSVParseError.missingDateHeader
        }

        var rows: [CSVRow] = []
        var seenDates = Set<String>()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = sourceTimeZone

        for (zeroBasedIndex, rawRecord) in records.dropFirst().enumerated() {
            let rowNumber = zeroBasedIndex + 2

            if rawRecord.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }

            guard rawRecord.count == headers.count else {
                throw CSVParseError.columnCountMismatch(
                    row: rowNumber,
                    expected: headers.count,
                    actual: rawRecord.count
                )
            }

            let dateText = rawRecord[dateIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let dateComponents = try parseISODate(dateText, rowNumber: rowNumber, calendar: calendar)

            guard seenDates.insert(dateText).inserted else {
                throw CSVParseError.duplicateDate(row: rowNumber, value: dateText)
            }

            var cells: [String: CSVCellState] = [:]
            for (index, header) in headers.enumerated() where index != dateIndex {
                let raw = rawRecord[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.isEmpty {
                    cells[header] = .missing
                    continue
                }

                guard let numeric = Double(raw), numeric.isFinite else {
                    throw CSVParseError.invalidNumeric(row: rowNumber, column: header, value: raw)
                }

                cells[header] = numeric == 0 ? .explicitZero : .value(numeric)
            }

            rows.append(CSVRow(rowNumber: rowNumber, sourceDate: dateComponents, cells: cells))
        }

        return ParsedCSV(
            headers: headers,
            rows: rows,
            sourceTimeZoneIdentifier: sourceTimeZone.identifier,
            encoding: "UTF-8"
        )
    }

    private static func parseISODate(
        _ value: String,
        rowNumber: Int,
        calendar: Calendar
    ) throws -> DateComponents {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            throw CSVParseError.invalidDate(row: rowNumber, value: value)
        }

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0

        guard let date = calendar.date(from: components) else {
            throw CSVParseError.invalidDate(row: rowNumber, value: value)
        }

        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            throw CSVParseError.invalidDate(row: rowNumber, value: value)
        }

        var result = DateComponents()
        result.year = year
        result.month = month
        result.day = day
        return result
    }

    private static func tokenize(_ text: String) throws -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var buffered: Character?

        func flushField() {
            record.append(field)
            field = ""
        }

        func flushRecord() {
            flushField()
            records.append(record)
            record = []
        }

        while true {
            let character: Character?
            if let bufferedCharacter = buffered {
                character = bufferedCharacter
                buffered = nil
            } else {
                character = iterator.next()
            }

            guard let character else { break }

            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            buffered = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }

            switch character {
            case "\r\n":
                // Swift Character segmentation treats CRLF as a single grapheme cluster.
                // Handle it explicitly so RFC-style/Windows CSV line endings terminate records.
                flushRecord()
            case "\"":
                if field.isEmpty {
                    inQuotes = true
                } else {
                    field.append(character)
                }
            case ",":
                flushField()
            case "\n":
                flushRecord()
            case "\r":
                if let next = iterator.next(), next != "\n" {
                    buffered = next
                }
                flushRecord()
            default:
                field.append(character)
            }
        }

        guard !inQuotes else {
            throw CSVParseError.unterminatedQuotedField
        }

        if !field.isEmpty || !record.isEmpty {
            flushRecord()
        }

        return records
    }
}
