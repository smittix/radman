import XCTest
@testable import HorizonRFMac

final class RT950ProCloneCodecTests: XCTestCase {
    func testApplyingChannelsRoundTripsCoreMemoryFields() throws {
        var clone = Data(repeating: 0xFF, count: RT950ProUSBService.expectedCloneByteCount)
        clone[RT950ProCloneCodec.channelSectionBytes] = 1

        var channel = ChannelMemory.empty
        channel.location = "1"
        channel.name = "LOCAL"
        channel.frequency = "145.500000"
        channel.duplex = "+"
        channel.offset = "0.600000"
        channel.tone = "Tone"
        channel.rToneFreq = "123.0"
        channel.mode = "NFM"
        channel.power = "Low"
        channel.skip = "S"
        channel.nativeSignalGroup = "3"
        channel.nativePTTID = "2"
        channel.nativeBusyLockout = true
        channel.nativeScrambler = "4"
        channel.nativeEncryption = "1"
        channel.nativeLearnFHSS = true
        channel.nativeFHSSCode = "ABC123"

        let patched = try RT950ProCloneCodec.applyingChannels([channel], to: clone)
        XCTAssertEqual(patched[RT950ProCloneCodec.channelSectionBytes], 1)

        let decoded = try RT950ProCloneCodec.channels(from: patched)
        let restored = try XCTUnwrap(decoded.first(where: { $0.location == "1" }))
        XCTAssertEqual(restored.name, "LOCAL")
        XCTAssertEqual(restored.frequency, "145.500000")
        XCTAssertEqual(restored.duplex, "+")
        XCTAssertEqual(restored.offset, "0.600000")
        XCTAssertEqual(restored.tone, "Tone")
        XCTAssertEqual(restored.rToneFreq, "123.0")
        XCTAssertEqual(restored.mode, "NFM")
        XCTAssertEqual(restored.power, "Low")
        XCTAssertEqual(restored.skip, "S")
        XCTAssertEqual(restored.nativeSignalGroup, "3")
        XCTAssertEqual(restored.nativePTTID, "2")
        XCTAssertEqual(restored.nativeScrambler, "4")
        XCTAssertEqual(restored.nativeEncryption, "1")
        XCTAssertEqual(restored.nativeFHSSCode, "ABC123")
        XCTAssertTrue(restored.nativeBusyLockout)
        XCTAssertTrue(restored.nativeLearnFHSS)
    }

    func testSummaryDecodesVFOAndFunctionSettings() throws {
        var clone = Data(repeating: 0xFF, count: RT950ProUSBService.expectedCloneByteCount)
        let vfoStart = RT950ProCloneCodec.channelSectionBytes
        let functionStart = vfoStart + RT950ProCloneCodec.vfoSegmentBytes
        clone.replaceSubrange(vfoStart..<(vfoStart + 8), with: Data([1, 4, 5, 5, 0, 0, 0, 0]))
        clone[vfoStart + 13] = 0x01
        clone[vfoStart + 14] = 0x10
        clone[vfoStart + 16] = 0x02
        clone[vfoStart + 17] = 0x41
        clone.replaceSubrange((vfoStart + 20)..<(vfoStart + 27), with: Data([0, 0, 0, 6, 0, 0, 0]))
        clone[functionStart + 0] = 0x05
        clone[functionStart + 4] = 0x01

        let summary = try RT950ProCloneCodec.summary(from: clone)
        XCTAssertEqual(summary.vfos.first?.frequency, "145.500000")
        XCTAssertEqual(summary.vfos.first?.direction, "+")
        XCTAssertEqual(summary.vfos.first?.mode, "AM")
        XCTAssertEqual(summary.vfos.first?.power, "Low")
        XCTAssertEqual(summary.functionSettings.first(where: { $0.key == "sql" })?.value, "5")
        XCTAssertEqual(summary.functionSettings.first(where: { $0.key == "tdr" })?.value, "On")
    }

    func testSummaryUsesRealSegmentBoundariesForLaterSections() throws {
        var clone = Data(repeating: 0xFF, count: RT950ProUSBService.expectedCloneByteCount)
        let vfoStart = RT950ProCloneCodec.channelSectionBytes
        let functionStart = vfoStart + RT950ProCloneCodec.vfoSegmentBytes
        let dtmfStart = functionStart + RT950ProCloneCodec.functionSegmentBytes
        let aprsStart = dtmfStart + RT950ProCloneCodec.dtmfSegmentBytes + RT950ProCloneCodec.modulationParameterSectionBytes + RT950ProCloneCodec.modulationNameSectionBytes

        clone[functionStart + 0] = 0x04
        clone[functionStart + 4] = 0x01

        clone[dtmfStart + 0] = 1
        clone[dtmfStart + 1] = 2
        clone[dtmfStart + 2] = 3
        clone[dtmfStart + 3] = 0xFF
        clone[dtmfStart + 6] = 0x02

        let callSign = Array("M0TEST".utf8)
        clone.replaceSubrange((aprsStart + 17)..<(aprsStart + 17 + callSign.count), with: callSign)
        clone[aprsStart + 23] = 0x03
        clone[aprsStart + 24] = 0x02

        let summary = try RT950ProCloneCodec.summary(from: clone)

        XCTAssertEqual(summary.functionSettings.first(where: { $0.key == "sql" })?.value, "4")
        XCTAssertEqual(summary.functionSettings.first(where: { $0.key == "tdr" })?.value, "On")
        XCTAssertEqual(summary.dtmf.currentID, "123")
        XCTAssertEqual(summary.dtmf.pttMode, "2")
        XCTAssertEqual(summary.aprsFields.first(where: { $0.key == "call_sign" })?.value, "M0TEST")
        XCTAssertEqual(summary.aprsFields.first(where: { $0.key == "ssid" })?.value, "3")
        XCTAssertEqual(summary.aprsFields.first(where: { $0.key == "routing_select" })?.value, "2")
    }

    func testDecodedChannelsUseUniqueIdentifiers() throws {
        var clone = Data(repeating: 0xFF, count: RT950ProUSBService.expectedCloneByteCount)

        var channelOne = ChannelMemory()
        channelOne.location = "1"
        channelOne.name = "ONE"
        channelOne.frequency = "145.500000"

        var channelTwo = ChannelMemory()
        channelTwo.location = "2"
        channelTwo.name = "TWO"
        channelTwo.frequency = "145.550000"

        clone = try RT950ProCloneCodec.applyingChannels([channelOne, channelTwo], to: clone)
        let decoded = try RT950ProCloneCodec.channels(from: clone)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(Set(decoded.map(\.id)).count, 2)
    }

    func testApplyingAPRSEntryRoundTripsEditableFields() throws {
        let clone = Data(repeating: 0xFF, count: RT950ProUSBService.expectedCloneByteCount)

        let patched = try RT950ProCloneCodec.applyingAPRS(
            RT950ProAPRSEntry(
                aprsEnabled: true,
                gpsEnabled: true,
                timeZone: "4",
                callSign: "M0TEST",
                ssid: "7",
                routingSelect: "2",
                myPosition: "9",
                radioSymbol: "5",
                aprsPriority: "1",
                beaconTxType: "2",
                customRoutingOne: "ROUTE1",
                customRoutingTwo: "ROUTE2",
                sendCustomMessages: true,
                customMessages: "HELLO WORLD"
            ),
            to: clone
        )

        let entry = try RT950ProCloneCodec.aprsEntry(from: patched)
        XCTAssertTrue(entry.aprsEnabled)
        XCTAssertTrue(entry.gpsEnabled)
        XCTAssertEqual(entry.timeZone, "4")
        XCTAssertEqual(entry.callSign, "M0TEST")
        XCTAssertEqual(entry.ssid, "7")
        XCTAssertEqual(entry.routingSelect, "2")
        XCTAssertEqual(entry.myPosition, "9")
        XCTAssertEqual(entry.radioSymbol, "5")
        XCTAssertEqual(entry.aprsPriority, "1")
        XCTAssertEqual(entry.beaconTxType, "2")
        XCTAssertEqual(entry.customRoutingOne, "ROUTE1")
        XCTAssertEqual(entry.customRoutingTwo, "ROUTE2")
        XCTAssertTrue(entry.sendCustomMessages)
        XCTAssertEqual(entry.customMessages, "HELLO WORLD")
    }

    func testApplyingDTMFRoundTripsEditableFields() throws {
        let clone = Data(repeating: 0xFF, count: RT950ProUSBService.expectedCloneByteCount)

        let patched = try RT950ProCloneCodec.applyingDTMF(
            RT950ProDTMFEntry(
                currentID: "12A#",
                pttMode: "3",
                codeGroups: [
                    "123456",
                    "*0#AB",
                    "999",
                ]
            ),
            to: clone
        )

        let entry = try RT950ProCloneCodec.dtmfEntry(from: patched)
        XCTAssertEqual(entry.currentID, "12A#")
        XCTAssertEqual(entry.pttMode, "3")
        XCTAssertEqual(entry.codeGroups[0], "123456")
        XCTAssertEqual(entry.codeGroups[1], "*0#AB")
        XCTAssertEqual(entry.codeGroups[2], "999")
        XCTAssertEqual(entry.codeGroups[3], "")
    }

    func testApplyingFunctionSettingsRoundTripsEditableFields() throws {
        let clone = Data(repeating: 0xFF, count: RT950ProUSBService.expectedCloneByteCount)

        let patched = try RT950ProCloneCodec.applyingFunctionSettings(
            RT950ProFunctionSettingsEntry(values: [
                "sql": "5",
                "save_mode": "2",
                "tdr": "On",
                "beep_prompt": "Off",
                "display_mode_a": "1",
                "display_mode_b": "2",
                "display_mode_c": "3",
                "auto_key_lock": "On",
                "work_mode_a": "2",
                "work_mode_b": "1",
                "work_mode_c": "3",
                "weather_channel": "9",
                "divide_channel": "On",
                "key0_long": "17",
            ]),
            to: clone
        )

        let entry = try RT950ProCloneCodec.functionSettingsEntry(from: patched)
        XCTAssertEqual(entry["sql"], "5")
        XCTAssertEqual(entry["save_mode"], "2")
        XCTAssertEqual(entry["tdr"], "On")
        XCTAssertEqual(entry["beep_prompt"], "Off")
        XCTAssertEqual(entry["display_mode_a"], "1")
        XCTAssertEqual(entry["display_mode_b"], "2")
        XCTAssertEqual(entry["display_mode_c"], "3")
        XCTAssertEqual(entry["auto_key_lock"], "On")
        XCTAssertEqual(entry["work_mode_a"], "2")
        XCTAssertEqual(entry["work_mode_b"], "1")
        XCTAssertEqual(entry["work_mode_c"], "3")
        XCTAssertEqual(entry["weather_channel"], "9")
        XCTAssertEqual(entry["divide_channel"], "On")
        XCTAssertEqual(entry["key0_long"], "17")
    }
}
