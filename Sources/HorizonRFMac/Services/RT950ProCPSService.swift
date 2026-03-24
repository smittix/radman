import Foundation

enum RT950ProCPSFormat: String, Hashable {
    case namedZoneArray = "Named Zone Array"
    case groupedChannelArrays = "Grouped Channel Arrays"
    case genericZoneArray = "Generic Zone Array"
    case unknown = "Unknown"
}

struct RT950ProCPSImportResult: Hashable {
    let fileName: String
    let format: RT950ProCPSFormat
    let zoneNames: [String]
    let notes: [String]
    let importedChannels: [ChannelMemory]
    let channelSlotCount: Int
    let templateDataBase64: String

    var importedZoneCount: Int { zoneNames.count }
    var importedChannelCount: Int { importedChannels.count }
    var hasZoneNames: Bool { !zoneNames.isEmpty }
    var hasChannels: Bool { !importedChannels.isEmpty }
}

enum RT950ProCPSServiceError: LocalizedError {
    case unsupportedFile
    case unsupportedChannelLayout(Int)
    case missingTemplate
    case invalidTemplate(String)
    case missingChannelObject(Int32)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "RadMan could not find a supported RT-950 Pro CPS channel layout in this .dat file."
        case let .unsupportedChannelLayout(length):
            return "This CPS file uses \(length) channel slots. RadMan currently manages RT-950 Pro CPS layouts around 960 slots and will not write this template safely."
        case .missingTemplate:
            return "Import an RT-950 Pro CPS file first, or choose a CPS template file before exporting."
        case let .invalidTemplate(message):
            return message
        case let .missingChannelObject(objectID):
            return "RadMan could not locate CPS channel object \(objectID) in the selected template."
        }
    }
}

private enum RT950PrimitiveType: UInt8 {
    case int32 = 8
}

private enum RT950BinaryType: UInt8 {
    case primitive = 0
    case string = 1
}

private enum RT950BinaryRecord: UInt8 {
    case serializedStreamHeader = 0
    case classWithId = 1
    case classWithMembersAndTypes = 5
    case binaryObjectString = 6
    case binaryArray = 7
    case memberReference = 9
    case objectNull = 10
    case messageEnd = 11
    case binaryLibrary = 12
    case arraySingleString = 17
}

private struct RT950ChannelArrayDescriptor {
    let range: Range<Int>
    let objectID: Int32
    let length: Int
    let channelObjectIDs: [Int32]
}

private struct RT950ZoneArrayDescriptor {
    let range: Range<Int>
    let objectID: Int32
    let zoneNames: [String]
}

private struct RT950CPSChannelSlot: Hashable {
    var receiveFrequency: String = ""
    var transmitFrequency: String = ""
    var receiveTone: String = "OFF"
    var transmitTone: String = "OFF"
    var signallingGroup: Int = 0
    var pttID: Int = 0
    var transmitPower: Int = 0
    var scrambler: Int = 0
    var learnFHSS: Int = 0
    var bandWide: Int = 0
    var encryption: Int = 0
    var busyLockout: Int = 0
    var scanAdd: Int = 0
    var transmitEnable: Int = 1
    var receiveModulation: Int = 0
    var fhssCode: String = ""
    var name: String = ""
}

private struct RT950ChannelObjectDescriptor {
    let objectID: Int32
    let range: Range<Int>
    let slot: RT950CPSChannelSlot
}

private struct RT950ChannelObjectSection {
    let range: Range<Int>
    let metadataObjectID: Int32
    let objects: [RT950ChannelObjectDescriptor]
}

private struct RT950ParsedTemplate {
    let templateData: Data
    let format: RT950ProCPSFormat
    let channelArrays: [RT950ChannelArrayDescriptor]
    let zoneArray: RT950ZoneArrayDescriptor?
    let channelSection: RT950ChannelObjectSection

    var slotCount: Int {
        channelArrays.reduce(0) { $0 + $1.length }
    }

    var orderedChannelObjectIDs: [Int32] {
        channelArrays.flatMap(\.channelObjectIDs)
    }

    var orderedSlots: [RT950CPSChannelSlot] {
        channelSection.objects.map(\.slot)
    }
}

private struct RT950BinaryScanner {
    let data: Data
    var offset: Int

    mutating func readByte() throws -> UInt8 {
        guard offset < data.count else {
            throw RT950ProCPSServiceError.unsupportedFile
        }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readInt32() throws -> Int32 {
        guard offset + 4 <= data.count else {
            throw RT950ProCPSServiceError.unsupportedFile
        }
        let value = data.withUnsafeBytes { rawBuffer in
            Int32(
                littleEndian: rawBuffer.loadUnaligned(
                    fromByteOffset: offset,
                    as: Int32.self
                )
            )
        }
        offset += 4
        return value
    }

    mutating func readLengthPrefixedString() throws -> String {
        var shift = 0
        var length = 0

        while true {
            let byte = try readByte()
            length |= Int(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                break
            }
            shift += 7
        }

        guard offset + length <= data.count else {
            throw RT950ProCPSServiceError.unsupportedFile
        }

        let stringData = data[offset..<(offset + length)]
        offset += length
        return String(data: stringData, encoding: .utf8) ?? ""
    }
}

private struct RT950BinaryWriter {
    var data = Data()

    mutating func writeByte(_ value: UInt8) {
        data.append(value)
    }

    mutating func writeInt32(_ value: Int32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    mutating func writeLengthPrefixedString(_ value: String) {
        let utf8 = Array(value.utf8)
        var length = utf8.count
        repeat {
            var next = UInt8(length & 0x7F)
            length >>= 7
            if length > 0 {
                next |= 0x80
            }
            data.append(next)
        } while length > 0
        data.append(contentsOf: utf8)
    }
}

enum RT950ProCPSService {
    private static let targetLibraryID: Int32 = 2
    private static let targetAssembly = "BT-RT950PRO_CPS, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null"
    private static let supportedSlotCount = ChannelPlanService.maxMemoryCount
    private static let genericZoneWords = [
        "ZoneOne",
        "ZoneTwo",
        "ZoneThree",
        "ZoneFour",
        "ZoneFive",
        "ZoneSix",
        "ZoneSeven",
        "ZoneEight",
        "ZoneNine",
        "ZoneTen",
        "ZoneEleven",
        "ZoneTwelve",
        "ZoneThirteen",
        "ZoneFourteen",
        "ZoneFifteen",
    ]
    private static let channelMemberNames = [
        "rxFreq",
        "txFreq",
        "rxQT",
        "txQT",
        "signallingGroup",
        "pttId",
        "txPower",
        "scram",
        "learnFHSS",
        "bandWide",
        "encrypt",
        "busyLockout",
        "scanAdd",
        "enableTx",
        "rxModulation",
        "fhssCode",
        "chName",
    ]
    private static let channelMemberTypes: [(UInt8, UInt8?)] = [
        (RT950BinaryType.string.rawValue, nil),
        (RT950BinaryType.string.rawValue, nil),
        (RT950BinaryType.string.rawValue, nil),
        (RT950BinaryType.string.rawValue, nil),
        (RT950BinaryType.primitive.rawValue, RT950PrimitiveType.int32.rawValue),
        (RT950BinaryType.primitive.rawValue, RT950PrimitiveType.int32.rawValue),
        (RT950BinaryType.primitive.rawValue, RT950PrimitiveType.int32.rawValue),
        (RT950BinaryType.primitive.rawValue, RT950PrimitiveType.int32.rawValue),
        (RT950BinaryType.primitive.rawValue, RT950PrimitiveType.int32.rawValue),
        (RT950BinaryType.primitive.rawValue, RT950PrimitiveType.int32.rawValue),
        (RT950BinaryType.primitive.rawValue, RT950PrimitiveType.int32.rawValue),
        (RT950BinaryType.primitive.rawValue, RT950PrimitiveType.int32.rawValue),
        (RT950BinaryType.primitive.rawValue, RT950PrimitiveType.int32.rawValue),
        (RT950BinaryType.primitive.rawValue, RT950PrimitiveType.int32.rawValue),
        (RT950BinaryType.primitive.rawValue, RT950PrimitiveType.int32.rawValue),
        (RT950BinaryType.string.rawValue, nil),
        (RT950BinaryType.string.rawValue, nil),
    ]

    static func inspectFile(at url: URL) throws -> RT950ProCPSImportResult {
        let data = try Data(contentsOf: url)
        return inspect(data: data, fileName: url.lastPathComponent)
    }

    static func inspect(data: Data, fileName: String = "RT-950 Pro CPS.dat") -> RT950ProCPSImportResult {
        do {
            let parsed = try parseTemplate(data: data)
            let zoneNames = normalizedImportedZoneNames(parsed.zoneArray?.zoneNames ?? [], format: parsed.format)
            let channels = importableChannels(from: parsed)
            var notes: [String] = []

            if parsed.slotCount > supportedSlotCount {
                notes.append("This CPS file contains \(parsed.slotCount) channel slots. RadMan currently imports the first \(supportedSlotCount) supported RT-950 Pro positions.")
            }
            if parsed.format == .groupedChannelArrays {
                notes.append("Imported grouped zone arrays from the CPS file.")
            } else if zoneNames.isEmpty {
                notes.append("Imported channel memories from the CPS file.")
            } else {
                notes.append("Imported \(zoneNames.count) named zones and \(channels.count) populated channels from the CPS file.")
            }

            return RT950ProCPSImportResult(
                fileName: fileName,
                format: zoneNames.isEmpty && parsed.format == .namedZoneArray ? .genericZoneArray : parsed.format,
                zoneNames: zoneNames,
                notes: notes,
                importedChannels: channels,
                channelSlotCount: parsed.slotCount,
                templateDataBase64: data.base64EncodedString()
            )
        } catch {
            return RT950ProCPSImportResult(
                fileName: fileName,
                format: .unknown,
                zoneNames: [],
                notes: ["RadMan could not find a supported RT-950 Pro CPS channel layout in this file."],
                importedChannels: [],
                channelSlotCount: 0,
                templateDataBase64: ""
            )
        }
    }

    static func importCodeplug(at url: URL) throws -> RT950ProCPSImportResult {
        let data = try Data(contentsOf: url)
        let parsed = try parseTemplate(data: data)
        let zoneNames = normalizedImportedZoneNames(parsed.zoneArray?.zoneNames ?? [], format: parsed.format)
        var notes = ["Imported \(importableChannels(from: parsed).count) populated channels from \(url.lastPathComponent)."]
        if parsed.format == .groupedChannelArrays {
            notes.append("Imported grouped zone arrays from the CPS file.")
        }
        if !zoneNames.isEmpty {
            notes.append("Imported \(zoneNames.count) zone names from the CPS file.")
        }
        if parsed.slotCount > supportedSlotCount {
            notes.append("Skipped CPS positions above \(supportedSlotCount) because RadMan is currently running the 15x64 RT-950 Pro memory plan.")
        }

        return RT950ProCPSImportResult(
            fileName: url.lastPathComponent,
            format: zoneNames.isEmpty && parsed.format == .namedZoneArray ? .genericZoneArray : parsed.format,
            zoneNames: zoneNames,
            notes: notes,
            importedChannels: importableChannels(from: parsed),
            channelSlotCount: parsed.slotCount,
            templateDataBase64: data.base64EncodedString()
        )
    }

    static func exportCodeplug(
        channels: [ChannelMemory],
        zoneNames: [String],
        to url: URL,
        templateData: Data
    ) throws {
        let parsed = try parseTemplate(data: templateData)
        let updatedData = try applyingChannels(
            channels,
            zoneNames: zoneNames,
            to: parsed
        )
        try updatedData.write(to: url, options: .atomic)
    }

    private static func parseTemplate(data: Data) throws -> RT950ParsedTemplate {
        let channelArrays = try findChannelArrays(in: data)
        guard !channelArrays.isEmpty else {
            throw RT950ProCPSServiceError.unsupportedFile
        }

        let format: RT950ProCPSFormat
        if channelArrays.count == ChannelPlanService.zoneCount && channelArrays.allSatisfy({ $0.length == ChannelPlanService.slotsPerZone }) {
            format = .groupedChannelArrays
        } else if channelArrays.count == 1 {
            format = .namedZoneArray
        } else {
            format = .unknown
        }

        let zoneArray = try findZoneArray(in: data, startingAfter: channelArrays.last?.range.upperBound ?? 0)
        let channelSection = try parseChannelSection(
            in: data,
            objectIDs: channelArrays.flatMap(\.channelObjectIDs),
            startingAfter: max(channelArrays.last?.range.upperBound ?? 0, zoneArray?.range.upperBound ?? 0)
        )

        return RT950ParsedTemplate(
            templateData: data,
            format: format,
            channelArrays: channelArrays,
            zoneArray: zoneArray,
            channelSection: channelSection
        )
    }

    private static func findChannelArrays(in data: Data) throws -> [RT950ChannelArrayDescriptor] {
        var descriptors: [RT950ChannelArrayDescriptor] = []
        var index = 0

        while index < data.count - 24 {
            guard data[index] == RT950BinaryRecord.binaryArray.rawValue else {
                index += 1
                continue
            }

            if let descriptor = try parseChannelArrayDescriptor(in: data, at: index) {
                descriptors.append(descriptor)
                index = descriptor.range.upperBound
            } else {
                index += 1
            }
        }

        return descriptors
    }

    private static func parseChannelArrayDescriptor(in data: Data, at offset: Int) throws -> RT950ChannelArrayDescriptor? {
        var scanner = RT950BinaryScanner(data: data, offset: offset)
        guard try scanner.readByte() == RT950BinaryRecord.binaryArray.rawValue else {
            return nil
        }

        let objectID = try scanner.readInt32()
        let arrayType = try scanner.readByte()
        let rank = try scanner.readInt32()
        let length = Int(try scanner.readInt32())
        let memberType = try scanner.readByte()
        let typeName = try scanner.readLengthPrefixedString()
        _ = try scanner.readInt32()

        guard arrayType == 0, rank == 1, memberType == 4, typeName == "KDH.Channel", length > 0 else {
            return nil
        }

        var objectIDs: [Int32] = []
        objectIDs.reserveCapacity(length)

        for _ in 0..<length {
            guard try scanner.readByte() == RT950BinaryRecord.memberReference.rawValue else {
                return nil
            }
            objectIDs.append(try scanner.readInt32())
        }

        return RT950ChannelArrayDescriptor(
            range: offset..<scanner.offset,
            objectID: objectID,
            length: length,
            channelObjectIDs: objectIDs
        )
    }

    private static func findZoneArray(in data: Data, startingAfter start: Int) throws -> RT950ZoneArrayDescriptor? {
        var index = start
        while index < data.count - 16 {
            guard data[index] == RT950BinaryRecord.arraySingleString.rawValue else {
                index += 1
                continue
            }

            var scanner = RT950BinaryScanner(data: data, offset: index)
            _ = try scanner.readByte()
            let objectID = try scanner.readInt32()
            let length = Int(try scanner.readInt32())
            guard length == ChannelPlanService.zoneCount else {
                index += 1
                continue
            }

            var names: [String] = []
            var stringTable: [Int32: String] = [:]
            for _ in 0..<length {
                names.append(try parseStringLike(in: data, scanner: &scanner, stringTable: &stringTable, defaultValue: ""))
            }

            return RT950ZoneArrayDescriptor(
                range: index..<scanner.offset,
                objectID: objectID,
                zoneNames: names
            )
        }
        return nil
    }

    private static func parseChannelSection(
        in data: Data,
        objectIDs: [Int32],
        startingAfter start: Int
    ) throws -> RT950ChannelObjectSection {
        guard let firstObjectID = objectIDs.first else {
            throw RT950ProCPSServiceError.unsupportedFile
        }

        let firstRecordPrefix = Data([RT950BinaryRecord.classWithMembersAndTypes.rawValue])
            + withUnsafeBytes(of: firstObjectID.littleEndian, Array.init)
            + Data([0x0B]) + Data("KDH.Channel".utf8)
        guard let startOffset = data.range(of: firstRecordPrefix, options: [], in: start..<data.count)?.lowerBound else {
            throw RT950ProCPSServiceError.invalidTemplate("RadMan could not locate the CPS channel object section in this template.")
        }

        var stringTable = seedStringTable(in: data, upTo: startOffset)
        var scanner = RT950BinaryScanner(data: data, offset: startOffset)
        var objects: [RT950ChannelObjectDescriptor] = []
        objects.reserveCapacity(objectIDs.count)
        var metadataObjectID: Int32?

        for expectedObjectID in objectIDs {
            let objectStart = scanner.offset
            let recordType = try scanner.readByte()

            switch recordType {
            case RT950BinaryRecord.classWithMembersAndTypes.rawValue:
                let objectID = try scanner.readInt32()
                let className = try scanner.readLengthPrefixedString()
                let memberCount = Int(try scanner.readInt32())
                guard objectID == expectedObjectID, className == "KDH.Channel", memberCount == channelMemberNames.count else {
                    throw RT950ProCPSServiceError.invalidTemplate("The selected CPS template does not contain a compatible KDH.Channel object layout.")
                }
                for expectedName in channelMemberNames {
                    let found = try scanner.readLengthPrefixedString()
                    guard found == expectedName else {
                        throw RT950ProCPSServiceError.invalidTemplate("The selected CPS template uses an unexpected channel member layout.")
                    }
                }

                for (binaryType, _) in channelMemberTypes {
                    guard try scanner.readByte() == binaryType else {
                        throw RT950ProCPSServiceError.invalidTemplate("The selected CPS template uses unsupported channel member types.")
                    }
                }

                for (_, primitive) in channelMemberTypes {
                    if let primitive {
                        guard try scanner.readByte() == primitive else {
                            throw RT950ProCPSServiceError.invalidTemplate("The selected CPS template uses unsupported primitive channel members.")
                        }
                    }
                }
                _ = try scanner.readInt32()
                metadataObjectID = objectID
            case RT950BinaryRecord.classWithId.rawValue:
                let objectID = try scanner.readInt32()
                let classMetadataID = try scanner.readInt32()
                guard objectID == expectedObjectID, classMetadataID == metadataObjectID else {
                    throw RT950ProCPSServiceError.invalidTemplate("The selected CPS template contains an unexpected channel metadata reference.")
                }
            default:
                throw RT950ProCPSServiceError.invalidTemplate("RadMan encountered an unexpected channel object record in the selected CPS template.")
            }

            let slot = try parseChannelSlot(in: data, scanner: &scanner, stringTable: &stringTable)
            objects.append(
                RT950ChannelObjectDescriptor(
                    objectID: expectedObjectID,
                    range: objectStart..<scanner.offset,
                    slot: slot
                )
            )
        }

        guard let metadataObjectID else {
            throw RT950ProCPSServiceError.invalidTemplate("The selected CPS template does not include a complete channel metadata record.")
        }

        return RT950ChannelObjectSection(
            range: startOffset..<scanner.offset,
            metadataObjectID: metadataObjectID,
            objects: objects
        )
    }

    private static func parseChannelSlot(
        in data: Data,
        scanner: inout RT950BinaryScanner,
        stringTable: inout [Int32: String]
    ) throws -> RT950CPSChannelSlot {
        RT950CPSChannelSlot(
            receiveFrequency: try parseStringLike(in: data, scanner: &scanner, stringTable: &stringTable, defaultValue: ""),
            transmitFrequency: try parseStringLike(in: data, scanner: &scanner, stringTable: &stringTable, defaultValue: ""),
            receiveTone: try parseStringLike(in: data, scanner: &scanner, stringTable: &stringTable, defaultValue: "OFF"),
            transmitTone: try parseStringLike(in: data, scanner: &scanner, stringTable: &stringTable, defaultValue: "OFF"),
            signallingGroup: Int(try scanner.readInt32()),
            pttID: Int(try scanner.readInt32()),
            transmitPower: Int(try scanner.readInt32()),
            scrambler: Int(try scanner.readInt32()),
            learnFHSS: Int(try scanner.readInt32()),
            bandWide: Int(try scanner.readInt32()),
            encryption: Int(try scanner.readInt32()),
            busyLockout: Int(try scanner.readInt32()),
            scanAdd: Int(try scanner.readInt32()),
            transmitEnable: Int(try scanner.readInt32()),
            receiveModulation: Int(try scanner.readInt32()),
            fhssCode: try parseStringLike(in: data, scanner: &scanner, stringTable: &stringTable, defaultValue: ""),
            name: try parseStringLike(in: data, scanner: &scanner, stringTable: &stringTable, defaultValue: "")
        )
    }

    private static func parseStringLike(
        in data: Data,
        scanner: inout RT950BinaryScanner,
        stringTable: inout [Int32: String],
        defaultValue: String
    ) throws -> String {
        let recordType = try scanner.readByte()
        switch recordType {
        case RT950BinaryRecord.binaryObjectString.rawValue:
            let objectID = try scanner.readInt32()
            let value = try scanner.readLengthPrefixedString()
            stringTable[objectID] = value
            return value
        case RT950BinaryRecord.memberReference.rawValue:
            let referenceID = try scanner.readInt32()
            return stringTable[referenceID] ?? defaultValue
        case RT950BinaryRecord.objectNull.rawValue:
            return defaultValue
        default:
            throw RT950ProCPSServiceError.invalidTemplate("The selected CPS template contains an unsupported string record.")
        }
    }

    private static func seedStringTable(in data: Data, upTo upperBound: Int) -> [Int32: String] {
        guard upperBound > 6 else { return [:] }

        var table: [Int32: String] = [:]
        var index = 0

        while index < upperBound - 6 {
            guard data[index] == RT950BinaryRecord.binaryObjectString.rawValue else {
                index += 1
                continue
            }

            do {
                var scanner = RT950BinaryScanner(data: data, offset: index)
                _ = try scanner.readByte()
                let objectID = try scanner.readInt32()
                let value = try scanner.readLengthPrefixedString()
                if objectID > 0, value.count <= 64 {
                    table[objectID] = value
                    index = scanner.offset
                    continue
                }
            } catch {
            }

            index += 1
        }

        return table
    }

    private static func normalizedImportedZoneNames(_ zoneNames: [String], format: RT950ProCPSFormat) -> [String] {
        let trimmed = zoneNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard format == .namedZoneArray else {
            return []
        }
        if isGenericZoneArray(trimmed) {
            return []
        }
        return trimmed
    }

    private static func isGenericZoneArray(_ zoneNames: [String]) -> Bool {
        guard zoneNames.count == genericZoneWords.count else { return false }
        return zip(zoneNames, genericZoneWords).allSatisfy { lhs, rhs in
            lhs.caseInsensitiveCompare(rhs) == .orderedSame
        }
    }

    private static func importableChannels(from parsed: RT950ParsedTemplate) -> [ChannelMemory] {
        var imported: [ChannelMemory] = []
        let orderedSlots = parsed.orderedSlots

        switch parsed.format {
        case .groupedChannelArrays:
            var index = 0
            for zoneIndex in parsed.channelArrays.indices {
                for slotIndex in 0..<parsed.channelArrays[zoneIndex].length {
                    guard index < orderedSlots.count else { break }
                    let location = (zoneIndex * ChannelPlanService.slotsPerZone) + slotIndex + 1
                    if location <= supportedSlotCount, let channel = makeChannel(from: orderedSlots[index], location: location) {
                        imported.append(channel)
                    }
                    index += 1
                }
            }
        default:
            for (index, slot) in orderedSlots.enumerated() {
                let location = index + 1
                guard location <= supportedSlotCount else { continue }
                if let channel = makeChannel(from: slot, location: location) {
                    imported.append(channel)
                }
            }
        }

        return ChannelPlanService.sorted(imported)
    }

    private static func makeChannel(from slot: RT950CPSChannelSlot, location: Int) -> ChannelMemory? {
        let trimmedRx = slot.receiveFrequency.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = slot.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRx.isEmpty || !trimmedName.isEmpty else {
            return nil
        }

        var channel = ChannelMemory()
        channel.location = String(location)
        channel.name = trimmedName
        channel.frequency = formatImportedFrequency(trimmedRx)
        applyTransmitFrequency(from: slot, to: &channel)
        applyTones(from: slot, to: &channel)
        channel.mode = slot.receiveModulation == 1 ? "AM" : (slot.bandWide == 1 ? "NFM" : "FM")
        channel.power = powerLabel(from: slot.transmitPower)
        channel.skip = slot.scanAdd == 0 ? "S" : ""
        channel.nativeSignalGroup = String(max(0, slot.signallingGroup))
        channel.nativePTTID = String(max(0, slot.pttID))
        channel.nativeBusyLockout = slot.busyLockout != 0
        channel.nativeScrambler = String(max(0, slot.scrambler))
        channel.nativeEncryption = String(max(0, slot.encryption))
        channel.nativeLearnFHSS = slot.learnFHSS != 0
        channel.nativeFHSSCode = slot.fhssCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return channel
    }

    private static func applyingChannels(
        _ channels: [ChannelMemory],
        zoneNames: [String],
        to parsed: RT950ParsedTemplate
    ) throws -> Data {
        let exportablePrefixCount = min(parsed.slotCount, supportedSlotCount)
        var slots = parsed.orderedSlots

        if slots.count < parsed.slotCount {
            slots += Array(repeating: RT950CPSChannelSlot(), count: parsed.slotCount - slots.count)
        }

        for index in 0..<exportablePrefixCount {
            slots[index] = RT950CPSChannelSlot()
        }

        for channel in channels {
            guard let location = ChannelPlanService.locationValue(for: channel), location >= 1, location <= exportablePrefixCount else {
                continue
            }
            slots[location - 1] = cpsSlot(from: channel)
        }

        var result = parsed.templateData

        if let zoneArray = parsed.zoneArray {
            let normalizedZoneNames = ChannelPlanService.normalizedZoneNames(zoneNames)
            let zoneBytes = serializeZoneArray(
                objectID: zoneArray.objectID,
                zoneNames: normalizedZoneNames,
                nextStringObjectID: Int32(parsed.orderedChannelObjectIDs.max() ?? 0) + 10_000
            )
            result.replaceSubrange(zoneArray.range, with: zoneBytes)
        }

        let sectionBytes = serializeChannelObjectSection(
            objectIDs: parsed.orderedChannelObjectIDs,
            slots: slots,
            metadataObjectID: parsed.channelSection.metadataObjectID,
            nextStringObjectID: Int32(parsed.orderedChannelObjectIDs.max() ?? 0) + 1_000
        )
        result.replaceSubrange(parsed.channelSection.range, with: sectionBytes)
        return result
    }

    private static func serializeZoneArray(
        objectID: Int32,
        zoneNames: [String],
        nextStringObjectID: Int32
    ) -> Data {
        var writer = RT950BinaryWriter()
        var nextID = nextStringObjectID

        writer.writeByte(RT950BinaryRecord.arraySingleString.rawValue)
        writer.writeInt32(objectID)
        writer.writeInt32(Int32(ChannelPlanService.zoneCount))

        for name in zoneNames.prefix(ChannelPlanService.zoneCount) {
            writer.writeByte(RT950BinaryRecord.binaryObjectString.rawValue)
            writer.writeInt32(nextID)
            writer.writeLengthPrefixedString(name)
            nextID += 1
        }

        return writer.data
    }

    private static func serializeChannelObjectSection(
        objectIDs: [Int32],
        slots: [RT950CPSChannelSlot],
        metadataObjectID: Int32,
        nextStringObjectID: Int32
    ) -> Data {
        var writer = RT950BinaryWriter()
        var nextStringID = nextStringObjectID

        for (index, objectID) in objectIDs.enumerated() {
            let slot = index < slots.count ? slots[index] : RT950CPSChannelSlot()
            if index == 0 {
                writeChannelMetadataRecord(writer: &writer, objectID: objectID)
            } else {
                writer.writeByte(RT950BinaryRecord.classWithId.rawValue)
                writer.writeInt32(objectID)
                writer.writeInt32(metadataObjectID)
            }
            writeChannelMemberValues(writer: &writer, slot: slot, nextStringObjectID: &nextStringID)
        }

        return writer.data
    }

    private static func writeChannelMetadataRecord(writer: inout RT950BinaryWriter, objectID: Int32) {
        writer.writeByte(RT950BinaryRecord.classWithMembersAndTypes.rawValue)
        writer.writeInt32(objectID)
        writer.writeLengthPrefixedString("KDH.Channel")
        writer.writeInt32(Int32(channelMemberNames.count))

        for memberName in channelMemberNames {
            writer.writeLengthPrefixedString(memberName)
        }
        for (binaryType, _) in channelMemberTypes {
            writer.writeByte(binaryType)
        }
        for (_, primitive) in channelMemberTypes {
            if let primitive {
                writer.writeByte(primitive)
            }
        }
        writer.writeInt32(targetLibraryID)
    }

    private static func writeChannelMemberValues(
        writer: inout RT950BinaryWriter,
        slot: RT950CPSChannelSlot,
        nextStringObjectID: inout Int32
    ) {
        for value in [
            slot.receiveFrequency,
            slot.transmitFrequency,
            slot.receiveTone.ifEmpty("OFF"),
            slot.transmitTone.ifEmpty("OFF"),
        ] {
            writeBinaryString(value, writer: &writer, nextStringObjectID: &nextStringObjectID)
        }

        for numeric in [
            slot.signallingGroup,
            slot.pttID,
            slot.transmitPower,
            slot.scrambler,
            slot.learnFHSS,
            slot.bandWide,
            slot.encryption,
            slot.busyLockout,
            slot.scanAdd,
            slot.transmitEnable,
            slot.receiveModulation,
        ] {
            writer.writeInt32(Int32(numeric))
        }

        writeBinaryString(slot.fhssCode, writer: &writer, nextStringObjectID: &nextStringObjectID)
        writeBinaryString(slot.name, writer: &writer, nextStringObjectID: &nextStringObjectID)
    }

    private static func writeBinaryString(
        _ value: String,
        writer: inout RT950BinaryWriter,
        nextStringObjectID: inout Int32
    ) {
        writer.writeByte(RT950BinaryRecord.binaryObjectString.rawValue)
        writer.writeInt32(nextStringObjectID)
        writer.writeLengthPrefixedString(value)
        nextStringObjectID += 1
    }

    private static func cpsSlot(from channel: ChannelMemory) -> RT950CPSChannelSlot {
        let normalized = (try? RadManValidationService.normalizeChannel(channel)) ?? channel
        let rxFrequency = cpsFrequency(normalized.frequency)
        let txFrequency: String
        let txEnabled = normalized.duplex.lowercased() != "off" && !rxFrequency.isEmpty

        if !txEnabled {
            txFrequency = rxFrequency
        } else if normalized.duplex == "split" {
            txFrequency = cpsFrequency(normalized.offset)
        } else if normalized.duplex == "+" || normalized.duplex == "-" {
            txFrequency = deriveOffsetTransmitFrequency(from: normalized) ?? rxFrequency
        } else {
            txFrequency = rxFrequency
        }

        let tones = cpsTones(from: normalized)
        return RT950CPSChannelSlot(
            receiveFrequency: rxFrequency,
            transmitFrequency: txFrequency,
            receiveTone: tones.rx,
            transmitTone: tones.tx,
            signallingGroup: max(0, Int(normalized.nativeSignalGroup) ?? 0),
            pttID: max(0, Int(normalized.nativePTTID) ?? 0),
            transmitPower: powerRawValue(from: normalized.power),
            scrambler: max(0, Int(normalized.nativeScrambler) ?? 0),
            learnFHSS: normalized.nativeLearnFHSS ? 1 : 0,
            bandWide: normalized.mode.uppercased() == "NFM" ? 1 : 0,
            encryption: max(0, Int(normalized.nativeEncryption) ?? 0),
            busyLockout: normalized.nativeBusyLockout ? 1 : 0,
            scanAdd: normalized.skip.uppercased() == "S" ? 0 : 1,
            transmitEnable: txEnabled ? 1 : 0,
            receiveModulation: normalized.mode.uppercased() == "AM" ? 1 : 0,
            fhssCode: normalized.nativeFHSSCode,
            name: normalized.name
        )
    }

    private static func cpsFrequency(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let numeric = Double(trimmed), !trimmed.isEmpty else { return "" }
        return String(format: "%.5f", numeric)
    }

    private static func deriveOffsetTransmitFrequency(from channel: ChannelMemory) -> String? {
        guard
            let rx = Double(channel.frequency.trimmingCharacters(in: .whitespacesAndNewlines)),
            let offset = Double(channel.offset.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return nil
        }

        let tx = channel.duplex == "+" ? rx + offset : rx - offset
        return String(format: "%.5f", tx)
    }

    private static func cpsTones(from channel: ChannelMemory) -> (rx: String, tx: String) {
        let txTone = channel.rToneFreq.trimmingCharacters(in: .whitespacesAndNewlines)
        let rxTone = channel.cToneFreq.trimmingCharacters(in: .whitespacesAndNewlines)
        let dtcs = channel.dtcsCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let rxDtcs = channel.rxDtcsCode.trimmingCharacters(in: .whitespacesAndNewlines)

        switch channel.tone.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Tone":
            return ("OFF", txTone.ifEmpty("OFF"))
        case "TSQL":
            return (rxTone.ifEmpty(txTone.ifEmpty("OFF")), txTone.ifEmpty(rxTone.ifEmpty("OFF")))
        case "DTCS":
            return (rxDtcs.ifEmpty(dtcs.ifEmpty("OFF")), dtcs.ifEmpty(rxDtcs.ifEmpty("OFF")))
        case "Cross":
            return (rxTone.ifEmpty(rxDtcs.ifEmpty("OFF")), txTone.ifEmpty(dtcs.ifEmpty("OFF")))
        default:
            return ("OFF", "OFF")
        }
    }

    private static func applyTransmitFrequency(from slot: RT950CPSChannelSlot, to channel: inout ChannelMemory) {
        let rx = slot.receiveFrequency.trimmingCharacters(in: .whitespacesAndNewlines)
        let tx = slot.transmitFrequency.trimmingCharacters(in: .whitespacesAndNewlines)

        guard slot.transmitEnable != 0 else {
            channel.duplex = "off"
            channel.offset = ""
            return
        }

        guard
            let rxValue = Double(rx),
            let txValue = Double(tx),
            !rx.isEmpty,
            !tx.isEmpty
        else {
            channel.duplex = ""
            channel.offset = ""
            return
        }

        let delta = txValue - rxValue
        if abs(delta) < 0.000001 {
            channel.duplex = ""
            channel.offset = ""
        } else if delta > 0 {
            channel.duplex = "+"
            channel.offset = String(format: "%.6f", abs(delta))
        } else if delta < 0 {
            channel.duplex = "-"
            channel.offset = String(format: "%.6f", abs(delta))
        } else {
            channel.duplex = "split"
            channel.offset = formatImportedFrequency(tx)
        }
    }

    private static func applyTones(from slot: RT950CPSChannelSlot, to channel: inout ChannelMemory) {
        let rx = normalizedToneValue(slot.receiveTone)
        let tx = normalizedToneValue(slot.transmitTone)

        switch (tx, rx) {
        case ("", ""):
            break
        case let (txTone, "") where isCTCSS(txTone):
            channel.tone = "Tone"
            channel.rToneFreq = txTone
        case let (txTone, rxTone) where isCTCSS(txTone) && isCTCSS(rxTone):
            if txTone == rxTone {
                channel.tone = "TSQL"
            } else {
                channel.tone = "Cross"
                channel.crossMode = "Tone->Tone"
            }
            channel.rToneFreq = txTone
            channel.cToneFreq = rxTone
        case let (txDtcs, rxDtcs) where isDTCS(txDtcs) || isDTCS(rxDtcs):
            if txDtcs == rxDtcs {
                channel.tone = "DTCS"
            } else {
                channel.tone = "Cross"
            }
            channel.dtcsCode = txDtcs
            channel.rxDtcsCode = rxDtcs.ifEmpty(txDtcs)
            channel.dtcsPolarity = "NN"
        default:
            break
        }
    }

    private static func normalizedToneValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.caseInsensitiveCompare("OFF") == .orderedSame ? "" : trimmed
    }

    private static func isCTCSS(_ value: String) -> Bool {
        !value.isEmpty && Double(value) != nil
    }

    private static func isDTCS(_ value: String) -> Bool {
        !value.isEmpty && Int(value) != nil && value.count <= 3
    }

    private static func formatImportedFrequency(_ value: String) -> String {
        (try? RadManValidationService.normalizeMHz(value)) ?? value
    }

    private static func powerLabel(from rawValue: Int) -> String {
        switch rawValue {
        case 1:
            return "Medium"
        case 2:
            return "Low"
        default:
            return "High"
        }
    }

    private static func powerRawValue(from label: String) -> Int {
        switch label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "medium", "mid":
            return 1
        case "low":
            return 2
        default:
            return 0
        }
    }
}
