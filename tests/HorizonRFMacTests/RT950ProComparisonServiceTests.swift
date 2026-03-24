import XCTest
@testable import HorizonRFMac

final class RT950ProComparisonServiceTests: XCTestCase {
    func testCompareLiveRadioDetectsChannelDifferences() throws {
        let liveClone = try cloneData(with: [
            channel(location: "1", name: "LOCAL", frequency: "145.500000"),
        ])

        let report = try RT950ProComparisonService.compareLiveRadio(
            liveCloneData: liveClone,
            againstChannels: [
                channel(location: "1", name: "CALL", frequency: "146.520000"),
            ]
        )

        XCTAssertTrue(report.hasChanges)
        XCTAssertEqual(report.sections.first?.kind, .channels)
        XCTAssertEqual(report.sections.first?.items.first?.label, "Memory 1")
    }

    func testCompareCloneDataReportsAPRSDTMFAndCoreSettingChanges() throws {
        let base = Data(repeating: 0xFF, count: RT950ProUSBService.expectedCloneByteCount)
        let changedAPRS = try RT950ProCloneCodec.applyingAPRS(
            RT950ProAPRSEntry(
                aprsEnabled: true,
                gpsEnabled: true,
                timeZone: "2",
                callSign: "M0TEST",
                ssid: "1",
                routingSelect: "4",
                myPosition: "6",
                radioSymbol: "2",
                aprsPriority: "3",
                beaconTxType: "1",
                customRoutingOne: "ROUTE1",
                customRoutingTwo: "ROUTE2",
                sendCustomMessages: true,
                customMessages: "HELLO"
            ),
            to: base
        )

        let changedCore = try RT950ProCloneCodec.applyingFunctionSettings(
            RT950ProFunctionSettingsEntry(values: ["sql": "5", "tdr": "On"]),
            to: changedAPRS
        )

        let changedClone = try RT950ProCloneCodec.applyingDTMF(
            RT950ProDTMFEntry(currentID: "123", pttMode: "2", codeGroups: ["123456"]),
            to: changedCore
        )

        let report = try RT950ProComparisonService.compareCloneData(
            base,
            beforeLabel: "Base",
            against: changedClone,
            afterLabel: "Changed"
        )

        let kinds = Set(report.sections.map(\.kind))
        XCTAssertTrue(kinds.contains(.aprs))
        XCTAssertTrue(kinds.contains(.coreSettings))
        XCTAssertTrue(kinds.contains(.dtmf))
    }

    private func cloneData(with channels: [ChannelMemory]) throws -> Data {
        try RT950ProCloneCodec.applyingChannels(
            channels,
            to: Data(repeating: 0xFF, count: RT950ProUSBService.expectedCloneByteCount)
        )
    }

    private func channel(location: String, name: String, frequency: String) -> ChannelMemory {
        var channel = ChannelMemory.empty
        channel.location = location
        channel.name = name
        channel.frequency = frequency
        return channel
    }
}
