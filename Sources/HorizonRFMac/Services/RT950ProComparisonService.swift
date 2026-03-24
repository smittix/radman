import Foundation

struct RT950ProComparisonItem: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let beforeValue: String
    let afterValue: String
}

struct RT950ProComparisonSection: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case channels = "Channels"
        case aprs = "APRS"
        case coreSettings = "Core Settings"
        case dtmf = "DTMF"
    }

    let kind: Kind
    let summary: String
    let items: [RT950ProComparisonItem]

    var id: Kind { kind }
    var changeCount: Int { items.count }
}

struct RT950ProComparisonReport: Hashable {
    let beforeLabel: String
    let afterLabel: String
    let sections: [RT950ProComparisonSection]

    var totalChangeCount: Int {
        sections.reduce(0) { $0 + $1.changeCount }
    }

    var hasChanges: Bool {
        totalChangeCount > 0
    }
}

enum RT950ProComparisonService {
    static func compareLiveRadio(liveCloneData: Data, againstChannels channels: [ChannelMemory], liveLabel: String = "Live Radio", targetLabel: String = "RadMan Frequencies") throws -> RT950ProComparisonReport {
        let liveChannels = try RT950ProCloneCodec.channels(from: liveCloneData)
        let sections = [compareChannels(before: liveChannels, after: channels)]
            .compactMap { $0 }
        return RT950ProComparisonReport(beforeLabel: liveLabel, afterLabel: targetLabel, sections: sections)
    }

    static func compareCloneData(_ beforeData: Data, beforeLabel: String, against afterData: Data, afterLabel: String) throws -> RT950ProComparisonReport {
        let beforeChannels = try RT950ProCloneCodec.channels(from: beforeData)
        let afterChannels = try RT950ProCloneCodec.channels(from: afterData)
        let beforeAPRS = try RT950ProCloneCodec.aprsEntry(from: beforeData)
        let afterAPRS = try RT950ProCloneCodec.aprsEntry(from: afterData)
        let beforeFunctionSettings = try RT950ProCloneCodec.functionSettingsEntry(from: beforeData)
        let afterFunctionSettings = try RT950ProCloneCodec.functionSettingsEntry(from: afterData)
        let beforeDTMF = try RT950ProCloneCodec.dtmfEntry(from: beforeData)
        let afterDTMF = try RT950ProCloneCodec.dtmfEntry(from: afterData)

        let sections = [
            compareChannels(before: beforeChannels, after: afterChannels),
            compareAPRS(before: beforeAPRS, after: afterAPRS),
            compareFunctionSettings(before: beforeFunctionSettings, after: afterFunctionSettings),
            compareDTMF(before: beforeDTMF, after: afterDTMF),
        ]
        .compactMap { $0 }

        return RT950ProComparisonReport(beforeLabel: beforeLabel, afterLabel: afterLabel, sections: sections)
    }

    private static func compareChannels(before: [ChannelMemory], after: [ChannelMemory]) -> RT950ProComparisonSection? {
        let beforeMap = Dictionary(uniqueKeysWithValues: before.compactMap { channel -> (Int, ChannelMemory)? in
            guard let location = ChannelPlanService.locationValue(for: channel) else { return nil }
            return (location, channel)
        })
        let afterMap = Dictionary(uniqueKeysWithValues: after.compactMap { channel -> (Int, ChannelMemory)? in
            guard let location = ChannelPlanService.locationValue(for: channel) else { return nil }
            return (location, channel)
        })

        let allLocations = Set(beforeMap.keys).union(afterMap.keys).sorted()
        let items = allLocations.compactMap { location -> RT950ProComparisonItem? in
            let beforeChannel = beforeMap[location]
            let afterChannel = afterMap[location]
            guard channelFingerprint(beforeChannel) != channelFingerprint(afterChannel) else {
                return nil
            }

            return RT950ProComparisonItem(
                label: "Memory \(location)",
                beforeValue: channelSummary(beforeChannel),
                afterValue: channelSummary(afterChannel)
            )
        }

        guard !items.isEmpty else { return nil }
        return RT950ProComparisonSection(
            kind: .channels,
            summary: "\(items.count) channel change\(items.count == 1 ? "" : "s") detected.",
            items: items
        )
    }

    private static func compareAPRS(before: RT950ProAPRSEntry, after: RT950ProAPRSEntry) -> RT950ProComparisonSection? {
        let rows = [
            ("APRS Enabled", before.aprsEnabled ? "On" : "Off", after.aprsEnabled ? "On" : "Off"),
            ("GPS Enabled", before.gpsEnabled ? "On" : "Off", after.gpsEnabled ? "On" : "Off"),
            ("Time Zone", before.timeZone.ifEmpty("Unset"), after.timeZone.ifEmpty("Unset")),
            ("Call Sign", before.callSign.ifEmpty("Unset"), after.callSign.ifEmpty("Unset")),
            ("SSID", before.ssid.ifEmpty("Unset"), after.ssid.ifEmpty("Unset")),
            ("Routing Select", before.routingSelect.ifEmpty("Unset"), after.routingSelect.ifEmpty("Unset")),
            ("My Position", before.myPosition.ifEmpty("Unset"), after.myPosition.ifEmpty("Unset")),
            ("Radio Symbol", before.radioSymbol.ifEmpty("Unset"), after.radioSymbol.ifEmpty("Unset")),
            ("APRS Priority", before.aprsPriority.ifEmpty("Unset"), after.aprsPriority.ifEmpty("Unset")),
            ("Beacon TX Type", before.beaconTxType.ifEmpty("Unset"), after.beaconTxType.ifEmpty("Unset")),
            ("Custom Route 1", before.customRoutingOne.ifEmpty("Unset"), after.customRoutingOne.ifEmpty("Unset")),
            ("Custom Route 2", before.customRoutingTwo.ifEmpty("Unset"), after.customRoutingTwo.ifEmpty("Unset")),
            ("Send Custom Message", before.sendCustomMessages ? "On" : "Off", after.sendCustomMessages ? "On" : "Off"),
            ("Custom Message", before.customMessages.ifEmpty("Unset"), after.customMessages.ifEmpty("Unset")),
        ]

        let items = rows.compactMap { label, oldValue, newValue in
            oldValue == newValue ? nil : RT950ProComparisonItem(label: label, beforeValue: oldValue, afterValue: newValue)
        }

        guard !items.isEmpty else { return nil }
        return RT950ProComparisonSection(kind: .aprs, summary: "\(items.count) APRS field change\(items.count == 1 ? "" : "s") detected.", items: items)
    }

    private static func compareFunctionSettings(before: RT950ProFunctionSettingsEntry, after: RT950ProFunctionSettingsEntry) -> RT950ProComparisonSection? {
        let keys = Set(before.values.keys).union(after.values.keys).sorted()
        let items = keys.compactMap { key -> RT950ProComparisonItem? in
            let oldValue = before[key].ifEmpty("Unset")
            let newValue = after[key].ifEmpty("Unset")
            guard oldValue != newValue else { return nil }
            return RT950ProComparisonItem(
                label: friendlyLabel(for: key),
                beforeValue: oldValue,
                afterValue: newValue
            )
        }

        guard !items.isEmpty else { return nil }
        return RT950ProComparisonSection(kind: .coreSettings, summary: "\(items.count) core setting change\(items.count == 1 ? "" : "s") detected.", items: items)
    }

    private static func compareDTMF(before: RT950ProDTMFEntry, after: RT950ProDTMFEntry) -> RT950ProComparisonSection? {
        var items: [RT950ProComparisonItem] = []

        if before.currentID != after.currentID {
            items.append(RT950ProComparisonItem(label: "Current ID", beforeValue: before.currentID.ifEmpty("Unset"), afterValue: after.currentID.ifEmpty("Unset")))
        }

        if before.pttMode != after.pttMode {
            items.append(RT950ProComparisonItem(label: "PTT Mode", beforeValue: before.pttMode.ifEmpty("Unset"), afterValue: after.pttMode.ifEmpty("Unset")))
        }

        let count = max(before.codeGroups.count, after.codeGroups.count)
        for index in 0..<count {
            let oldValue = index < before.codeGroups.count ? before.codeGroups[index].ifEmpty("Unset") : "Unset"
            let newValue = index < after.codeGroups.count ? after.codeGroups[index].ifEmpty("Unset") : "Unset"
            if oldValue != newValue {
                items.append(RT950ProComparisonItem(label: "Group \(index + 1)", beforeValue: oldValue, afterValue: newValue))
            }
        }

        guard !items.isEmpty else { return nil }
        return RT950ProComparisonSection(kind: .dtmf, summary: "\(items.count) DTMF change\(items.count == 1 ? "" : "s") detected.", items: items)
    }

    private static func channelFingerprint(_ channel: ChannelMemory?) -> String {
        guard let channel else { return "" }
        return [
            channel.location,
            channel.name,
            channel.frequency,
            channel.duplex,
            channel.offset,
            channel.tone,
            channel.rToneFreq,
            channel.cToneFreq,
            channel.dtcsCode,
            channel.dtcsPolarity,
            channel.rxDtcsCode,
            channel.crossMode,
            channel.mode,
            channel.tStep,
            channel.skip,
            channel.power,
            channel.comment,
            channel.urcall,
            channel.rpt1call,
            channel.rpt2call,
            channel.dvcode,
            channel.nativeSignalGroup,
            channel.nativePTTID,
            channel.nativeBusyLockout ? "1" : "0",
            channel.nativeScrambler,
            channel.nativeEncryption,
            channel.nativeLearnFHSS ? "1" : "0",
            channel.nativeFHSSCode,
        ]
        .joined(separator: "|")
    }

    private static func channelSummary(_ channel: ChannelMemory?) -> String {
        guard let channel else { return "Empty" }

        var tokens: [String] = []
        let name = channel.displayName
        let frequency = channel.frequency.isEmpty ? "No RX" : "\(channel.frequency) MHz"
        tokens.append(name == "Untitled" ? frequency : "\(name) • \(frequency)")

        if !channel.txSummary.isEmpty {
            tokens.append("TX \(channel.txSummary)")
        }
        if !channel.modeDisplay.isEmpty {
            tokens.append(channel.modeDisplay)
        }
        if !channel.toneSummary.isEmpty {
            tokens.append(channel.toneSummary)
        }
        if !channel.power.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tokens.append(channel.power)
        }

        return tokens.joined(separator: " • ")
    }

    private static func friendlyLabel(for key: String) -> String {
        let explicit: [String: String] = [
            "sql": "Squelch",
            "save_mode": "Battery Save",
            "vox": "VOX Level",
            "auto_backlight": "Auto Backlight",
            "tdr": "Dual Watch",
            "tot": "Time-Out Timer",
            "beep_prompt": "Beep Prompt",
            "voice_prompt": "Voice Prompt",
            "scan_mode": "Scan Mode",
            "display_mode_a": "Display Mode A",
            "display_mode_b": "Display Mode B",
            "display_mode_c": "Display Mode C",
            "auto_key_lock": "Auto Key Lock",
            "fm_radio": "FM Radio",
            "vox_delay": "VOX Delay",
            "timer_menu_quit": "Menu Timeout",
            "weather_channel": "Weather Channel",
            "divide_channel": "Split Channel Mode",
            "lock_keyboard": "Keypad Lock",
            "power_on_message": "Power-On Message",
            "bt_write_switch": "Bluetooth Write",
            "call_sign": "Call Sign",
            "aprs_switch": "APRS",
            "gps_switch": "GPS",
            "time_zone": "Time Zone",
            "radio_symbol": "Radio Symbol",
            "routing_select": "Routing Preset",
            "my_position": "My Position",
            "custom_routing_one": "Custom Route 1",
            "custom_routing_two": "Custom Route 2",
            "custom_messages": "Custom Message",
            "aprs_priority": "APRS Priority",
            "beacon_tx_type": "Beacon Mode",
        ]
        if let label = explicit[key] {
            return label
        }
        return key
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
