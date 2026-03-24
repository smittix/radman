import XCTest
@testable import HorizonRFMac

final class RadioSupportTests: XCTestCase {
    func testRT950ProIsPreferredStandaloneTarget() {
        let target = RadioCatalog.preferredStandaloneTarget

        XCTAssertEqual(target.model, .radtelRT950Pro)
        XCTAssertEqual(target.recommendedConnection, .usbCable)
        XCTAssertEqual(target.supportLevel, .directProgrammingReady)
    }

    func testLegacyRadioProfilesDecodeWithDefaults() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Boat Radio",
          "model": "Radtel RT-950 Pro",
          "chirpID": "",
          "serialPort": "/dev/cu.usbserial",
          "notes": "Legacy profile"
        }
        """

        let profile = try JSONDecoder().decode(RadioProfile.self, from: Data(json.utf8))

        XCTAssertEqual(profile.builtInModel, .radtelRT950Pro)
        XCTAssertEqual(profile.preferredConnection, .usbCable)
        XCTAssertTrue(profile.preferNativeWorkflow)
    }
}
