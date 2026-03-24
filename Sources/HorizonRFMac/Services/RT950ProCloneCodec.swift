import CoreFoundation
import Foundation

struct RT950ProNamedValue: Identifiable, Hashable {
    let key: String
    let value: String

    var id: String { key }
}

struct RT950ProVFOEntry: Identifiable, Hashable {
    let index: Int
    let frequency: String
    let offset: String
    let direction: String
    let mode: String
    let power: String
    let busyLockout: Bool

    var id: Int { index }
}

struct RT950ProDTMFSummary: Hashable {
    let currentID: String
    let pttMode: String
    let codeGroups: [String]
}

struct RT950ProDTMFEntry: Identifiable, Hashable {
    let id = "dtmf"
    var currentID: String
    var pttMode: String
    var codeGroups: [String]

    var populatedCodeGroups: [String] {
        codeGroups
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct RT950ProAPRSEntry: Identifiable, Hashable {
    let id = "aprs"
    var aprsEnabled: Bool
    var gpsEnabled: Bool
    var timeZone: String
    var callSign: String
    var ssid: String
    var routingSelect: String
    var myPosition: String
    var radioSymbol: String
    var aprsPriority: String
    var beaconTxType: String
    var customRoutingOne: String
    var customRoutingTwo: String
    var sendCustomMessages: Bool
    var customMessages: String
}

struct RT950ProFunctionSettingsEntry: Identifiable {
    let id = "core-settings"
    var values: [String: String]

    subscript(key: String) -> String {
        get { values[key, default: ""] }
        set { values[key] = newValue }
    }
}

struct RT950ProFunctionSettingDescriptor: Identifiable {
    enum ValueKind {
        case toggle
        case numeric(min: Int, max: Int)
    }

    let key: String
    let byteOffset: Int
    let mask: UInt8
    let shift: Int
    let kind: ValueKind

    var id: String { key }
}

struct RT950ProCloneSummary: Hashable {
    let channelCount: Int
    let vfos: [RT950ProVFOEntry]
    let functionSettings: [RT950ProNamedValue]
    let dtmf: RT950ProDTMFSummary
    let aprsFields: [RT950ProNamedValue]
}

enum RT950ProCloneCodecError: LocalizedError {
    case cloneTooSmall(Int)
    case invalidLocation(String)
    case invalidFrequency(String)
    case invalidToneValue(String)
    case invalidDCSCode(String)
    case invalidCrossMode(String)
    case invalidFunctionSettingValue(key: String, value: String)
    case invalidDTMFCharacter(Character)
    case invalidDTMFMode(String)

    var errorDescription: String? {
        switch self {
        case let .cloneTooSmall(size):
            return "The RT-950 Pro clone image is too small (\(size) bytes)."
        case let .invalidLocation(location):
            return "Channel location \(location) is outside the RT-950 Pro memory range."
        case let .invalidFrequency(value):
            return "Could not parse frequency value '\(value)'."
        case let .invalidToneValue(value):
            return "Could not parse tone value '\(value)'."
        case let .invalidDCSCode(value):
            return "Could not parse DCS code '\(value)'."
        case let .invalidCrossMode(value):
            return "Cross tone mode '\(value)' is not understood."
        case let .invalidFunctionSettingValue(key, value):
            return "Could not save \(key) with value '\(value)'."
        case let .invalidDTMFCharacter(character):
            return "The DTMF value contains an unsupported character '\(character)'."
        case let .invalidDTMFMode(value):
            return "Could not save DTMF PTT mode '\(value)'."
        }
    }
}

enum RT950ProCloneCodec {
    static let channelCount = 960
    static let channelSize = 32
    static let channelSectionBytes = channelCount * channelSize
    static let vfoSegmentBytes = 0x100
    static let vfoSectionBytes = 96
    static let functionSegmentBytes = 0x100
    static let functionSectionBytes = 96
    static let dtmfSegmentBytes = 0x200
    static let dtmfSectionBytes = 384
    static let modulationParameterSectionBytes = 0x200
    static let modulationNameSectionBytes = 0x300
    static let aprsSegmentBytes = 0x80
    static let aprsSectionBytes = 128
    static let functionSegmentOffset = channelSectionBytes + vfoSegmentBytes
    static let dtmfSegmentOffset = functionSegmentOffset + functionSegmentBytes
    static let aprsSegmentOffset = channelSectionBytes + vfoSegmentBytes + functionSegmentBytes + dtmfSegmentBytes + modulationParameterSectionBytes + modulationNameSectionBytes
    static let functionDataRange = functionSegmentOffset..<(functionSegmentOffset + functionSectionBytes)
    static let dtmfDataRange = dtmfSegmentOffset..<(dtmfSegmentOffset + dtmfSectionBytes)
    static let aprsSegmentRange = aprsSegmentOffset..<(aprsSegmentOffset + aprsSegmentBytes)
    static let aprsDataRange = aprsSegmentOffset..<(aprsSegmentOffset + aprsSectionBytes)
    static let editableFunctionSettingDescriptors: [RT950ProFunctionSettingDescriptor] = [
        RT950ProFunctionSettingDescriptor(key: "sql", byteOffset: 0, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "save_mode", byteOffset: 1, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "vox", byteOffset: 2, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "auto_backlight", byteOffset: 3, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "tdr", byteOffset: 4, mask: 0x0F, shift: 0, kind: .toggle),
        RT950ProFunctionSettingDescriptor(key: "tot", byteOffset: 5, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "beep_prompt", byteOffset: 6, mask: 0x0F, shift: 0, kind: .toggle),
        RT950ProFunctionSettingDescriptor(key: "voice_prompt", byteOffset: 7, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "language", byteOffset: 8, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "dtmf_mode", byteOffset: 9, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "scan_mode", byteOffset: 10, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "ptt_id", byteOffset: 11, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "send_id_delay", byteOffset: 12, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "display_mode_a", byteOffset: 13, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "display_mode_b", byteOffset: 14, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "display_mode_c", byteOffset: 15, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "auto_key_lock", byteOffset: 16, mask: 0x0F, shift: 0, kind: .toggle),
        RT950ProFunctionSettingDescriptor(key: "alarm_mode", byteOffset: 17, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "alarm_sound", byteOffset: 18, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "tail_noise_clear", byteOffset: 20, mask: 0x0F, shift: 0, kind: .toggle),
        RT950ProFunctionSettingDescriptor(key: "pass_repeater_noise_clear", byteOffset: 21, mask: 0x0F, shift: 0, kind: .toggle),
        RT950ProFunctionSettingDescriptor(key: "pass_repeater_noise_detect", byteOffset: 22, mask: 0x0F, shift: 0, kind: .toggle),
        RT950ProFunctionSettingDescriptor(key: "sound_tx_end", byteOffset: 23, mask: 0x0F, shift: 0, kind: .toggle),
        RT950ProFunctionSettingDescriptor(key: "current_work_mode", byteOffset: 24, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "fm_radio", byteOffset: 25, mask: 0x0F, shift: 0, kind: .toggle),
        RT950ProFunctionSettingDescriptor(key: "work_mode_a", byteOffset: 26, mask: 0x03, shift: 0, kind: .numeric(min: 0, max: 3)),
        RT950ProFunctionSettingDescriptor(key: "work_mode_b", byteOffset: 26, mask: 0x03, shift: 2, kind: .numeric(min: 0, max: 3)),
        RT950ProFunctionSettingDescriptor(key: "work_mode_c", byteOffset: 26, mask: 0x03, shift: 4, kind: .numeric(min: 0, max: 3)),
        RT950ProFunctionSettingDescriptor(key: "lock_keyboard", byteOffset: 27, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "power_on_message", byteOffset: 28, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "bt_write_switch", byteOffset: 29, mask: 0x0F, shift: 0, kind: .toggle),
        RT950ProFunctionSettingDescriptor(key: "rtone", byteOffset: 30, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "vox_delay", byteOffset: 32, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "timer_menu_quit", byteOffset: 33, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "weather_channel", byteOffset: 37, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "divide_channel", byteOffset: 38, mask: 0x0F, shift: 0, kind: .toggle),
        RT950ProFunctionSettingDescriptor(key: "subaudio_scan_save", byteOffset: 39, mask: 0x0F, shift: 0, kind: .toggle),
        RT950ProFunctionSettingDescriptor(key: "vox_switch", byteOffset: 40, mask: 0x0F, shift: 0, kind: .toggle),
        RT950ProFunctionSettingDescriptor(key: "key_side1_short", byteOffset: 41, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "key_side1_long", byteOffset: 42, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "key_side2_short", byteOffset: 43, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "key_side2_long", byteOffset: 44, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "current_work_area_a", byteOffset: 45, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "current_work_area_b", byteOffset: 46, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "current_work_area_c", byteOffset: 47, mask: 0x0F, shift: 0, kind: .numeric(min: 0, max: 15)),
        RT950ProFunctionSettingDescriptor(key: "ab_uv_transfer", byteOffset: 57, mask: 0x0F, shift: 0, kind: .toggle),
        RT950ProFunctionSettingDescriptor(key: "sound_transfer", byteOffset: 58, mask: 0x0F, shift: 0, kind: .toggle),
        RT950ProFunctionSettingDescriptor(key: "key0_long", byteOffset: 59, mask: 0x1F, shift: 0, kind: .numeric(min: 0, max: 31)),
        RT950ProFunctionSettingDescriptor(key: "key1_long", byteOffset: 60, mask: 0x1F, shift: 0, kind: .numeric(min: 0, max: 31)),
        RT950ProFunctionSettingDescriptor(key: "key2_long", byteOffset: 61, mask: 0x1F, shift: 0, kind: .numeric(min: 0, max: 31)),
        RT950ProFunctionSettingDescriptor(key: "key3_long", byteOffset: 62, mask: 0x1F, shift: 0, kind: .numeric(min: 0, max: 31)),
        RT950ProFunctionSettingDescriptor(key: "key4_long", byteOffset: 63, mask: 0x1F, shift: 0, kind: .numeric(min: 0, max: 31)),
        RT950ProFunctionSettingDescriptor(key: "key5_long", byteOffset: 64, mask: 0x1F, shift: 0, kind: .numeric(min: 0, max: 31)),
        RT950ProFunctionSettingDescriptor(key: "key6_long", byteOffset: 65, mask: 0x1F, shift: 0, kind: .numeric(min: 0, max: 31)),
        RT950ProFunctionSettingDescriptor(key: "key7_long", byteOffset: 66, mask: 0x1F, shift: 0, kind: .numeric(min: 0, max: 31)),
        RT950ProFunctionSettingDescriptor(key: "key8_long", byteOffset: 67, mask: 0x1F, shift: 0, kind: .numeric(min: 0, max: 31)),
        RT950ProFunctionSettingDescriptor(key: "key9_long", byteOffset: 68, mask: 0x1F, shift: 0, kind: .numeric(min: 0, max: 31)),
    ]

    static func summary(from cloneData: Data) throws -> RT950ProCloneSummary {
        guard cloneData.count >= channelSectionBytes else {
            throw RT950ProCloneCodecError.cloneTooSmall(cloneData.count)
        }

        let channels = try channels(from: cloneData)
        let tail = Data(cloneData.dropFirst(channelSectionBytes))

        let vfoSegment = Data(tail.prefix(vfoSegmentBytes))
        let functionStart = vfoSegmentBytes
        let functionEnd = functionStart + functionSegmentBytes
        let functionSegment = tail.count >= functionEnd ? Data(tail[functionStart..<functionEnd]) : Data()

        let dtmfStart = functionEnd
        let dtmfEnd = dtmfStart + dtmfSegmentBytes
        let dtmfSegment = tail.count >= dtmfEnd ? Data(tail[dtmfStart..<dtmfEnd]) : Data()

        let modulationParametersStart = dtmfEnd
        let modulationParametersEnd = modulationParametersStart + modulationParameterSectionBytes
        let modulationNamesStart = modulationParametersEnd
        let modulationNamesEnd = modulationNamesStart + modulationNameSectionBytes
        let aprsStart = modulationNamesEnd
        let aprsEnd = aprsStart + aprsSegmentBytes
        let aprsSegment = tail.count >= aprsEnd ? Data(tail[aprsStart..<aprsEnd]) : Data()

        return RT950ProCloneSummary(
            channelCount: channels.count,
            vfos: parseVFOs(from: Data(vfoSegment.prefix(vfoSectionBytes))),
            functionSettings: parseFunctionSettings(from: Data(functionSegment.prefix(functionSectionBytes))),
            dtmf: parseDTMF(from: Data(dtmfSegment.prefix(dtmfSectionBytes))),
            aprsFields: parseAPRS(from: Data(aprsSegment.prefix(aprsSectionBytes)))
        )
    }

    static func channels(from cloneData: Data) throws -> [ChannelMemory] {
        guard cloneData.count >= channelSectionBytes else {
            throw RT950ProCloneCodecError.cloneTooSmall(cloneData.count)
        }

        var channels: [ChannelMemory] = []
        for index in 0..<channelCount {
            let start = index * channelSize
            let end = start + channelSize
            let record = try decodeChannel(Data(cloneData[start..<end]), location: index + 1)
            if !record.isEffectivelyEmpty {
                channels.append(record)
            }
        }
        return channels
    }

    static func applyingChannels(_ channels: [ChannelMemory], to cloneData: Data) throws -> Data {
        guard cloneData.count >= channelSectionBytes else {
            throw RT950ProCloneCodecError.cloneTooSmall(cloneData.count)
        }

        var result = cloneData
        for channel in channels {
            let location = try parseLocation(channel.location)
            let start = (location - 1) * channelSize
            let end = start + channelSize
            let encoded = try encodeChannel(channel)
            result.replaceSubrange(start..<end, with: encoded)
        }
        return result
    }

    static func aprsEntry(from cloneData: Data) throws -> RT950ProAPRSEntry {
        guard cloneData.count >= aprsDataRange.upperBound else {
            throw RT950ProCloneCodecError.cloneTooSmall(cloneData.count)
        }

        let data = Data(cloneData[aprsDataRange])
        return RT950ProAPRSEntry(
            aprsEnabled: parseBoolLabel(data[0]),
            gpsEnabled: parseBoolLabel(data[1]),
            timeZone: parseMaskedValue(data[6], mask: 0x1F),
            callSign: decodeASCII(data, offset: 17, maxLength: 6),
            ssid: parseMaskedValue(data[23]),
            routingSelect: parseMaskedValue(data[24]),
            myPosition: parseMaskedValue(data[25]),
            radioSymbol: parseMaskedValue(data[26]),
            aprsPriority: parseMaskedValue(data[29]),
            beaconTxType: parseMaskedValue(data[34]),
            customRoutingOne: decodeASCII(data, offset: 43, maxLength: 6),
            customRoutingTwo: decodeASCII(data, offset: 50, maxLength: 6),
            sendCustomMessages: parseBoolLabel(data[78]),
            customMessages: decodeGB2312(Data(data[79..<119]), maxBytes: 40)
        )
    }

    static func dtmfEntry(from cloneData: Data) throws -> RT950ProDTMFEntry {
        guard cloneData.count >= dtmfDataRange.upperBound else {
            throw RT950ProCloneCodecError.cloneTooSmall(cloneData.count)
        }

        let data = Data(cloneData[dtmfDataRange])
        let info = Data(data[0..<32])
        let groups = Data(data[32..<dtmfSectionBytes])
        let currentID = decodeDTMFSequence(info[0..<5], maxLength: 5)
        let pttMode = info[6] == 0xFF ? "" : String(info[6] & 0x0F)

        var codeGroups: [String] = []
        for offset in stride(from: 0, to: groups.count, by: 16) {
            codeGroups.append(decodeDTMFSequence(groups[offset..<(offset + 16)], maxLength: 6))
        }

        return RT950ProDTMFEntry(currentID: currentID, pttMode: pttMode, codeGroups: codeGroups)
    }

    static func functionSettingsEntry(from cloneData: Data) throws -> RT950ProFunctionSettingsEntry {
        guard cloneData.count >= functionDataRange.upperBound else {
            throw RT950ProCloneCodecError.cloneTooSmall(cloneData.count)
        }
        return RT950ProFunctionSettingsEntry(values: parseFunctionSettingValues(from: Data(cloneData[functionDataRange])))
    }

    static func applyingFunctionSettings(_ entry: RT950ProFunctionSettingsEntry, to cloneData: Data) throws -> Data {
        guard cloneData.count >= functionDataRange.upperBound else {
            throw RT950ProCloneCodecError.cloneTooSmall(cloneData.count)
        }

        var result = cloneData
        var data = Array(result[functionDataRange])

        for descriptor in editableFunctionSettingDescriptors {
            let trimmed = entry[descriptor.key].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.localizedCaseInsensitiveContains("unset") else {
                continue
            }

            let rawValue = try rawFunctionValue(from: trimmed, descriptor: descriptor)
            let currentByte = data[descriptor.byteOffset] == 0xFF ? UInt8(0) : data[descriptor.byteOffset]
            let clearMask = UInt8((Int(descriptor.mask) << descriptor.shift) & 0xFF)
            let cleared = currentByte & ~clearMask
            let encodedBits = UInt8((rawValue & Int(descriptor.mask)) << descriptor.shift)
            data[descriptor.byteOffset] = cleared | encodedBits
        }

        result.replaceSubrange(functionDataRange, with: data)
        return result
    }

    static func applyingAPRS(_ entry: RT950ProAPRSEntry, to cloneData: Data) throws -> Data {
        guard cloneData.count >= aprsDataRange.upperBound else {
            throw RT950ProCloneCodecError.cloneTooSmall(cloneData.count)
        }

        var result = cloneData
        var data = Array(result[aprsDataRange])

        data[0] = entry.aprsEnabled ? 1 : 0
        data[1] = entry.gpsEnabled ? 1 : 0
        data[6] = encodeMaskedValue(entry.timeZone, mask: 0x1F)
        data.replaceSubrange(17..<23, with: Array(encodeASCII(entry.callSign, maxBytes: 6)))
        data[23] = encodeMaskedValue(entry.ssid, mask: 0x0F)
        data[24] = encodeMaskedValue(entry.routingSelect, mask: 0x0F)
        data[25] = encodeMaskedValue(entry.myPosition, mask: 0x0F)
        data[26] = encodeMaskedValue(entry.radioSymbol, mask: 0x0F)
        data[29] = encodeMaskedValue(entry.aprsPriority, mask: 0x0F)
        data[34] = encodeMaskedValue(entry.beaconTxType, mask: 0x0F)
        data.replaceSubrange(43..<49, with: Array(encodeASCII(entry.customRoutingOne, maxBytes: 6)))
        data.replaceSubrange(50..<56, with: Array(encodeASCII(entry.customRoutingTwo, maxBytes: 6)))
        data[78] = entry.sendCustomMessages ? 1 : 0
        data.replaceSubrange(79..<119, with: Array(encodeGB2312(entry.customMessages, maxBytes: 40)))

        result.replaceSubrange(aprsDataRange, with: data)
        return result
    }

    static func applyingDTMF(_ entry: RT950ProDTMFEntry, to cloneData: Data) throws -> Data {
        guard cloneData.count >= dtmfDataRange.upperBound else {
            throw RT950ProCloneCodecError.cloneTooSmall(cloneData.count)
        }

        var result = cloneData
        var data = Array(result[dtmfDataRange])

        data.replaceSubrange(0..<5, with: Array(try encodeDTMFSequence(entry.currentID, maxBytes: 5)))

        let trimmedMode = entry.pttMode.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedMode.isEmpty {
            data[6] = 0xFF
        } else if let modeValue = Int(trimmedMode), (0...15).contains(modeValue) {
            data[6] = UInt8(modeValue & 0x0F)
        } else {
            throw RT950ProCloneCodecError.invalidDTMFMode(entry.pttMode)
        }

        let groupRange = 32..<dtmfSectionBytes
        let groupCount = groupRange.count / 16
        for index in 0..<groupCount {
            let group = index < entry.codeGroups.count ? entry.codeGroups[index] : ""
            let start = 32 + (index * 16)
            data.replaceSubrange(start..<(start + 16), with: Array(try encodeDTMFSequence(group, maxBytes: 16, visibleLength: 6)))
        }

        result.replaceSubrange(dtmfDataRange, with: data)
        return result
    }

    private static func decodeChannel(_ data: Data, location: Int) throws -> ChannelMemory {
        let rxHz = try decodeFrequency(data[0..<4])
        guard let rxHz else {
            var empty = ChannelMemory()
            empty.location = String(location)
            return empty
        }

        let txHz = try decodeFrequency(data[4..<8])
        let rxTone = try decodeTone(data[8..<10])
        let txTone = try decodeTone(data[10..<12])
        let signallingGroup = Int(data[12] & 0x0F)
        let pttID = Int(data[13] & 0x0F)
        let powerRaw = Int(data[14] & 0x0F)
        let scrambler = Int((data[14] >> 4) & 0x0F)
        let flags = data[15]
        let busyLockout = (flags & 0x08) != 0
        let scanAdd = (flags & 0x04) != 0
        let txEnabled = (flags & 0x02) != 0
        let isAM = (flags & 0x01) != 0
        let isNarrow = ((flags >> 6) & 0x01) != 0
        let encryption = Int((flags >> 4) & 0x03)
        let learnFHSS = (flags & 0x80) != 0
        let fhssCode = decodeFHSSCode(data[16..<20])
        let name = decodeGB2312(data[20..<32], maxBytes: 12)

        var channel = ChannelMemory()
        channel.location = String(location)
        channel.name = name
        channel.frequency = formatMHz(rxHz)
        applyDuplex(txHz: txHz, rxHz: rxHz, txEnabled: txEnabled, to: &channel)
        applyTones(txTone: txTone, rxTone: rxTone, to: &channel)
        channel.mode = isAM ? "AM" : (isNarrow ? "NFM" : "FM")
        channel.power = powerLabel(from: powerRaw)
        channel.skip = scanAdd ? "" : "S"
        channel.nativeSignalGroup = String(signallingGroup)
        channel.nativePTTID = String(pttID)
        channel.nativeBusyLockout = busyLockout
        channel.nativeScrambler = String(scrambler)
        channel.nativeEncryption = String(encryption)
        channel.nativeLearnFHSS = learnFHSS
        channel.nativeFHSSCode = fhssCode ?? ""
        return channel
    }

    private static func encodeChannel(_ channel: ChannelMemory) throws -> Data {
        let trimmedFrequency = channel.frequency.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFrequency.isEmpty else {
            return Data(repeating: 0xFF, count: channelSize)
        }

        let rxHz = try parseFrequency(trimmedFrequency)
        let txEnabled = channel.duplex.lowercased() != "off"
        let txHz = try deriveTXFrequency(from: channel, rxHz: rxHz, txEnabled: txEnabled)
        let tonePair = try encodeTones(from: channel)

        var bytes = Data(repeating: 0xFF, count: channelSize)
        bytes.replaceSubrange(0..<4, with: encodeFrequency(rxHz))
        bytes.replaceSubrange(4..<8, with: encodeFrequency(txHz))
        bytes.replaceSubrange(8..<10, with: tonePair.rx)
        bytes.replaceSubrange(10..<12, with: tonePair.tx)
        bytes[12] = UInt8(clampedInt(channel.nativeSignalGroup, range: 0...15))
        bytes[13] = UInt8(clampedInt(channel.nativePTTID, range: 0...15))

        let powerValue = powerRawValue(from: channel.power)
        let scrambler = clampedInt(channel.nativeScrambler, range: 0...15)
        bytes[14] = UInt8((scrambler << 4) | powerValue)

        var flags = UInt8(0)
        if channel.nativeLearnFHSS {
            flags |= 0x80
        }
        if channel.mode.uppercased() == "NFM" {
            flags |= 0x40
        }
        flags |= UInt8(clampedInt(channel.nativeEncryption, range: 0...3) << 4)
        if channel.nativeBusyLockout {
            flags |= 0x08
        }
        if channel.skip.uppercased() != "S" {
            flags |= 0x04
        }
        if txEnabled {
            flags |= 0x02
        }
        if channel.mode.uppercased() == "AM" {
            flags |= 0x01
        }
        bytes[15] = flags
        bytes.replaceSubrange(16..<20, with: encodeFHSSCode(channel.nativeFHSSCode))
        bytes.replaceSubrange(20..<32, with: encodeGB2312(channel.name, maxBytes: 12))
        return bytes
    }

    private static func applyDuplex(txHz: Int?, rxHz: Int, txEnabled: Bool, to channel: inout ChannelMemory) {
        guard txEnabled else {
            channel.duplex = "off"
            channel.offset = ""
            return
        }

        guard let txHz else {
            channel.duplex = ""
            channel.offset = ""
            return
        }

        let diff = txHz - rxHz
        if diff == 0 {
            channel.duplex = ""
            channel.offset = ""
        } else if diff > 0 {
            channel.duplex = "+"
            channel.offset = formatMHz(abs(diff))
        } else {
            channel.duplex = "-"
            channel.offset = formatMHz(abs(diff))
        }
    }

    private static func applyTones(txTone: NativeToneSetting, rxTone: NativeToneSetting, to channel: inout ChannelMemory) {
        switch (txTone, rxTone) {
        case (.off, .off):
            channel.tone = ""
        case let (.ctcss(txHz), .off):
            channel.tone = "Tone"
            channel.rToneFreq = formatTone(txHz)
            channel.cToneFreq = ""
        case let (.ctcss(txHz), .ctcss(rxHz)):
            if abs(txHz - rxHz) < 0.05 {
                channel.tone = "TSQL"
                channel.rToneFreq = formatTone(txHz)
                channel.cToneFreq = formatTone(rxHz)
            } else {
                channel.tone = "Cross"
                channel.crossMode = "Tone->Tone"
                channel.rToneFreq = formatTone(txHz)
                channel.cToneFreq = formatTone(rxHz)
            }
        case let (.dcs(txCode, txPolarity), .dcs(rxCode, rxPolarity)):
            if txCode == rxCode {
                channel.tone = "DTCS"
                channel.dtcsCode = String(format: "%03d", txCode)
                channel.rxDtcsCode = String(format: "%03d", rxCode)
                channel.dtcsPolarity = txPolarity + rxPolarity
            } else {
                channel.tone = "Cross"
                channel.crossMode = "DTCS->DTCS"
                channel.dtcsCode = String(format: "%03d", txCode)
                channel.rxDtcsCode = String(format: "%03d", rxCode)
                channel.dtcsPolarity = txPolarity + rxPolarity
            }
        case let (.dcs(txCode, txPolarity), .off):
            channel.tone = "DTCS"
            channel.dtcsCode = String(format: "%03d", txCode)
            channel.rxDtcsCode = String(format: "%03d", txCode)
            channel.dtcsPolarity = txPolarity + "N"
        case let (.off, .dcs(rxCode, rxPolarity)):
            channel.tone = "Cross"
            channel.crossMode = "->DTCS"
            channel.rxDtcsCode = String(format: "%03d", rxCode)
            channel.dtcsPolarity = "N" + rxPolarity
        case let (.off, .ctcss(rxHz)):
            channel.tone = "Cross"
            channel.crossMode = "->Tone"
            channel.cToneFreq = formatTone(rxHz)
        case let (.ctcss(txHz), .dcs(rxCode, rxPolarity)):
            channel.tone = "Cross"
            channel.crossMode = "Tone->DTCS"
            channel.rToneFreq = formatTone(txHz)
            channel.rxDtcsCode = String(format: "%03d", rxCode)
            channel.dtcsPolarity = "N" + rxPolarity
        case let (.dcs(txCode, txPolarity), .ctcss(rxHz)):
            channel.tone = "Cross"
            channel.crossMode = "DTCS->Tone"
            channel.dtcsCode = String(format: "%03d", txCode)
            channel.dtcsPolarity = txPolarity + "N"
            channel.cToneFreq = formatTone(rxHz)
        }
    }

    private static func encodeTones(from channel: ChannelMemory) throws -> (rx: Data, tx: Data) {
        let toneMode = channel.tone.trimmingCharacters(in: .whitespacesAndNewlines)
        switch toneMode.uppercased() {
        case "":
            return (encodeTone(.off), encodeTone(.off))
        case "TONE":
            let tx = try toneFromCTCSS(channel.rToneFreq)
            return (encodeTone(.off), encodeTone(tx))
        case "TSQL":
            let tx = try toneFromCTCSS(channel.rToneFreq.isEmpty ? channel.cToneFreq : channel.rToneFreq)
            let rx = try toneFromCTCSS(channel.cToneFreq.isEmpty ? channel.rToneFreq : channel.cToneFreq)
            return (encodeTone(rx), encodeTone(tx))
        case "DTCS":
            let txCode = try parseDCSCode(channel.dtcsCode)
            let rxCode = try parseDCSCode(channel.rxDtcsCode.isEmpty ? channel.dtcsCode : channel.rxDtcsCode)
            let polarity = normalizedDTCSPolarity(channel.dtcsPolarity)
            return (
                encodeTone(.dcs(code: rxCode, polarity: String(polarity.last ?? "N"))),
                encodeTone(.dcs(code: txCode, polarity: String(polarity.first ?? "N")))
            )
        case "CROSS":
            let crossMode = channel.crossMode.trimmingCharacters(in: .whitespacesAndNewlines)
            return try encodeCrossTones(channel: channel, crossMode: crossMode)
        default:
            throw RT950ProCloneCodecError.invalidToneValue(channel.tone)
        }
    }

    private static func encodeCrossTones(channel: ChannelMemory, crossMode: String) throws -> (rx: Data, tx: Data) {
        let parts = crossMode.split(separator: ">", omittingEmptySubsequences: false).map(String.init)
        let tokens: [String]
        if crossMode.contains("->"), parts.count == 2 {
            tokens = parts.map { $0.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            throw RT950ProCloneCodecError.invalidCrossMode(crossMode)
        }

        let txTone: NativeToneSetting
        switch tokens[0].uppercased() {
        case "", "NONE":
            txTone = .off
        case "TONE":
            txTone = try toneFromCTCSS(channel.rToneFreq)
        case "DTCS":
            txTone = .dcs(code: try parseDCSCode(channel.dtcsCode), polarity: String(normalizedDTCSPolarity(channel.dtcsPolarity).first ?? "N"))
        default:
            throw RT950ProCloneCodecError.invalidCrossMode(crossMode)
        }

        let rxTone: NativeToneSetting
        switch tokens[1].uppercased() {
        case "", "NONE":
            rxTone = .off
        case "TONE":
            rxTone = try toneFromCTCSS(channel.cToneFreq.isEmpty ? channel.rToneFreq : channel.cToneFreq)
        case "DTCS":
            let codeSource = channel.rxDtcsCode.isEmpty ? channel.dtcsCode : channel.rxDtcsCode
            rxTone = .dcs(code: try parseDCSCode(codeSource), polarity: String(normalizedDTCSPolarity(channel.dtcsPolarity).last ?? "N"))
        default:
            throw RT950ProCloneCodecError.invalidCrossMode(crossMode)
        }

        return (encodeTone(rxTone), encodeTone(txTone))
    }

    private static func parseVFOs(from data: Data) -> [RT950ProVFOEntry] {
        guard data.count >= vfoSectionBytes else { return [] }
        return (0..<3).map { index in
            let start = index * 32
            let chunk = Data(data[start..<(start + 32)])
            let frequency = decodeVFOFrequency(chunk[0..<8]).map(formatMHz) ?? ""
            let offset = decodeOffsetFrequency(chunk[20..<27]).map(formatMHz) ?? ""
            let direction = vfoOffsetDirectionLabel(Int((chunk[14] >> 4) & 0x03))
            let mode = (chunk[17] & 0x01) != 0 ? "AM" : ((((chunk[17] >> 6) & 0x01) != 0) ? "NFM" : "FM")
            let power = powerLabel(from: Int(chunk[16] & 0x0F))
            let busyLockout = (chunk[13] & 0x01) != 0
            return RT950ProVFOEntry(
                index: index + 1,
                frequency: frequency,
                offset: offset,
                direction: direction,
                mode: mode,
                power: power,
                busyLockout: busyLockout
            )
        }
    }

    private static func parseFunctionSettings(from data: Data) -> [RT950ProNamedValue] {
        guard data.count == functionSectionBytes else { return [] }
        return parseFunctionSettingValues(from: data)
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { RT950ProNamedValue(key: $0.key, value: $0.value) }
    }

    private static func parseDTMF(from data: Data) -> RT950ProDTMFSummary {
        guard data.count == dtmfSectionBytes else {
            return RT950ProDTMFSummary(currentID: "", pttMode: "Unknown", codeGroups: [])
        }

        let info = Data(data[0..<32])
        let groups = Data(data[32..<384])
        let currentID = decodeDTMFSequence(info[0..<5], maxLength: 5)
        let pttMode = info[6] == 0xFF ? "Unset" : String(info[6] & 0x0F)
        var codeGroups: [String] = []
        for offset in stride(from: 0, to: groups.count, by: 16) {
            let sequence = decodeDTMFSequence(groups[offset..<(offset + 16)], maxLength: 6)
            if !sequence.isEmpty {
                codeGroups.append(sequence)
            }
        }

        return RT950ProDTMFSummary(currentID: currentID, pttMode: pttMode, codeGroups: codeGroups)
    }

    private static func parseAPRS(from data: Data) -> [RT950ProNamedValue] {
        guard data.count == aprsSectionBytes else { return [] }
        var fields: [RT950ProNamedValue] = []

        func appendValue(_ key: String, _ value: String) {
            if !value.isEmpty {
                fields.append(RT950ProNamedValue(key: key, value: value))
            }
        }

        appendValue("aprs_switch", boolLabel(data[0]))
        appendValue("gps_switch", boolLabel(data[1]))
        appendValue("time_zone", data[6] == 0xFF ? "" : String(data[6] & 0x1F))
        appendValue("call_sign", decodeASCII(data, offset: 17, maxLength: 6))
        appendValue("ssid", data[23] == 0xFF ? "" : String(data[23] & 0x0F))
        appendValue("routing_select", data[24] == 0xFF ? "" : String(data[24] & 0x0F))
        appendValue("my_position", data[25] == 0xFF ? "" : String(data[25] & 0x0F))
        appendValue("radio_symbol", data[26] == 0xFF ? "" : String(data[26] & 0x0F))
        appendValue("aprs_priority", data[29] == 0xFF ? "" : String(data[29] & 0x0F))
        appendValue("beacon_tx_type", data[34] == 0xFF ? "" : String(data[34] & 0x0F))
        appendValue("custom_routing_one", decodeASCII(data, offset: 43, maxLength: 6))
        appendValue("custom_routing_two", decodeASCII(data, offset: 50, maxLength: 6))
        appendValue("custom_messages", decodeGB2312(Data(data[79..<119]), maxBytes: 40))
        return fields
    }

    private static func parseLocation(_ value: String) throws -> Int {
        guard let location = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), (1...channelCount).contains(location) else {
            throw RT950ProCloneCodecError.invalidLocation(value)
        }
        return location
    }

    private static func deriveTXFrequency(from channel: ChannelMemory, rxHz: Int, txEnabled: Bool) throws -> Int? {
        guard txEnabled else { return nil }

        let duplex = channel.duplex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let offsetSource = channel.offset.trimmingCharacters(in: .whitespacesAndNewlines)
        switch duplex {
        case "", "simplex":
            return rxHz
        case "+":
            let offset = try parseFrequency(offsetSource)
            return rxHz + offset
        case "-":
            let offset = try parseFrequency(offsetSource)
            return rxHz - offset
        case "split":
            return try parseFrequency(offsetSource)
        case "off":
            return nil
        default:
            return rxHz
        }
    }

    private static func parseFrequency(_ value: String) throws -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RT950ProCloneCodecError.invalidFrequency(value)
        }

        let lowered = trimmed.lowercased()
        let multiplier: Double
        let numericText: String
        if lowered.hasSuffix("mhz") {
            multiplier = 1_000_000
            numericText = String(lowered.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lowered.hasSuffix("khz") {
            multiplier = 1_000
            numericText = String(lowered.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lowered.hasSuffix("hz") {
            multiplier = 1
            numericText = String(lowered.dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            multiplier = trimmed.contains(".") ? 1_000_000 : 1
            numericText = trimmed
        }

        guard let numericValue = Double(numericText) else {
            throw RT950ProCloneCodecError.invalidFrequency(value)
        }

        if multiplier == 1, numericValue < 1_000_000, trimmed.contains(".") {
            return Int((numericValue * 1_000_000).rounded())
        }
        return Int((numericValue * multiplier).rounded())
    }

    private static func parseDCSCode(_ value: String) throws -> Int {
        let digits = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(digits), parsed > 0 else {
            throw RT950ProCloneCodecError.invalidDCSCode(value)
        }
        return parsed
    }

    private static func normalizedDTCSPolarity(_ value: String) -> String {
        let upper = value.uppercased().filter { $0 == "N" || $0 == "R" }
        if upper.count >= 2 {
            return String(upper.prefix(2))
        }
        if upper.count == 1 {
            return upper + upper
        }
        return "NN"
    }

    private static func toneFromCTCSS(_ value: String) throws -> NativeToneSetting {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hz = Double(trimmed) else {
            throw RT950ProCloneCodecError.invalidToneValue(value)
        }
        return .ctcss(hz: hz)
    }

    private static func formatMHz(_ hz: Int) -> String {
        String(format: "%.6f", Double(hz) / 1_000_000.0)
    }

    private static func formatTone(_ hz: Double) -> String {
        String(format: "%.1f", hz)
    }

    private static func powerLabel(from rawValue: Int) -> String {
        switch rawValue {
        case 0:
            return "High"
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

    private static func vfoOffsetDirectionLabel(_ value: Int) -> String {
        switch value {
        case 1:
            return "+"
        case 2:
            return "-"
        case 3:
            return "split"
        default:
            return "simplex"
        }
    }

    private static func formatFunctionValue(key: String, value: Int?) -> String {
        guard let value else { return "Unset" }
        if functionBooleanKeys.contains(key) {
            return value == 0 ? "Off" : "On"
        }
        return String(value)
    }

    private static func parseFunctionSettingValues(from data: Data) -> [String: String] {
        guard data.count == functionSectionBytes else { return [:] }
        var values: [String: String] = [:]

        for descriptor in editableFunctionSettingDescriptors {
            let byte = data[descriptor.byteOffset]
            let rawValue: Int?
            if byte == 0xFF {
                rawValue = nil
            } else {
                rawValue = Int((byte >> descriptor.shift) & descriptor.mask)
            }
            values[descriptor.key] = formatFunctionValue(key: descriptor.key, value: rawValue)
        }

        return values
    }

    private static func rawFunctionValue(from value: String, descriptor: RT950ProFunctionSettingDescriptor) throws -> Int {
        switch descriptor.kind {
        case .toggle:
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "on", "1", "true", "yes":
                return 1
            case "off", "0", "false", "no":
                return 0
            default:
                throw RT950ProCloneCodecError.invalidFunctionSettingValue(key: descriptor.key, value: value)
            }
        case let .numeric(min, max):
            guard let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), (min...max).contains(parsed) else {
                throw RT950ProCloneCodecError.invalidFunctionSettingValue(key: descriptor.key, value: value)
            }
            return parsed
        }
    }

    private static func boolLabel(_ byte: UInt8) -> String {
        if byte == 0xFF {
            return ""
        }
        return byte == 0 ? "Off" : "On"
    }

    private static func parseBoolLabel(_ byte: UInt8) -> Bool {
        byte != 0xFF && byte != 0
    }

    private static func parseMaskedValue(_ byte: UInt8, mask: UInt8 = 0x0F) -> String {
        if byte == 0xFF {
            return ""
        }
        return String(byte & mask)
    }

    private static func encodeMaskedValue(_ value: String, mask: UInt8) -> UInt8 {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let intValue = Int(trimmed) else {
            return 0xFF
        }
        return UInt8(intValue) & mask
    }

    private static func clampedInt(_ string: String, range: ClosedRange<Int>) -> Int {
        guard let value = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return range.lowerBound
        }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    private static func decodeFrequency<S: DataProtocol>(_ data: S) throws -> Int? {
        let bytes = Array(data)
        guard bytes.count == 4 else { return nil }
        if bytes.allSatisfy({ $0 == 0x00 || $0 == 0xFF }) {
            return nil
        }

        var digits: [Int] = []
        for byte in bytes {
            let high = Int((byte >> 4) & 0x0F)
            let low = Int(byte & 0x0F)
            guard high <= 9, low <= 9 else {
                throw RT950ProCloneCodecError.invalidFrequency(bytes.map { String(format: "%02X", $0) }.joined())
            }
            digits.append(high * 10 + low)
        }

        var value = 0
        for chunk in digits.reversed() {
            value = value * 100 + chunk
        }
        return value * 10
    }

    private static func encodeFrequency(_ hz: Int?) -> Data {
        guard let hz, hz > 0 else {
            return Data(repeating: 0xFF, count: 4)
        }

        let value = hz / 10
        var remainder = value
        var bytes: [UInt8] = []
        for _ in 0..<4 {
            let chunk = remainder % 100
            remainder /= 100
            bytes.append(UInt8(((chunk / 10) << 4) | (chunk % 10)))
        }
        return Data(bytes)
    }

    private static func decodeVFOFrequency<S: DataProtocol>(_ data: S) -> Int? {
        let bytes = Array(data)
        guard !bytes.isEmpty else { return nil }
        if bytes.allSatisfy({ $0 == 0x00 || $0 == 0xFF }) {
            return nil
        }
        let value = Int(bytes.map(String.init).joined()) ?? 0
        return Int((Double(value) / 100000.0 * 1_000_000.0).rounded())
    }

    private static func decodeOffsetFrequency<S: DataProtocol>(_ data: S) -> Int? {
        let bytes = Array(data)
        guard !bytes.isEmpty else { return nil }
        if bytes.allSatisfy({ $0 == 0x00 || $0 == 0xFF }) {
            return nil
        }
        let value = Int(bytes.map(String.init).joined()) ?? 0
        return Int((Double(value) / 10000.0 * 1_000_000.0).rounded())
    }

    private static func decodeFHSSCode<S: DataProtocol>(_ data: S) -> String? {
        let bytes = Array(data)
        guard bytes.count == 4, bytes[3] == 0xA0 else { return nil }
        let digits = Array("0123456789ABCDEF")
        let pairs = Array(bytes[0..<3].reversed()).flatMap { byte -> [Character] in
            [
                digits[Int((byte >> 4) & 0x0F)],
                digits[Int(byte & 0x0F)],
            ]
        }
        return String(pairs)
    }

    private static func encodeFHSSCode(_ code: String) -> Data {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count == 6, trimmed.allSatisfy({ "0123456789ABCDEF".contains($0) }) else {
            return Data(repeating: 0xFF, count: 4)
        }

        let digits = Array(trimmed)
        func nibble(_ character: Character) -> UInt8 {
            UInt8(Int(String(character), radix: 16) ?? 0)
        }

        return Data([
            (nibble(digits[4]) << 4) | nibble(digits[5]),
            (nibble(digits[2]) << 4) | nibble(digits[3]),
            (nibble(digits[0]) << 4) | nibble(digits[1]),
            0xA0,
        ])
    }

    private static func decodeTone<S: DataProtocol>(_ data: S) throws -> NativeToneSetting {
        let bytes = Array(data)
        guard bytes.count == 2 else { return .off }
        let first = bytes[0]
        let second = bytes[1]

        if first == 0 && second == 0 {
            return .off
        }
        if second == 0 {
            let index = Int(first)
            if index >= 1, index <= dcsCodes.count {
                let token = dcsCodes[index - 1]
                let code = Int(token.dropFirst().prefix(3)) ?? 0
                let polarity = String(token.suffix(1))
                return .dcs(code: code, polarity: polarity)
            }
            return .off
        }

        let value = Int(second) << 8 | Int(first)
        if value == 0xFFFF {
            return .off
        }
        return .ctcss(hz: Double(value) / 10.0)
    }

    private static func encodeTone(_ tone: NativeToneSetting) -> Data {
        switch tone {
        case .off:
            return Data([0x00, 0x00])
        case let .ctcss(hz):
            let value = Int((hz * 10).rounded())
            return Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
        case let .dcs(code, polarity):
            let token = String(format: "D%03d%@", code, polarity.uppercased())
            guard let index = dcsCodes.firstIndex(of: token) else {
                return Data([0x00, 0x00])
            }
            return Data([UInt8(index + 1), 0x00])
        }
    }

    private static func decodeDTMFSequence<S: DataProtocol>(_ data: S, maxLength: Int) -> String {
        let digits = dtmfAlphabet
        var characters: [Character] = []
        for byte in Array(data).prefix(maxLength) {
            if byte == 0xFF {
                break
            }
            let index = Int(byte)
            if digits.indices.contains(index) {
                characters.append(digits[index])
            }
        }
        return String(characters)
    }

    private static func encodeDTMFSequence(_ string: String, maxBytes: Int, visibleLength: Int? = nil) throws -> Data {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            return Data(repeating: 0xFF, count: maxBytes)
        }

        let capped = String(trimmed.prefix(visibleLength ?? maxBytes))
        var bytes = Data()
        for character in capped {
            guard let index = dtmfAlphabet.firstIndex(of: character) else {
                throw RT950ProCloneCodecError.invalidDTMFCharacter(character)
            }
            bytes.append(UInt8(index))
            if bytes.count == maxBytes {
                break
            }
        }

        if bytes.count < maxBytes {
            bytes.append(Data(repeating: 0xFF, count: maxBytes - bytes.count))
        }
        return bytes.prefix(maxBytes)
    }

    private static func decodeGB2312(_ data: Data, maxBytes: Int) -> String {
        let bytes = Array(data.prefix(maxBytes))
        var decoded = Data()
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0xFF || byte == 0x00 {
                break
            }
            if byte >= 0xA1, index + 1 < bytes.count {
                decoded.append(byte)
                decoded.append(bytes[index + 1])
                index += 2
            } else {
                decoded.append(byte)
                index += 1
            }
        }
        guard !decoded.isEmpty else { return "" }
        return String(data: decoded, encoding: .gb18030) ?? String(decoding: decoded, as: UTF8.self)
    }

    private static func encodeGB2312(_ string: String, maxBytes: Int) -> Data {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Data(repeating: 0xFF, count: maxBytes)
        }

        let encoding = String.Encoding.gb18030
        var encoded = Data()
        for character in trimmed {
            let scalar = String(character)
            guard let charData = scalar.data(using: encoding) ?? scalar.data(using: .ascii) else {
                continue
            }
            if encoded.count + charData.count > maxBytes {
                break
            }
            encoded.append(charData)
        }
        if encoded.count < maxBytes {
            encoded.append(Data(repeating: 0xFF, count: maxBytes - encoded.count))
        }
        return encoded.prefix(maxBytes)
    }

    private static func encodeASCII(_ string: String, maxBytes: Int) -> Data {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Data(repeating: 0xFF, count: maxBytes)
        }

        let filtered = trimmed
            .uppercased()
            .unicodeScalars
            .filter { $0.isASCII }
            .prefix(maxBytes)
        var data = Data(filtered.map { UInt8($0.value) })
        if data.count < maxBytes {
            data.append(Data(repeating: 0xFF, count: maxBytes - data.count))
        }
        return data
    }

    private static func decodeASCII(_ data: Data, offset: Int, maxLength: Int) -> String {
        guard data.count >= offset else { return "" }
        let end = min(data.count, offset + maxLength)
        var bytes: [UInt8] = []
        for byte in data[offset..<end] {
            if byte == 0xFF || byte == 0x00 {
                break
            }
            bytes.append(byte)
        }
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    private static let functionBooleanKeys: Set<String> = [
        "tdr",
        "beep_prompt",
        "auto_key_lock",
        "tail_noise_clear",
        "pass_repeater_noise_clear",
        "pass_repeater_noise_detect",
        "sound_tx_end",
        "fm_radio",
        "bt_write_switch",
        "divide_channel",
        "subaudio_scan_save",
        "vox_switch",
        "ab_uv_transfer",
        "sound_transfer",
    ]

    private static let dtmfAlphabet = Array("0123456789ABCD*#")

    private static let dcsCodes: [String] = [
        "D023N", "D025N", "D026N", "D031N", "D032N", "D036N", "D043N", "D047N", "D051N", "D053N",
        "D054N", "D065N", "D071N", "D072N", "D073N", "D074N", "D114N", "D115N", "D116N", "D122N",
        "D125N", "D131N", "D132N", "D134N", "D143N", "D145N", "D152N", "D155N", "D156N", "D162N",
        "D165N", "D172N", "D174N", "D205N", "D212N", "D223N", "D225N", "D226N", "D243N", "D244N",
        "D245N", "D246N", "D251N", "D252N", "D255N", "D261N", "D263N", "D265N", "D266N", "D271N",
        "D274N", "D306N", "D311N", "D315N", "D325N", "D331N", "D332N", "D343N", "D346N", "D351N",
        "D356N", "D364N", "D365N", "D371N", "D411N", "D412N", "D413N", "D423N", "D431N", "D432N",
        "D445N", "D446N", "D452N", "D454N", "D455N", "D462N", "D464N", "D465N", "D466N", "D503N",
        "D506N", "D516N", "D523N", "D526N", "D532N", "D546N", "D565N", "D606N", "D612N", "D624N",
        "D627N", "D631N", "D632N", "D645N", "D654N", "D662N", "D664N", "D703N", "D712N", "D723N",
        "D731N", "D732N", "D734N", "D743N", "D754N", "D023I", "D025I", "D026I", "D031I", "D032I",
        "D036I", "D043I", "D047I", "D051I", "D053I", "D054I", "D065I", "D071I", "D072I", "D073I",
        "D074I", "D114I", "D115I", "D116I", "D122I", "D125I", "D131I", "D132I", "D134I", "D143I",
        "D145I", "D152I", "D155I", "D156I", "D162I", "D165I", "D172I", "D174I", "D205I", "D212I",
        "D223I", "D225I", "D226I", "D243I", "D244I", "D245I", "D246I", "D251I", "D252I", "D255I",
        "D261I", "D263I", "D265I", "D266I", "D271I", "D274I", "D306I", "D311I", "D315I", "D325I",
        "D331I", "D332I", "D343I", "D346I", "D351I", "D356I", "D364I", "D365I", "D371I", "D411I",
        "D412I", "D413I", "D423I", "D431I", "D432I", "D445I", "D446I", "D452I", "D454I", "D455I",
        "D462I", "D464I", "D465I", "D466I", "D503I", "D506I", "D516I", "D523I", "D526I", "D532I",
        "D546I", "D565I", "D606I", "D612I", "D624I", "D627I", "D631I", "D632I", "D645I", "D654I",
        "D662I", "D664I", "D703I", "D712I", "D723I", "D731I", "D732I", "D734I", "D743I", "D754I",
    ]
}

private enum NativeToneSetting: Hashable {
    case off
    case ctcss(hz: Double)
    case dcs(code: Int, polarity: String)
}

private extension String.Encoding {
    static let gb18030: String.Encoding = {
        let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String.Encoding(rawValue: encoding)
    }()
}

private extension String {
    func leftPadding(toLength: Int, withPad character: Character) -> String {
        if count >= toLength {
            return self
        }
        return String(repeating: String(character), count: toLength - count) + self
    }
}
