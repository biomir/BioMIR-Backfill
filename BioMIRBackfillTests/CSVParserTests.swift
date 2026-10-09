import XCTest
@testable import BioMIRBackfill

final class CSVParserTests: XCTestCase {
    private let newYork = TimeZone(identifier: "America/New_York")!

    func testParsesQuotedHeaderAndPreservesMissingZeroAndValueStates() throws {
        let csv = "\"Date\",\"Energy, kcal\",Sodium (mg)\n2025-01-01,0,\n2025-01-02,125.5,2300\n"

        let parsed = try CSVParser.parse(data: Data(csv.utf8), sourceTimeZone: newYork)

        XCTAssertEqual(parsed.headers, ["Date", "Energy, kcal", "Sodium (mg)"])
        XCTAssertEqual(parsed.rows.count, 2)
        XCTAssertEqual(parsed.rows[0].cells["Energy, kcal"], .explicitZero)
        XCTAssertEqual(parsed.rows[0].cells["Sodium (mg)"], .missing)
        XCTAssertEqual(parsed.rows[1].cells["Energy, kcal"], .value(125.5))
        XCTAssertEqual(parsed.rows[1].cells["Sodium (mg)"], .value(2300))
    }

    func testParsesCRLFRecordsAsSeparateRows() throws {
        let csv = "Date,Carb Manager Total Carbohydrates (g)\r\n2021-03-11,59.93\r\n2021-03-12,37.93\r\n"

        let parsed = try CSVParser.parse(data: Data(csv.utf8), sourceTimeZone: newYork)

        XCTAssertEqual(parsed.headers, ["Date", "Carb Manager Total Carbohydrates (g)"])
        XCTAssertEqual(parsed.rows.count, 2)
        XCTAssertEqual(parsed.rows[0].cells["Carb Manager Total Carbohydrates (g)"], .value(59.93))
        XCTAssertEqual(parsed.rows[1].cells["Carb Manager Total Carbohydrates (g)"], .value(37.93))
    }

    func testAcceptsUTF8BOM() throws {
        let bytes = [0xEF, 0xBB, 0xBF] + Array("Date,Sodium (mg)\n2025-01-01,100\n".utf8)
        let parsed = try CSVParser.parse(data: Data(bytes), sourceTimeZone: newYork)
        XCTAssertEqual(parsed.headers, ["Date", "Sodium (mg)"])
        XCTAssertEqual(parsed.rows.count, 1)
    }

    func testRejectsMalformedQuotedCSV() {
        let csv = "Date,\"Sodium (mg)\n2025-01-01,100\n"
        XCTAssertThrowsError(try CSVParser.parse(data: Data(csv.utf8), sourceTimeZone: newYork)) { error in
            guard case CSVParseError.unterminatedQuotedField = error else {
                return XCTFail("Expected unterminatedQuotedField, got \(error)")
            }
        }
    }

    func testRejectsNonFiniteNumericValues() {
        let csv = "Date,Sodium (mg)\n2025-01-01,NaN\n"
        XCTAssertThrowsError(try CSVParser.parse(data: Data(csv.utf8), sourceTimeZone: newYork)) { error in
            guard case CSVParseError.invalidNumeric(let row, let column, let value) = error else {
                return XCTFail("Expected invalidNumeric, got \(error)")
            }
            XCTAssertEqual(row, 2)
            XCTAssertEqual(column, "Sodium (mg)")
            XCTAssertEqual(value, "NaN")
        }
    }

    func testRejectsDuplicateDatesInsteadOfRepairingThem() {
        let csv = "Date,Sodium (mg)\n2025-01-01,100\n2025-01-01,200\n"
        XCTAssertThrowsError(try CSVParser.parse(data: Data(csv.utf8), sourceTimeZone: newYork)) { error in
            guard case CSVParseError.duplicateDate(let row, let value) = error else {
                return XCTFail("Expected duplicateDate, got \(error)")
            }
            XCTAssertEqual(row, 3)
            XCTAssertEqual(value, "2025-01-01")
        }
    }

    func testRejectsInvalidCalendarDate() {
        let csv = "Date,Sodium (mg)\n2025-02-30,100\n"
        XCTAssertThrowsError(try CSVParser.parse(data: Data(csv.utf8), sourceTimeZone: newYork)) { error in
            guard case CSVParseError.invalidDate(let row, let value) = error else {
                return XCTFail("Expected invalidDate, got \(error)")
            }
            XCTAssertEqual(row, 2)
            XCTAssertEqual(value, "2025-02-30")
        }
    }
}
