import XCTest
@testable import HorizonRFMac

final class ChannelPlanServiceTests: XCTestCase {
    func testInsertBlankChannelShiftsFollowingLocations() throws {
        let channels = [
            makeChannel(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, location: 1, name: "One", frequency: "145.500000"),
            makeChannel(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, location: 2, name: "Two", frequency: "145.550000"),
            makeChannel(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, location: 3, name: "Three", frequency: "145.600000"),
        ]

        let result = try ChannelPlanService.insertBlankChannel(into: channels, afterLocation: 1)

        XCTAssertEqual(result.inserted.location, "2")
        XCTAssertEqual(result.channels.map(\.location), ["1", "2", "3", "4"])
        XCTAssertEqual(result.channels.first(where: { $0.name == "Two" })?.location, "3")
        XCTAssertEqual(result.channels.first(where: { $0.name == "Three" })?.location, "4")
    }

    func testPasteChannelsInsertsBlockAndPreservesOrder() throws {
        let base = [
            makeChannel(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, location: 1, name: "One", frequency: "145.500000"),
            makeChannel(id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!, location: 2, name: "Two", frequency: "145.550000"),
            makeChannel(id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!, location: 3, name: "Three", frequency: "145.600000"),
        ]
        let copied = [
            makeChannel(id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!, location: 8, name: "Copied B", frequency: "433.600000"),
            makeChannel(id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!, location: 7, name: "Copied A", frequency: "433.500000"),
        ]

        let result = try ChannelPlanService.pasteChannels(copied, into: base, afterLocation: 1)

        XCTAssertEqual(result.pasted.map(\.location), ["2", "3"])
        XCTAssertEqual(result.pasted.map(\.name), ["Copied A", "Copied B"])
        XCTAssertEqual(result.channels.map(\.location), ["1", "2", "3", "4", "5"])
        XCTAssertEqual(result.channels.first(where: { $0.name == "Two" })?.location, "4")
        XCTAssertEqual(Set(result.pasted.map(\.id)).count, 2)
    }

    func testValidateRejectsMoreThanRT950Capacity() {
        let channels = (1...(ChannelPlanService.maxMemoryCount + 1)).map { index in
            makeChannel(id: UUID(), location: index, name: "CH\(index)", frequency: "145.500000")
        }

        XCTAssertThrowsError(try ChannelPlanService.validate(channels)) { error in
            guard case let ChannelPlanError.limitExceeded(limit) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(limit, ChannelPlanService.maxMemoryCount)
        }
    }

    func testValidateRejectsDuplicateLocations() {
        let channels = [
            makeChannel(id: UUID(), location: 1, name: "One", frequency: "145.500000"),
            makeChannel(id: UUID(), location: 1, name: "Two", frequency: "145.550000"),
        ]

        XCTAssertThrowsError(try ChannelPlanService.validate(channels)) { error in
            guard case let ChannelPlanError.duplicateLocation(location) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(location, "1")
        }
    }

    func testPrepareImportedChannelsAssignsMissingLocations() throws {
        let first = makeChannel(id: UUID(), location: 4, name: "Four", frequency: "145.800000")
        let second = makeChannel(id: UUID(), location: 1, name: "One", frequency: "145.500000")
        var third = ChannelMemory()
        third.id = UUID()
        third.name = "Auto"
        third.frequency = "145.650000"

        let prepared = try ChannelPlanService.prepareImportedChannels([first, second, third])

        XCTAssertEqual(prepared.map(\.location), ["1", "2", "4"])
        XCTAssertEqual(prepared.first(where: { $0.name == "Auto" })?.location, "2")
    }

    func testZoneAndSlotMappingRoundTripsNativeMemoryLayout() {
        XCTAssertEqual(ChannelPlanService.zone(forLocation: 1), 1)
        XCTAssertEqual(ChannelPlanService.slot(forLocation: 1), 1)
        XCTAssertEqual(ChannelPlanService.zone(forLocation: 64), 1)
        XCTAssertEqual(ChannelPlanService.slot(forLocation: 64), 64)
        XCTAssertEqual(ChannelPlanService.zone(forLocation: 65), 2)
        XCTAssertEqual(ChannelPlanService.slot(forLocation: 65), 1)
        XCTAssertEqual(ChannelPlanService.zone(forLocation: 960), 15)
        XCTAssertEqual(ChannelPlanService.slot(forLocation: 960), 64)
        XCTAssertEqual(ChannelPlanService.location(forZone: 15, slot: 64), 960)
        XCTAssertEqual(ChannelPlanService.location(forZone: 2, slot: 1), 65)
    }

    func testNextAvailableLocationInZoneFindsFirstFreeSlot() {
        let channels = [
            makeChannel(id: UUID(), location: 1, name: "One", frequency: "145.500000"),
            makeChannel(id: UUID(), location: 2, name: "Two", frequency: "145.550000"),
            makeChannel(id: UUID(), location: 65, name: "Zone 2 One", frequency: "433.500000"),
        ]

        XCTAssertEqual(ChannelPlanService.nextAvailableLocation(inZone: 1, channels: channels), 3)
        XCTAssertEqual(ChannelPlanService.nextAvailableLocation(inZone: 2, channels: channels), 66)
    }

    func testSortedBySlotGroupsMatchingSlotsAcrossZones() {
        let channels = [
            makeChannel(id: UUID(), location: 65, name: "Zone2 Slot1", frequency: "433.500000"),
            makeChannel(id: UUID(), location: 2, name: "Zone1 Slot2", frequency: "145.550000"),
            makeChannel(id: UUID(), location: 1, name: "Zone1 Slot1", frequency: "145.500000"),
            makeChannel(id: UUID(), location: 66, name: "Zone2 Slot2", frequency: "433.550000"),
        ]

        let sorted = ChannelPlanService.sorted(channels, by: .slot)

        XCTAssertEqual(sorted.map(\.location), ["1", "65", "2", "66"])
    }

    func testUpsertingWithOverwriteReplacesConflictingMemory() throws {
        let existing = [
            makeChannel(id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!, location: 10, name: "Original", frequency: "145.500000"),
            makeChannel(id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!, location: 11, name: "Neighbor", frequency: "145.550000"),
        ]
        let replacement = makeChannel(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000033")!,
            location: 10,
            name: "Replacement",
            frequency: "433.500000"
        )

        let updated = try ChannelPlanService.upserting(
            replacement,
            into: existing,
            overwriteExistingLocation: true
        )

        XCTAssertEqual(updated.count, 2)
        XCTAssertEqual(updated.first(where: { $0.location == "10" })?.name, "Replacement")
        XCTAssertNil(updated.first(where: { $0.name == "Original" }))
    }

    func testConflictingChannelIgnoresCurrentEditingID() {
        let currentID = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
        let channels = [
            makeChannel(id: currentID, location: 20, name: "Current", frequency: "145.500000"),
            makeChannel(id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!, location: 21, name: "Other", frequency: "145.550000"),
        ]

        XCTAssertNil(ChannelPlanService.conflictingChannel(at: 20, excluding: currentID, in: channels))
        XCTAssertEqual(ChannelPlanService.conflictingChannel(at: 21, excluding: currentID, in: channels)?.name, "Other")
    }

    func testNormalizedZoneNamesFillMissingEntriesWithDefaults() {
        let names = ChannelPlanService.normalizedZoneNames(["Marine", "Airband", ""])

        XCTAssertEqual(names.count, ChannelPlanService.zoneCount)
        XCTAssertEqual(names[0], "Marine")
        XCTAssertEqual(names[1], "Airband")
        XCTAssertEqual(names[2], "Zone 3")
        XCTAssertEqual(names[14], "Zone 15")
    }

    func testWorkAreaDisplayNameUsesZeroBasedZoneMapping() {
        let names = ChannelPlanService.normalizedZoneNames(["Marine", "Airband"])

        XCTAssertEqual(ChannelPlanService.workAreaDisplayName(for: "0", customNames: names), "Raw 0 • Z1 • Marine")
        XCTAssertEqual(ChannelPlanService.workAreaDisplayName(for: "1", customNames: names), "Raw 1 • Z2 • Airband")
        XCTAssertEqual(ChannelPlanService.workAreaDisplayName(for: "15", customNames: names), "Raw 15 • Z15")
    }

    private func makeChannel(id: UUID, location: Int, name: String, frequency: String) -> ChannelMemory {
        var channel = ChannelMemory()
        channel.id = id
        channel.location = String(location)
        channel.name = name
        channel.frequency = frequency
        return channel
    }
}
