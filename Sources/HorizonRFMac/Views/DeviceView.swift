import SwiftUI

struct DeviceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editingFunctionSettings: RT950ProFunctionSettingsEntry?
    @State private var editingAPRS: RT950ProAPRSEntry?
    @State private var editingDTMF: RT950ProDTMFEntry?
    @State private var deviceStatusMessage: String?
    @State private var deviceErrorMessage: String?
    @State private var isRefreshingSnapshot = false
    @State private var isApplyingFunctionUpdate = false
    @State private var isApplyingAPRSUpdate = false
    @State private var isApplyingDTMFUpdate = false

    private var profile: RadioProfile? {
        store.preferredRT950ProProfile
    }

    private var cloneSummary: RT950ProCloneSummary? {
        guard let base64 = profile?.lastNativeCloneBase64, let data = Data(base64Encoded: base64) else {
            return nil
        }
        return try? RT950ProCloneCodec.summary(from: data)
    }

    private var aprsEntry: RT950ProAPRSEntry? {
        guard let base64 = profile?.lastNativeCloneBase64, let data = Data(base64Encoded: base64) else {
            return nil
        }
        return try? RT950ProCloneCodec.aprsEntry(from: data)
    }

    private var functionSettingsEntry: RT950ProFunctionSettingsEntry? {
        guard let base64 = profile?.lastNativeCloneBase64, let data = Data(base64Encoded: base64) else {
            return nil
        }
        return try? RT950ProCloneCodec.functionSettingsEntry(from: data)
    }

    private var dtmfEntry: RT950ProDTMFEntry? {
        guard let base64 = profile?.lastNativeCloneBase64, let data = Data(base64Encoded: base64) else {
            return nil
        }
        return try? RT950ProCloneCodec.dtmfEntry(from: data)
    }

    private var isBusy: Bool {
        isRefreshingSnapshot || isApplyingFunctionUpdate || isApplyingAPRSUpdate || isApplyingDTMFUpdate
    }

    private var canUseLiveWorkflow: Bool {
        guard let profile else { return false }
        return !profile.serialPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let deviceStatusMessage {
                    RadManStatusBanner(text: deviceStatusMessage, tone: .success)
                }

                if let profile, let summary = cloneSummary {
                    RadManHeroCard(
                        title: "Device Snapshot",
                        subtitle: "Refresh the radio, inspect the latest decoded clone, and review the RT-950 Pro's working state before programming channels, zones, DTMF, APRS, or core settings.",
                        accent: RadManPalette.teal
                    ) {
                        HStack(spacing: 14) {
                            RadManMetricCard(
                                title: "Profile",
                                value: profile.name.isEmpty ? profile.resolvedModelName : profile.name,
                                subtitle: profile.serialPort.isEmpty ? "No serial port saved" : profile.serialPort,
                                accent: RadManPalette.teal
                            )
                            RadManMetricCard(
                                title: "Channels",
                                value: "\(summary.channelCount)",
                                subtitle: profile.lastNativeCloneCapturedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Capture time unknown",
                                accent: RadManPalette.amber
                            )
                            RadManMetricCard(
                                title: "Model",
                                value: profile.lastNativeModelIdentifier.isEmpty ? profile.resolvedModelName : profile.lastNativeModelIdentifier,
                                subtitle: profile.lastNativeCloneSHA256.isEmpty ? "No clone hash" : String(profile.lastNativeCloneSHA256.prefix(12)) + "…",
                                accent: RadManPalette.coral
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 12) {
                            Button {
                                refreshSnapshotFromRadio()
                            } label: {
                                Label(isRefreshingSnapshot ? "Reading Radio..." : "Refresh From Radio", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(RadManPrimaryButtonStyle())
                            .disabled(!canUseLiveWorkflow || isBusy)

                            Text("Use this screen to read the radio, confirm what is currently programmed, and review the settings RadMan can safely edit today.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.82))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !canUseLiveWorkflow {
                        RadManStatusBanner(
                            text: "Assign the RT-950 Pro programming cable on the Radios or Tools screen to enable live refresh and safe programming from here.",
                            tone: .warning
                        )
                    }

                    RadManPanel(title: "VFO Memories", subtitle: "Current working frequencies and front-panel state from the radio.") {
                        if summary.vfos.isEmpty {
                            Text("No VFO summary decoded yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            RadManStatusBanner(
                                text: "VFO values are currently read-only in RadMan so the app can avoid unstable front-panel writes.",
                                tone: .info
                            )

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                                ForEach(summary.vfos) { entry in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text("VFO \(entry.index)")
                                                .font(.headline)
                                            Spacer()
                                            RadManBadge(text: entry.mode, accent: RadManPalette.teal)
                                        }
                                        Text(entry.frequency.isEmpty ? "No frequency" : entry.frequency + " MHz")
                                            .font(.system(size: 22, weight: .bold, design: .rounded))
                                        HStack(spacing: 8) {
                                            if !entry.offset.isEmpty {
                                                RadManBadge(text: "\(entry.direction) \(entry.offset)", accent: RadManPalette.amber)
                                            }
                                            RadManBadge(text: entry.power, accent: RadManPalette.coral)
                                            if entry.busyLockout {
                                                RadManBadge(text: "Busy Lockout", accent: .red)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                                    .background(Color.white.opacity(0.74))
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                            }
                        }
                    }

                    RadManPanel(title: "Core Radio Settings", subtitle: "Important operating settings decoded from the latest clone.") {
                        if importantFunctionSettings.isEmpty {
                            Text("No function settings decoded yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Text("Edit the core operating settings RadMan already understands.")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    if let functionSettingsEntry {
                                        editingFunctionSettings = functionSettingsEntry
                                    }
                                } label: {
                                    Label("Edit Core Settings", systemImage: "slider.horizontal.3")
                                }
                                .buttonStyle(RadManSecondaryButtonStyle())
                                .disabled(!canUseLiveWorkflow || isBusy || functionSettingsEntry == nil)
                            }

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                                ForEach(importantFunctionSettings) { item in
                                    DeviceFieldCard(item: item)
                                }
                            }

                            if !advancedFunctionSettings.isEmpty {
                                DisclosureGroup("More decoded settings") {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                                        ForEach(advancedFunctionSettings) { item in
                                            DeviceFieldCard(item: item)
                                        }
                                    }
                                    .padding(.top, 12)
                                }
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 18) {
                        RadManPanel(title: "DTMF", subtitle: "Current identity and stored quick-code groups.") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Edit DTMF IDs and stored quick-code groups using the same safe full-clone workflow.")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        if let dtmfEntry {
                                            editingDTMF = dtmfEntry
                                        }
                                    } label: {
                                        Label("Edit DTMF", systemImage: "phone.connection")
                                    }
                                    .buttonStyle(RadManSecondaryButtonStyle())
                                    .disabled(!canUseLiveWorkflow || isBusy || dtmfEntry == nil)
                                }

                                DeviceFieldCard(item: DeviceDisplayField(label: "Current ID", value: summary.dtmf.currentID.isEmpty ? "Unset" : summary.dtmf.currentID))
                                DeviceFieldCard(item: DeviceDisplayField(label: "PTT Mode", value: summary.dtmf.pttMode))
                                let displayGroups = dtmfEntry?.populatedCodeGroups ?? summary.dtmf.codeGroups
                                if displayGroups.isEmpty {
                                    Text("No DTMF code groups decoded.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(Array(displayGroups.prefix(6)).indices, id: \.self) { index in
                                        DeviceFieldCard(item: DeviceDisplayField(label: "Group \(index + 1)", value: displayGroups[index]))
                                    }

                                    if displayGroups.count > 6 {
                                        DisclosureGroup("More DTMF groups") {
                                            VStack(alignment: .leading, spacing: 10) {
                                                ForEach(Array(displayGroups.dropFirst(6)).indices, id: \.self) { index in
                                                    DeviceFieldCard(item: DeviceDisplayField(label: "Group \(index + 7)", value: Array(displayGroups.dropFirst(6))[index]))
                                                }
                                            }
                                            .padding(.top, 12)
                                        }
                                    }
                                }
                            }
                        }

                        RadManPanel(title: "APRS", subtitle: "Tracking and beacon settings decoded from the dedicated APRS block.") {
                            if importantAPRSFields.isEmpty {
                                Text("No APRS summary decoded yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                HStack {
                                    Text("Edit the APRS identity and beacon fields RadMan already understands.")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        if let aprsEntry {
                                            editingAPRS = aprsEntry
                                        }
                                    } label: {
                                        Label("Edit APRS", systemImage: "dot.radiowaves.left.and.right")
                                    }
                                    .buttonStyle(RadManSecondaryButtonStyle())
                                    .disabled(!canUseLiveWorkflow || isBusy || aprsEntry == nil)
                                }

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                                    ForEach(importantAPRSFields) { item in
                                        DeviceFieldCard(item: item)
                                    }
                                }

                                if !advancedAPRSFields.isEmpty {
                                    DisclosureGroup("More APRS fields") {
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                                            ForEach(advancedAPRSFields) { item in
                                                DeviceFieldCard(item: item)
                                            }
                                        }
                                        .padding(.top, 12)
                                    }
                                    .padding(.top, 10)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Device Snapshot Yet",
                        systemImage: "memorychip",
                        description: Text("Read an RT-950 Pro clone from the radio or import a native clone image to see decoded VFOs and settings.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(24)
        }
        .sheet(item: $editingFunctionSettings) { entry in
            FunctionSettingsEditorSheet(entry: entry, isBusy: isApplyingFunctionUpdate) { updatedEntry in
                try applyFunctionSettingsUpdate(updatedEntry)
            }
        }
        .sheet(item: $editingAPRS) { entry in
            APRSEditorSheet(entry: entry, isBusy: isApplyingAPRSUpdate) { updatedEntry in
                try applyAPRSUpdate(updatedEntry)
            }
        }
        .sheet(item: $editingDTMF) { entry in
            DTMFEditorSheet(entry: entry, isBusy: isApplyingDTMFUpdate) { updatedEntry in
                try applyDTMFUpdate(updatedEntry)
            }
        }
        .alert("Device Action Failed", isPresented: Binding(
            get: { deviceErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    deviceErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deviceErrorMessage ?? "")
        }
    }

    private var functionFields: [DeviceDisplayField] {
        guard let summary = cloneSummary else { return [] }
        return summary.functionSettings.map {
            let value: String
            if $0.key.hasPrefix("current_work_area_") {
                value = store.workAreaDisplayName(for: $0.value)
            } else {
                value = $0.value
            }
            return DeviceDisplayField(label: Self.friendlyLabel(for: $0.key), value: value, group: Self.functionGroup(for: $0.key))
        }
    }

    private var importantFunctionSettings: [DeviceDisplayField] {
        functionFields.filter { $0.group != "Advanced" }
    }

    private var advancedFunctionSettings: [DeviceDisplayField] {
        functionFields.filter { $0.group == "Advanced" }
    }

    private var aprsFields: [DeviceDisplayField] {
        guard let summary = cloneSummary else { return [] }
        return summary.aprsFields.map {
            DeviceDisplayField(label: Self.friendlyLabel(for: $0.key), value: $0.value, group: Self.aprsGroup(for: $0.key))
        }
    }

    private var importantAPRSFields: [DeviceDisplayField] {
        aprsFields.filter { $0.group != "Advanced" }
    }

    private var advancedAPRSFields: [DeviceDisplayField] {
        aprsFields.filter { $0.group == "Advanced" }
    }

    private func refreshSnapshotFromRadio() {
        guard let profile else {
            deviceErrorMessage = RT950ProUSBServiceError.missingProfile.localizedDescription
            return
        }

        isRefreshingSnapshot = true
        defer { isRefreshingSnapshot = false }

        do {
            let report = try RT950ProUSBService.downloadClone(profile: profile)
            let importedCount = try store.applyRT950CloneReport(report, profile: profile)
            if let cloneData = Data(base64Encoded: report.rawCloneBase64) {
                let profileName = profile.name.isEmpty ? profile.resolvedModelName : profile.name
                let backupURL = try store.saveManagedBackup(cloneData: cloneData, profileName: profileName, label: "device-refresh")
                deviceStatusMessage = "Read \(importedCount) populated channels from the RT-950 Pro. Backup saved as \(backupURL.lastPathComponent)."
            } else {
                deviceStatusMessage = "Read \(importedCount) populated channels from the RT-950 Pro."
            }
            deviceErrorMessage = nil
        } catch {
            deviceErrorMessage = error.localizedDescription
        }
    }

    private func applyFunctionSettingsUpdate(_ entry: RT950ProFunctionSettingsEntry) throws {
        guard profile != nil else {
            throw RT950ProUSBServiceError.missingProfile
        }

        isApplyingFunctionUpdate = true
        defer { isApplyingFunctionUpdate = false }

        let backupURL = try store.programFunctionSettingsToRadio(entry, profile: profile)
        deviceStatusMessage = "Programmed core radio settings back to the RT-950 Pro. Backup saved as \(backupURL.lastPathComponent)."
        deviceErrorMessage = nil
    }

    private func applyAPRSUpdate(_ entry: RT950ProAPRSEntry) throws {
        guard profile != nil else {
            throw RT950ProUSBServiceError.missingProfile
        }

        isApplyingAPRSUpdate = true
        defer { isApplyingAPRSUpdate = false }

        let backupURL = try store.programAPRSToRadio(entry, profile: profile)
        deviceStatusMessage = "Programmed APRS settings back to the RT-950 Pro. Backup saved as \(backupURL.lastPathComponent)."
        deviceErrorMessage = nil
    }

    private func applyDTMFUpdate(_ entry: RT950ProDTMFEntry) throws {
        guard profile != nil else {
            throw RT950ProUSBServiceError.missingProfile
        }

        isApplyingDTMFUpdate = true
        defer { isApplyingDTMFUpdate = false }

        let backupURL = try store.programDTMFToRadio(entry, profile: profile)
        deviceStatusMessage = "Programmed DTMF settings back to the RT-950 Pro. Backup saved as \(backupURL.lastPathComponent)."
        deviceErrorMessage = nil
    }

    fileprivate static func friendlyLabel(for key: String) -> String {
        let explicit: [String: String] = [
            "sql": "Squelch",
            "save_mode": "Battery Save",
            "vox": "VOX Level",
            "auto_backlight": "Auto Backlight",
            "tdr": "Dual Watch",
            "tot": "Time-Out Timer",
            "beep_prompt": "Beep Prompt",
            "voice_prompt": "Voice Prompt",
            "language": "Language",
            "scan_mode": "Scan Mode",
            "ptt_id": "PTT ID Mode",
            "send_id_delay": "Send ID Delay",
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
            "rtone": "Receive Tone",
            "work_mode_a": "Work Mode A",
            "work_mode_b": "Work Mode B",
            "work_mode_c": "Work Mode C",
            "current_work_mode": "Current Work Mode",
            "current_work_area_a": "Current Work Area A",
            "current_work_area_b": "Current Work Area B",
            "current_work_area_c": "Current Work Area C",
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

    fileprivate static func functionGroup(for key: String) -> String {
        let primary = Set([
            "sql", "save_mode", "vox", "auto_backlight", "tdr", "tot",
            "beep_prompt", "voice_prompt", "scan_mode", "display_mode_a",
            "display_mode_b", "display_mode_c", "auto_key_lock", "fm_radio",
            "vox_delay", "timer_menu_quit", "weather_channel", "divide_channel",
            "lock_keyboard", "bt_write_switch", "current_work_area_a",
            "current_work_area_b", "current_work_area_c",
        ])
        return primary.contains(key) ? "Primary" : "Advanced"
    }

    fileprivate static func aprsGroup(for key: String) -> String {
        let primary = Set([
            "aprs_switch", "gps_switch", "call_sign", "time_zone", "radio_symbol",
            "routing_select", "my_position", "custom_routing_one", "custom_routing_two",
            "custom_messages", "aprs_priority", "beacon_tx_type",
        ])
        return primary.contains(key) ? "Primary" : "Advanced"
    }
}

private struct FunctionSettingsEditorSheet: View {
    let entry: RT950ProFunctionSettingsEntry
    let isBusy: Bool
    let onApply: (RT950ProFunctionSettingsEntry) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String]
    @State private var showAdvanced = false
    @State private var localErrorMessage: String?
    @State private var showProgramConfirmation = false

    init(entry: RT950ProFunctionSettingsEntry, isBusy: Bool, onApply: @escaping (RT950ProFunctionSettingsEntry) throws -> Void) {
        self.entry = entry
        self.isBusy = isBusy
        self.onApply = onApply
        _values = State(initialValue: entry.values)
    }

    private var primaryDescriptors: [RT950ProFunctionSettingDescriptor] {
        RT950ProCloneCodec.editableFunctionSettingDescriptors.filter {
            DeviceView.functionGroup(for: $0.key) != "Advanced"
        }
    }

    private var advancedDescriptors: [RT950ProFunctionSettingDescriptor] {
        RT950ProCloneCodec.editableFunctionSettingDescriptors.filter {
            DeviceView.functionGroup(for: $0.key) == "Advanced"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Core Settings")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("RadMan will read the radio again, save a backup, then program the updated core settings block back with a full safe sync.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsSection(title: "Primary Settings", descriptors: primaryDescriptors)

                    if !advancedDescriptors.isEmpty {
                        DisclosureGroup("Advanced Settings", isExpanded: $showAdvanced) {
                            settingsSection(title: nil, descriptors: advancedDescriptors)
                                .padding(.top, 12)
                        }
                    }
                }
                .padding(.trailing, 4)
            }

            if let localErrorMessage {
                RadManStatusBanner(text: localErrorMessage, tone: .warning)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(RadManSecondaryButtonStyle())

                Spacer()

                Button {
                    showProgramConfirmation = true
                } label: {
                    Label(isBusy ? "Programming..." : "Program Core Settings", systemImage: "gearshape.2")
                }
                .buttonStyle(RadManPrimaryButtonStyle())
                .disabled(isBusy)
            }
        }
        .padding(24)
        .frame(width: 760, height: 680)
        .confirmationDialog(
            "Program Core Settings?",
            isPresented: $showProgramConfirmation,
            titleVisibility: .visible
        ) {
            Button("Program Core Settings") {
                program()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("RadMan will save a managed backup, then write the updated core settings block to the RT-950 Pro.")
        }
    }

    @ViewBuilder
    private func settingsSection(title: String?, descriptors: [RT950ProFunctionSettingDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.headline)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                ForEach(descriptors) { descriptor in
                    editorField(title: DeviceView.friendlyLabel(for: descriptor.key)) {
                        switch descriptor.kind {
                        case .toggle:
                            Picker(DeviceView.friendlyLabel(for: descriptor.key), selection: binding(for: descriptor.key)) {
                                Text("Unset").tag("")
                                Text("Off").tag("Off")
                                Text("On").tag("On")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        case let .numeric(min, max):
                            Picker(DeviceView.friendlyLabel(for: descriptor.key), selection: binding(for: descriptor.key)) {
                                Text("Unset").tag("")
                                ForEach(Array(min...max), id: \.self) { value in
                                    Text(String(value)).tag(String(value))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key, default: ""] == "Unset" ? "" : values[key, default: ""] },
            set: { values[key] = $0 }
        )
    }

    private func program() {
        do {
            let normalized = values.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            try onApply(RT950ProFunctionSettingsEntry(values: normalized))
            dismiss()
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func editorField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct APRSEditorSheet: View {
    let entry: RT950ProAPRSEntry
    let isBusy: Bool
    let onApply: (RT950ProAPRSEntry) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var aprsEnabled: Bool
    @State private var gpsEnabled: Bool
    @State private var timeZone: String
    @State private var callSign: String
    @State private var ssid: String
    @State private var routingSelect: String
    @State private var myPosition: String
    @State private var radioSymbol: String
    @State private var aprsPriority: String
    @State private var beaconTxType: String
    @State private var customRoutingOne: String
    @State private var customRoutingTwo: String
    @State private var sendCustomMessages: Bool
    @State private var customMessages: String
    @State private var localErrorMessage: String?
    @State private var showProgramConfirmation = false

    init(entry: RT950ProAPRSEntry, isBusy: Bool, onApply: @escaping (RT950ProAPRSEntry) throws -> Void) {
        self.entry = entry
        self.isBusy = isBusy
        self.onApply = onApply
        _aprsEnabled = State(initialValue: entry.aprsEnabled)
        _gpsEnabled = State(initialValue: entry.gpsEnabled)
        _timeZone = State(initialValue: entry.timeZone)
        _callSign = State(initialValue: entry.callSign)
        _ssid = State(initialValue: entry.ssid)
        _routingSelect = State(initialValue: entry.routingSelect)
        _myPosition = State(initialValue: entry.myPosition)
        _radioSymbol = State(initialValue: entry.radioSymbol)
        _aprsPriority = State(initialValue: entry.aprsPriority)
        _beaconTxType = State(initialValue: entry.beaconTxType)
        _customRoutingOne = State(initialValue: entry.customRoutingOne)
        _customRoutingTwo = State(initialValue: entry.customRoutingTwo)
        _sendCustomMessages = State(initialValue: entry.sendCustomMessages)
        _customMessages = State(initialValue: entry.customMessages)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit APRS")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("RadMan will read the radio again, save a backup, then program the updated APRS block back with a full safe sync.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    Toggle("APRS Enabled", isOn: $aprsEnabled)
                    Toggle("GPS Enabled", isOn: $gpsEnabled)
                }

                GridRow {
                    editorField(title: "Time Zone") {
                        Picker("Time Zone", selection: $timeZone) {
                            Text("Unset").tag("")
                            ForEach(Array(0...23), id: \.self) { value in
                                Text(String(value)).tag(String(value))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    editorField(title: "My Position") {
                        Picker("My Position", selection: $myPosition) {
                            Text("Unset").tag("")
                            ForEach(Array(0...15), id: \.self) { value in
                                Text(String(value)).tag(String(value))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                GridRow {
                    editorField(title: "Call Sign") {
                        TextField("M0CALL", text: Binding(
                            get: { callSign },
                            set: { callSign = RadManValidationService.sanitizeASCII($0, maxLength: 6) }
                        ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    editorField(title: "SSID") {
                        Picker("SSID", selection: $ssid) {
                            Text("Unset").tag("")
                            ForEach(Array(0...15), id: \.self) { value in
                                Text(String(value)).tag(String(value))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                GridRow {
                    editorField(title: "Routing Select") {
                        Picker("Routing Select", selection: $routingSelect) {
                            Text("Unset").tag("")
                            ForEach(Array(0...15), id: \.self) { value in
                                Text(String(value)).tag(String(value))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    editorField(title: "Radio Symbol") {
                        Picker("Radio Symbol", selection: $radioSymbol) {
                            Text("Unset").tag("")
                            ForEach(Array(0...15), id: \.self) { value in
                                Text(String(value)).tag(String(value))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                GridRow {
                    editorField(title: "APRS Priority") {
                        Picker("APRS Priority", selection: $aprsPriority) {
                            Text("Unset").tag("")
                            ForEach(Array(0...2), id: \.self) { value in
                                Text(String(value)).tag(String(value))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    editorField(title: "Beacon TX Type") {
                        Picker("Beacon TX Type", selection: $beaconTxType) {
                            Text("Unset").tag("")
                            ForEach(Array(0...15), id: \.self) { value in
                                Text(String(value)).tag(String(value))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                GridRow {
                    editorField(title: "Custom Route 1") {
                        TextField("ROUTE1", text: Binding(
                            get: { customRoutingOne },
                            set: { customRoutingOne = RadManValidationService.sanitizeASCII($0, maxLength: 6) }
                        ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    editorField(title: "Custom Route 2") {
                        TextField("ROUTE2", text: Binding(
                            get: { customRoutingTwo },
                            set: { customRoutingTwo = RadManValidationService.sanitizeASCII($0, maxLength: 6) }
                        ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            Toggle("Send Custom Message", isOn: $sendCustomMessages)

            editorField(title: "Custom Message") {
                TextEditor(text: Binding(
                    get: { customMessages },
                    set: { customMessages = String($0.prefix(40)) }
                ))
                    .font(.body)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.82))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.black.opacity(0.08), lineWidth: 1)
                    )
            }

            if let localErrorMessage {
                RadManStatusBanner(text: localErrorMessage, tone: .warning)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(RadManSecondaryButtonStyle())

                Spacer()

                Button {
                    showProgramConfirmation = true
                } label: {
                    Label(isBusy ? "Programming..." : "Program APRS", systemImage: "paperplane")
                }
                .buttonStyle(RadManPrimaryButtonStyle())
                .disabled(isBusy)
            }
        }
        .padding(24)
        .frame(width: 620)
        .confirmationDialog(
            "Program APRS Settings?",
            isPresented: $showProgramConfirmation,
            titleVisibility: .visible
        ) {
            Button("Program APRS") {
                program()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("RadMan will save a managed backup, then write the updated APRS block to the RT-950 Pro.")
        }
    }

    @ViewBuilder
    private func editorField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func program() {
        do {
            try onApply(
                RT950ProAPRSEntry(
                    aprsEnabled: aprsEnabled,
                    gpsEnabled: gpsEnabled,
                    timeZone: timeZone.trimmingCharacters(in: .whitespacesAndNewlines),
                    callSign: callSign.trimmingCharacters(in: .whitespacesAndNewlines),
                    ssid: ssid.trimmingCharacters(in: .whitespacesAndNewlines),
                    routingSelect: routingSelect.trimmingCharacters(in: .whitespacesAndNewlines),
                    myPosition: myPosition.trimmingCharacters(in: .whitespacesAndNewlines),
                    radioSymbol: radioSymbol.trimmingCharacters(in: .whitespacesAndNewlines),
                    aprsPriority: aprsPriority.trimmingCharacters(in: .whitespacesAndNewlines),
                    beaconTxType: beaconTxType.trimmingCharacters(in: .whitespacesAndNewlines),
                    customRoutingOne: customRoutingOne.trimmingCharacters(in: .whitespacesAndNewlines),
                    customRoutingTwo: customRoutingTwo.trimmingCharacters(in: .whitespacesAndNewlines),
                    sendCustomMessages: sendCustomMessages,
                    customMessages: customMessages.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            dismiss()
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }
}

private struct DTMFEditorSheet: View {
    let entry: RT950ProDTMFEntry
    let isBusy: Bool
    let onApply: (RT950ProDTMFEntry) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: String
    @State private var pttMode: String
    @State private var codeGroups: [String]
    @State private var localErrorMessage: String?
    @State private var showProgramConfirmation = false

    init(entry: RT950ProDTMFEntry, isBusy: Bool, onApply: @escaping (RT950ProDTMFEntry) throws -> Void) {
        self.entry = entry
        self.isBusy = isBusy
        self.onApply = onApply
        _currentID = State(initialValue: entry.currentID)
        _pttMode = State(initialValue: entry.pttMode)
        let paddedGroups = entry.codeGroups + Array(repeating: "", count: max(0, 22 - entry.codeGroups.count))
        _codeGroups = State(initialValue: Array(paddedGroups.prefix(22)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit DTMF")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("Use digits `0-9`, letters `A-D`, or `*` and `#`. RadMan will read the radio again, save a backup, then program the updated DTMF block back with a full safe sync.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                editorField(title: "Current ID") {
                    TextField("12345", text: Binding(
                        get: { currentID },
                        set: { currentID = RadManValidationService.sanitizeDTMF($0, maxLength: 5) }
                    ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                editorField(title: "PTT Mode") {
                    Picker("PTT Mode", selection: $pttMode) {
                        Text("Unset").tag("")
                        ForEach(Array(0...3), id: \.self) { value in
                            Text(String(value)).tag(String(value))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    ForEach(codeGroups.indices, id: \.self) { index in
                        editorField(title: "Group \(index + 1)") {
                            TextField("DTMF", text: bindingForGroup(index))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
                .padding(.trailing, 4)
            }

            if let localErrorMessage {
                RadManStatusBanner(text: localErrorMessage, tone: .warning)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(RadManSecondaryButtonStyle())

                Spacer()

                Button {
                    showProgramConfirmation = true
                } label: {
                    Label(isBusy ? "Programming..." : "Program DTMF", systemImage: "phone.connection")
                }
                .buttonStyle(RadManPrimaryButtonStyle())
                .disabled(isBusy)
            }
        }
        .padding(24)
        .frame(width: 760, height: 720)
        .confirmationDialog(
            "Program DTMF Settings?",
            isPresented: $showProgramConfirmation,
            titleVisibility: .visible
        ) {
            Button("Program DTMF") {
                program()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("RadMan will save a managed backup, then write the updated DTMF block to the RT-950 Pro.")
        }
    }

    private func bindingForGroup(_ index: Int) -> Binding<String> {
        Binding(
            get: { codeGroups[index] },
            set: { codeGroups[index] = RadManValidationService.sanitizeDTMF($0, maxLength: 6) }
        )
    }

    private func program() {
        do {
            let updated = RT950ProDTMFEntry(
                currentID: currentID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                pttMode: pttMode.trimmingCharacters(in: .whitespacesAndNewlines),
                codeGroups: codeGroups.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            )
            try onApply(updated)
            dismiss()
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func editorField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DeviceDisplayField: Identifiable, Hashable {
    let label: String
    let value: String
    let group: String

    init(label: String, value: String, group: String = "Primary") {
        self.label = label
        self.value = value
        self.group = group
    }

    var id: String { label }
}

private struct DeviceFieldCard: View {
    let item: DeviceDisplayField

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(item.value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(RadManPalette.ink)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
