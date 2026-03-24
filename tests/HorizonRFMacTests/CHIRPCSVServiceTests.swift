import XCTest
@testable import HorizonRFMac

final class CHIRPCSVServiceTests: XCTestCase {
    func testImportAllowsMissingOptionalCHIRPHeaders() throws {
        let csv = """
        Location,Name,Frequency
        1,Simplex 1,145.500
        """

        let url = try writeTempCSV(contents: csv)
        let channels = try CHIRPCSVService.importChannels(from: url)

        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].location, "1")
        XCTAssertEqual(channels[0].name, "Simplex 1")
        XCTAssertEqual(channels[0].frequency, "145.500")
        XCTAssertEqual(channels[0].dvcode, "")
    }

    func testImportRequiresFrequencyHeader() throws {
        let csv = """
        Location,Name
        1,Simplex 1
        """

        let url = try writeTempCSV(contents: csv)

        XCTAssertThrowsError(try CHIRPCSVService.importChannels(from: url)) { error in
            guard case let CHIRPCSVServiceError.missingHeaders(headers) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(headers, ["Frequency"])
        }
    }

    func testImportSupportsCRLFWithTrailingEmptyFields() throws {
        let csv = "Location,Name,Frequency,DVCODE\r\n1,Simplex 1,145.500,\r\n2,Simplex 2,146.520,\r\n"
        let url = try writeTempCSV(contents: csv)

        let channels = try CHIRPCSVService.importChannels(from: url)

        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].dvcode, "")
        XCTAssertEqual(channels[1].frequency, "146.520")
    }

    func testImportRejectsHeaderOnlyFiles() throws {
        let csv = "Location,Name,Frequency\r\n"
        let url = try writeTempCSV(contents: csv)

        XCTAssertThrowsError(try CHIRPCSVService.importChannels(from: url)) { error in
            guard case CHIRPCSVServiceError.noChannelRows = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func writeTempCSV(contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("csv")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
