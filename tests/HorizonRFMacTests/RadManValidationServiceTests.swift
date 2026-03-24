import XCTest
@testable import HorizonRFMac

final class RadManValidationServiceTests: XCTestCase {
    func testNormalizeChannelFormatsMHzFieldsAndDefaultsMode() throws {
        var channel = ChannelMemory()
        channel.location = "1"
        channel.frequency = "145.5"
        channel.mode = ""
        channel.duplex = "+"
        channel.offset = "0.6"
        channel.nativeSignalGroup = ""
        channel.nativePTTID = ""
        channel.nativeScrambler = ""
        channel.nativeEncryption = ""

        let normalized = try RadManValidationService.normalizeChannel(channel)

        XCTAssertEqual(normalized.frequency, "145.500000")
        XCTAssertEqual(normalized.offset, "0.600000")
        XCTAssertEqual(normalized.mode, "FM")
        XCTAssertEqual(normalized.nativeSignalGroup, "0")
        XCTAssertEqual(normalized.nativePTTID, "0")
        XCTAssertEqual(normalized.nativeScrambler, "0")
        XCTAssertEqual(normalized.nativeEncryption, "0")
    }

    func testNormalizeChannelRequiresOffsetForSplitAndRepeaterModes() {
        var channel = ChannelMemory()
        channel.location = "2"
        channel.frequency = "433.5"
        channel.mode = "FM"
        channel.duplex = "split"
        channel.offset = ""

        XCTAssertThrowsError(try RadManValidationService.normalizeChannel(channel)) { error in
            guard case let RadManValidationError.missingMHz(field) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(field, "TX frequency")
        }
    }
}
