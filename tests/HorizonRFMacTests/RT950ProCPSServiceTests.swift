import XCTest
@testable import HorizonRFMac

final class RT950ProCPSServiceTests: XCTestCase {
    func testImportParsesNamedZoneArrayFixture() throws {
        let result = try RT950ProCPSService.importCodeplug(at: try fixtureURL("RT-950PRO Ingo.dat"))

        XCTAssertEqual(result.format, .namedZoneArray)
        XCTAssertEqual(result.importedZoneCount, 15)
        XCTAssertEqual(result.zoneNames.first, "CB 1-40")
        XCTAssertEqual(result.zoneNames[5], "PMR")
        XCTAssertEqual(result.zoneNames[8], "AfU 70 cm")
        XCTAssertGreaterThan(result.importedChannelCount, 0)
        XCTAssertLessThanOrEqual(result.importedChannelCount, ChannelPlanService.maxMemoryCount)
        XCTAssertEqual(result.importedChannels.first?.location, "1")
    }

    func testImportParsesGroupedZoneArraysFixture() throws {
        let result = try RT950ProCPSService.importCodeplug(at: try fixtureURL("north east zones.dat"))

        XCTAssertEqual(result.format, .groupedChannelArrays)
        XCTAssertTrue(result.zoneNames.isEmpty)
        XCTAssertEqual(result.channelSlotCount, ChannelPlanService.maxMemoryCount)
        XCTAssertGreaterThan(result.importedChannelCount, 0)
        XCTAssertTrue(result.notes.contains { $0.contains("grouped zone arrays") })
    }

    func testImportKeepsRadioCapacityWhenCPSTemplateHasMoreSlots() throws {
        let result = try RT950ProCPSService.importCodeplug(at: try fixtureURL("RT-950PRO_CPS_021225.dat"))

        XCTAssertEqual(result.channelSlotCount, 990)
        XCTAssertLessThanOrEqual(result.importedChannelCount, ChannelPlanService.maxMemoryCount)
        XCTAssertTrue(result.notes.contains { $0.contains("Skipped CPS positions above \(ChannelPlanService.maxMemoryCount)") })
    }

    func testExportRoundTripsNamedZoneTemplate() throws {
        let imported = try RT950ProCPSService.importCodeplug(at: try fixtureURL("RT-950PRO Ingo.dat"))
        let templateData = try XCTUnwrap(Data(base64Encoded: imported.templateDataBase64))
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("dat")

        try RT950ProCPSService.exportCodeplug(
            channels: imported.importedChannels,
            zoneNames: imported.zoneNames,
            to: exportURL,
            templateData: templateData
        )

        let exported = try RT950ProCPSService.importCodeplug(at: exportURL)
        XCTAssertEqual(exported.zoneNames, imported.zoneNames)
        XCTAssertEqual(exported.importedChannels.count, imported.importedChannels.count)
        XCTAssertEqual(
            Array(exported.importedChannels.prefix(12)).map(\.frequency),
            Array(imported.importedChannels.prefix(12)).map(\.frequency)
        )
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Local RT-950 CPS fixture '\(name)' is not present in this checkout.")
        }
        return url
    }
}
