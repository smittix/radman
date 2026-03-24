import Foundation

enum ChannelSortMode: String, CaseIterable, Identifiable {
    case memory = "Memory"
    case zone = "Zone"
    case slot = "Slot"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .memory:
            return "Memory Number"
        case .zone:
            return "Zone, then Slot"
        case .slot:
            return "Slot, then Zone"
        }
    }
}

struct ChannelZoneSummary: Identifiable, Hashable {
    let zone: Int
    let channels: [ChannelMemory]
    let capacity: Int

    var id: Int { zone }
    var title: String { "Zone \(zone)" }
    var usedSlots: Int { channels.count }
    var freeSlots: Int { max(0, capacity - usedSlots) }
    var firstAvailableSlot: Int? {
        let used = Set(channels.compactMap(ChannelPlanService.slotValue(for:)))
        return (1...capacity).first { !used.contains($0) }
    }
}

enum ChannelPlanError: LocalizedError {
    case limitExceeded(limit: Int)
    case invalidLocation(String)
    case duplicateLocation(String)
    case invalidZone(String)
    case invalidZoneSlot(String)

    var errorDescription: String? {
        switch self {
        case let .limitExceeded(limit):
            return "The RT-950 Pro supports up to \(limit) memory slots."
        case let .invalidLocation(value):
            return "Channel location '\(value)' is outside the RT-950 Pro range."
        case let .duplicateLocation(value):
            return "More than one channel is trying to use memory \(value)."
        case let .invalidZone(value):
            return "Zone '\(value)' is outside the RT-950 Pro zone range."
        case let .invalidZoneSlot(value):
            return "Zone slot '\(value)' is outside the RT-950 Pro slot range."
        }
    }
}

enum ChannelPlanService {
    static let zoneCount = 15
    static let slotsPerZone = 64
    static let maxMemoryCount = RT950ProCloneCodec.channelCount

    static func defaultZoneName(for zone: Int) -> String {
        "Zone \(zone)"
    }

    static func normalizedZoneNames(_ zoneNames: [String]) -> [String] {
        (1...zoneCount).map { zone in
            if zone <= zoneNames.count {
                let trimmed = zoneNames[zone - 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
            return defaultZoneName(for: zone)
        }
    }

    static func zoneName(for zone: Int, customNames: [String]) -> String {
        guard (1...zoneCount).contains(zone) else {
            return defaultZoneName(for: max(1, min(zoneCount, zone)))
        }
        return normalizedZoneNames(customNames)[zone - 1]
    }

    static func zoneShortLabel(for zone: Int, customNames: [String]) -> String {
        let name = zoneName(for: zone, customNames: customNames)
        if name == defaultZoneName(for: zone) {
            return "Z\(zone)"
        }
        return "Z\(zone) • \(name)"
    }

    static func workAreaDisplayName(for rawValue: String, customNames: [String]) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Int(trimmed) else {
            return trimmed.isEmpty ? "Unset" : trimmed
        }

        if (0..<zoneCount).contains(raw) {
            let zone = raw + 1
            return "Raw \(raw) • \(zoneShortLabel(for: zone, customNames: customNames))"
        }

        if (1...zoneCount).contains(raw) {
            return "Raw \(raw) • \(zoneShortLabel(for: raw, customNames: customNames))"
        }

        return trimmed
    }

    static func validate(_ channels: [ChannelMemory]) throws {
        guard channels.count <= maxMemoryCount else {
            throw ChannelPlanError.limitExceeded(limit: maxMemoryCount)
        }

        var seen = Set<Int>()
        for channel in channels {
            let location = try requiredLocation(channel.location)
            if seen.contains(location) {
                throw ChannelPlanError.duplicateLocation(String(location))
            }
            seen.insert(location)
        }
    }

    static func nextAvailableLocation(in channels: [ChannelMemory]) -> Int? {
        let used = Set(channels.compactMap(locationValue(for:)))
        return (1...maxMemoryCount).first { !used.contains($0) }
    }

    static func nextAvailableLocation(inZone zone: Int, channels: [ChannelMemory]) -> Int? {
        let summary = zoneSummary(for: zone, channels: channels)
        guard let slot = summary.firstAvailableSlot else { return nil }
        return location(forZone: zone, slot: slot)
    }

    static func prepareImportedChannels(_ channels: [ChannelMemory]) throws -> [ChannelMemory] {
        guard channels.count <= maxMemoryCount else {
            throw ChannelPlanError.limitExceeded(limit: maxMemoryCount)
        }

        var used = Set<Int>()
        var prepared: [ChannelMemory] = []

        for var channel in sorted(channels) {
            if let location = locationValue(for: channel) {
                if used.contains(location) {
                    throw ChannelPlanError.duplicateLocation(String(location))
                }
                used.insert(location)
            } else {
                guard let next = (1...maxMemoryCount).first(where: { !used.contains($0) }) else {
                    throw ChannelPlanError.limitExceeded(limit: maxMemoryCount)
                }
                channel.location = String(next)
                used.insert(next)
            }
            prepared.append(channel)
        }

        try validate(prepared)
        return sorted(prepared)
    }

    static func upserting(_ channel: ChannelMemory, into channels: [ChannelMemory]) throws -> [ChannelMemory] {
        try upserting(channel, into: channels, overwriteExistingLocation: false)
    }

    static func upserting(
        _ channel: ChannelMemory,
        into channels: [ChannelMemory],
        overwriteExistingLocation: Bool
    ) throws -> [ChannelMemory] {
        var updated = channels
        if overwriteExistingLocation, let location = locationValue(for: channel) {
            updated.removeAll {
                $0.id != channel.id && locationValue(for: $0) == location
            }
        }
        if let index = updated.firstIndex(where: { $0.id == channel.id }) {
            updated[index] = channel
        } else {
            updated.append(channel)
        }
        try validate(updated)
        return sorted(updated)
    }

    static func insertBlankChannel(into channels: [ChannelMemory], afterLocation: Int?) throws -> (channels: [ChannelMemory], inserted: ChannelMemory) {
        try validate(channels)

        let insertLocation = try resolveInsertLocation(afterLocation: afterLocation, existingChannels: channels)
        let shifted = try shiftedChannels(channels, startingAt: insertLocation, by: 1)

        var inserted = ChannelMemory()
        inserted.location = String(insertLocation)

        let merged = sorted(shifted + [inserted])
        try validate(merged)
        return (merged, inserted)
    }

    static func pasteChannels(
        _ copiedChannels: [ChannelMemory],
        into channels: [ChannelMemory],
        afterLocation: Int?
    ) throws -> (channels: [ChannelMemory], pasted: [ChannelMemory]) {
        guard !copiedChannels.isEmpty else {
            return (sorted(channels), [])
        }

        try validate(channels)

        let insertLocation = try resolveInsertLocation(afterLocation: afterLocation, existingChannels: channels)
        let orderedCopies = sorted(copiedChannels)
        let shifted = try shiftedChannels(channels, startingAt: insertLocation, by: orderedCopies.count)

        let pasted = orderedCopies.enumerated().map { index, original -> ChannelMemory in
            var copy = original
            copy.id = UUID()
            copy.location = String(insertLocation + index)
            return copy
        }

        let merged = sorted(shifted + pasted)
        try validate(merged)
        return (merged, pasted)
    }

    static func sorted(_ channels: [ChannelMemory]) -> [ChannelMemory] {
        sorted(channels, by: .memory)
    }

    static func sorted(_ channels: [ChannelMemory], by mode: ChannelSortMode) -> [ChannelMemory] {
        channels.sorted {
            let lhsLocation = locationValue(for: $0) ?? Int.max
            let rhsLocation = locationValue(for: $1) ?? Int.max
            let lhsZone = zoneValue(for: $0) ?? Int.max
            let rhsZone = zoneValue(for: $1) ?? Int.max
            let lhsSlot = slotValue(for: $0) ?? Int.max
            let rhsSlot = slotValue(for: $1) ?? Int.max

            switch mode {
            case .memory:
                if lhsLocation == rhsLocation {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return lhsLocation < rhsLocation
            case .zone:
                if lhsZone == rhsZone {
                    if lhsSlot == rhsSlot {
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    return lhsSlot < rhsSlot
                }
                return lhsZone < rhsZone
            case .slot:
                if lhsSlot == rhsSlot {
                    if lhsZone == rhsZone {
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    return lhsZone < rhsZone
                }
                return lhsSlot < rhsSlot
            }
        }
    }

    static func zone(forLocation location: Int) -> Int {
        ((location - 1) / slotsPerZone) + 1
    }

    static func slot(forLocation location: Int) -> Int {
        ((location - 1) % slotsPerZone) + 1
    }

    static func location(forZone zone: Int, slot: Int) -> Int? {
        guard (1...zoneCount).contains(zone), (1...slotsPerZone).contains(slot) else {
            return nil
        }
        return ((zone - 1) * slotsPerZone) + slot
    }

    static func zoneValue(for channel: ChannelMemory) -> Int? {
        guard let location = locationValue(for: channel) else { return nil }
        return zone(forLocation: location)
    }

    static func slotValue(for channel: ChannelMemory) -> Int? {
        guard let location = locationValue(for: channel) else { return nil }
        return slot(forLocation: location)
    }

    static func zoneSummary(for zone: Int, channels: [ChannelMemory]) -> ChannelZoneSummary {
        let members = sorted(channels.filter { zoneValue(for: $0) == zone })
        return ChannelZoneSummary(zone: zone, channels: members, capacity: slotsPerZone)
    }

    static func zoneSummaries(from channels: [ChannelMemory]) -> [ChannelZoneSummary] {
        (1...zoneCount).map { zoneSummary(for: $0, channels: channels) }
    }

    static func channels(inZone zone: Int, from channels: [ChannelMemory]) -> [ChannelMemory] {
        sorted(channels.filter { zoneValue(for: $0) == zone })
    }

    static func requiredZone(_ value: String) throws -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let zone = Int(trimmed), (1...zoneCount).contains(zone) else {
            throw ChannelPlanError.invalidZone(value)
        }
        return zone
    }

    static func requiredZoneSlot(_ value: String) throws -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slot = Int(trimmed), (1...slotsPerZone).contains(slot) else {
            throw ChannelPlanError.invalidZoneSlot(value)
        }
        return slot
    }

    static func locationValue(for channel: ChannelMemory) -> Int? {
        let trimmed = channel.location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), (1...maxMemoryCount).contains(value) else {
            return nil
        }
        return value
    }

    static func requiredLocation(_ value: String) throws -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let location = Int(trimmed), (1...maxMemoryCount).contains(location) else {
            throw ChannelPlanError.invalidLocation(value)
        }
        return location
    }

    static func conflictingChannel(at location: Int, excluding channelID: UUID?, in channels: [ChannelMemory]) -> ChannelMemory? {
        channels.first {
            $0.id != channelID && locationValue(for: $0) == location
        }
    }

    private static func resolveInsertLocation(afterLocation: Int?, existingChannels: [ChannelMemory]) throws -> Int {
        if let afterLocation {
            guard (0...maxMemoryCount).contains(afterLocation) else {
                throw ChannelPlanError.invalidLocation(String(afterLocation))
            }
            let proposed = afterLocation + 1
            guard proposed <= maxMemoryCount else {
                throw ChannelPlanError.limitExceeded(limit: maxMemoryCount)
            }
            return proposed
        }

        let next = (existingChannels.compactMap(locationValue(for:)).max() ?? 0) + 1
        guard next <= maxMemoryCount else {
            throw ChannelPlanError.limitExceeded(limit: maxMemoryCount)
        }
        return next
    }

    private static func shiftedChannels(_ channels: [ChannelMemory], startingAt location: Int, by amount: Int) throws -> [ChannelMemory] {
        guard amount >= 0 else { return channels }

        return try channels.map { channel in
            var updated = channel
            let currentLocation = try requiredLocation(channel.location)
            if currentLocation >= location {
                let newLocation = currentLocation + amount
                guard newLocation <= maxMemoryCount else {
                    throw ChannelPlanError.limitExceeded(limit: maxMemoryCount)
                }
                updated.location = String(newLocation)
            }
            return updated
        }
    }
}
