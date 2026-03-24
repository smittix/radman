import XCTest
@testable import HorizonRFMac

final class RT950ProBackupServiceTests: XCTestCase {
    func testBackupRoundTripPreservesChannelsAndProfile() throws {
        var profile = RadioProfile()
        profile.name = "Primary RT950"
        profile.serialPort = "/dev/cu.usbserial"
        profile.builtInModel = .radtelRT950Pro
        profile.model = BuiltInRadioModel.radtelRT950Pro.rawValue

        var channel = ChannelMemory()
        channel.location = "1"
        channel.name = "Simplex"
        channel.frequency = "145.500"

        let url = temporaryURL()
        try RT950ProBackupService.exportBackup(channels: [channel], radioProfile: profile, to: url)
        let imported = try RT950ProBackupService.importBackup(from: url)

        XCTAssertEqual(imported.channelCount, 1)
        XCTAssertEqual(imported.document.targetModel, .radtelRT950Pro)
        XCTAssertEqual(imported.document.channels[0].frequency, "145.500")
        XCTAssertEqual(imported.document.radioProfile?.name, "Primary RT950")
    }

    func testBackupRejectsWrongFormat() throws {
        let url = temporaryURL()
        try """
        {
          "format": "not-horizon",
          "version": 1,
          "targetModel": "Radtel RT-950 Pro",
          "channels": []
        }
        """.write(to: url, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try RT950ProBackupService.importBackup(from: url)) { error in
            guard case RT950ProBackupServiceError.invalidFormat = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testBackupRejectsEmptyChannels() throws {
        let url = temporaryURL()
        let document = RT950ProBackupDocument(channels: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)
        try data.write(to: url)

        XCTAssertThrowsError(try RT950ProBackupService.importBackup(from: url)) { error in
            guard case RT950ProBackupServiceError.noChannels = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
