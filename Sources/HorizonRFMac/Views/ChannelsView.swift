import AppKit
import SwiftUI

struct ChannelsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("radman.channels.presentationMode") private var presentationModeRawValue = ChannelPresentationMode.cards.rawValue
    @AppStorage("radman.channels.sortMode") private var sortModeRawValue = ChannelSortMode.memory.rawValue
    @State private var selectedIDs: Set<ChannelMemory.ID> = []
    @State private var draft = ChannelMemory.empty
    @State private var isEditing = false
    @State private var searchText = ""
    @State private var activeFilter: ChannelQuickFilter = .all
    @State private var activeZone: Int?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isProgrammingRadio = false
    @State private var isPreviewingRadioChanges = false
    @State private var comparisonReport: RT950ProComparisonReport?
    @State private var isEditingZoneNames = false
    @State private var showDeleteConfirmation = false
    @State private var showProgramConfirmation = false

    private var filteredChannels: [ChannelMemory] {
        ChannelPlanService.sorted(
            store.channels.filter { channel in
                activeFilter.matches(channel)
                    && matchesZone(channel)
                    && matchesSearch(channel)
            },
            by: sortMode
        )
    }

    private var sortMode: ChannelSortMode {
        get { ChannelSortMode(rawValue: sortModeRawValue) ?? .memory }
        set { sortModeRawValue = newValue.rawValue }
    }

    private var memorySortedChannels: [ChannelMemory] {
        ChannelPlanService.sorted(store.channels, by: .memory)
    }

    private var zoneSummaries: [ChannelZoneSummary] {
        ChannelPlanService.zoneSummaries(from: store.channels)
    }

    private var activeZoneSummary: ChannelZoneSummary? {
        guard let activeZone else { return nil }
        return zoneSummaries.first(where: { $0.zone == activeZone })
    }

    private var preferredZoneNames: [String] {
        store.preferredZoneNames
    }

    private var presentationMode: ChannelPresentationMode {
        get { ChannelPresentationMode(rawValue: presentationModeRawValue) ?? .cards }
        set { presentationModeRawValue = newValue.rawValue }
    }

    private var selectedChannels: [ChannelMemory] {
        ChannelPlanService.sorted(store.channels.filter { selectedIDs.contains($0.id) })
    }

    private var selectedChannel: ChannelMemory? {
        selectedChannels.count == 1 ? selectedChannels.first : nil
    }

    private var selectedAnchorLocation: Int? {
        selectedChannels.compactMap(ChannelPlanService.locationValue(for:)).max()
    }

    private var highestAssignedLocation: Int {
        store.channels.compactMap(ChannelPlanService.locationValue(for:)).max() ?? 0
    }

    private var nextAddLocation: String? {
        if let activeZone {
            return store.nextAvailableChannelLocation(inZone: activeZone)
        }
        return store.nextAvailableChannelLocation()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RadManHeroCard(
                title: "Channel Manager",
                subtitle: heroSubtitle,
                accent: RadManPalette.amber
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        Text("Review memories, compare them with the live handheld, and move backups or CPS codeplugs in and out of RadMan from one place.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .trailing, spacing: 8) {
                            if let capturedAt = store.preferredRT950ProProfile?.lastNativeCloneCapturedAt {
                                heroInfoPill(
                                    "Last radio read \(capturedAt.formatted(date: .abbreviated, time: .shortened))",
                                    systemImage: "dot.radiowaves.left.and.right"
                                )
                            }

                            if let templateName = store.preferredRT950CPSTemplateName {
                                heroInfoPill("CPS template \(templateName)", systemImage: "doc.badge.gearshape")
                            } else {
                                heroInfoPill("No CPS template saved yet", systemImage: "doc.badge.plus")
                            }

                            if !selectedChannels.isEmpty {
                                heroInfoPill("\(selectedChannels.count) selected", systemImage: "checklist")
                            }
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            previewButton
                            writeButton
                            addButton
                            importMenu
                            exportMenu
                            actionsMenu
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                previewButton
                                writeButton
                                addButton
                            }

                            HStack(spacing: 10) {
                                importMenu
                                exportMenu
                                actionsMenu
                            }
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            zoneChip(title: "All Zones", count: store.channels.count, isSelected: activeZone == nil) {
                                activeZone = nil
                            }

                            ForEach(zoneSummaries) { zone in
                                zoneChip(title: store.zoneShortLabel(for: zone.zone), count: zone.usedSlots, isSelected: activeZone == zone.zone) {
                                    activeZone = zone.zone
                                }
                            }
                        }
                    }
                }
            }

            HStack(spacing: 14) {
                RadManMetricCard(
                    title: "Stored",
                    value: "\(store.channels.count)/\(store.channelCapacity)",
                    subtitle: "\(filteredChannels.count) shown, highest used slot \(highestAssignedLocation)",
                    accent: RadManPalette.teal
                )
                RadManMetricCard(
                    title: activeZone.map { store.zoneName(for: $0) } ?? "Zones",
                    value: activeZoneSummary.map { "\($0.usedSlots)/\($0.capacity)" } ?? "\(zoneSummaries.filter { $0.usedSlots > 0 }.count)/\(ChannelPlanService.zoneCount)",
                    subtitle: activeZoneSummary.map { "\($0.freeSlots) free, next slot \($0.firstAvailableSlot.map(String.init) ?? "full")" } ?? "Occupied fixed zones in the current memory plan",
                    accent: RadManPalette.slate
                )
                RadManMetricCard(
                    title: "Marine",
                    value: "\(store.channels.filter { ChannelQuickFilter.marine.matches($0) }.count)",
                    subtitle: "Marine and coastal channels",
                    accent: RadManPalette.amber
                )
                RadManMetricCard(
                    title: "Airband",
                    value: "\(store.channels.filter { ChannelQuickFilter.airband.matches($0) }.count)",
                    subtitle: "AM receive and aviation memories",
                    accent: RadManPalette.coral
                )
                RadManMetricCard(
                    title: "Tone Guard",
                    value: "\(store.channels.filter { ChannelQuickFilter.toneGuard.matches($0) }.count)",
                    subtitle: "Channels with tone or DTCS protection",
                    accent: RadManPalette.teal
                )
            }

            if let statusMessage {
                RadManStatusBanner(
                    text: statusMessage,
                    tone: statusMessage.hasPrefix("Imported")
                        || statusMessage.hasPrefix("Exported")
                        || statusMessage.hasPrefix("Updated")
                        || statusMessage.hasPrefix("Wrote")
                        ? .success
                        : .info
                )
            }

            if highestAssignedLocation >= store.channelCapacity {
                RadManStatusBanner(
                    text: "The current memory map already reaches slot \(store.channelCapacity). Insert and paste may fail until you free space or move channels lower.",
                    tone: .warning
                )
            }

            HSplitView {
                RadManPanel(
                    title: "Memory List",
                    subtitle: "Search, filter, and review the channels currently loaded in RadMan."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            TextField("Search by name, frequency, notes, or mode", text: $searchText)
                                .textFieldStyle(.roundedBorder)

                            Picker("Sort", selection: $sortModeRawValue) {
                                ForEach(ChannelSortMode.allCases) { mode in
                                    Text(mode.subtitle).tag(mode.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 170)

                            Picker("View", selection: $presentationModeRawValue) {
                                ForEach(ChannelPresentationMode.allCases) { mode in
                                    Label(mode.rawValue, systemImage: mode.systemImage).tag(mode.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)

                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .opacity(searchText.isEmpty ? 0 : 1)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(ChannelQuickFilter.allCases) { filter in
                                    let count = store.channels.filter { filter.matches($0) }.count
                                    Button {
                                        activeFilter = filter
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text(filter.rawValue)
                                            Text("\(count)")
                                                .foregroundStyle(activeFilter == filter ? .white.opacity(0.9) : .secondary)
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(activeFilter == filter ? RadManPalette.ink : RadManPalette.mist)
                                        )
                                        .foregroundStyle(activeFilter == filter ? .white : RadManPalette.ink)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if filteredChannels.isEmpty {
                            ContentUnavailableView(
                                searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No Channels Yet" : "No Matching Channels",
                                systemImage: "waveform.path.ecg.rectangle",
                                description: Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "Read the RT-950 Pro, import a backup, or add a memory manually."
                                    : "Adjust the search text or filter chips to see more memories.")
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            if presentationMode == .cards {
                                ScrollView {
                                    LazyVStack(spacing: 12) {
                                        ForEach(filteredChannels) { channel in
                                            ChannelListRow(channel: channel, isSelected: selectedIDs.contains(channel.id), zoneNames: preferredZoneNames)
                                                .onTapGesture {
                                                    selectedIDs = [channel.id]
                                                }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            } else {
                                    Table(filteredChannels, selection: $selectedIDs) {
                                    TableColumn("Zone") { channel in
                                        Text(channel.zoneNumber.map { store.zoneShortLabel(for: $0) } ?? "?")
                                    }
                                    TableColumn("Slot") { channel in
                                        Text(channel.zoneSlot.map(String.init) ?? "?")
                                    }
                                    TableColumn("Mem") { channel in
                                        Text(channel.location)
                                    }
                                    TableColumn("Name") { channel in
                                        Text(channel.displayName)
                                    }
                                    TableColumn("Receive") { channel in
                                        Text(channel.frequency)
                                            .font(.system(.body, design: .monospaced))
                                    }
                                    TableColumn("TX") { channel in
                                        Text(channel.txSummary.ifEmpty("Simplex"))
                                    }
                                    TableColumn("Mode") { channel in
                                        Text(channel.modeDisplay)
                                    }
                                    TableColumn("Tone") { channel in
                                        Text(channel.toneSummary.ifEmpty("Carrier"))
                                    }
                                    TableColumn("Power") { channel in
                                        Text(channel.power.ifEmpty("Unset"))
                                    }
                                }
                                .tableStyle(.inset(alternatesRowBackgrounds: true))
                            }
                        }
                    }
                }
                .frame(minWidth: 520)

                RadManPanel(
                title: selectedChannels.isEmpty ? "Inspector" : (selectedChannel == nil ? "Batch Selection" : "Selected Memory"),
                subtitle: selectedChannels.isEmpty
                    ? "Choose a channel on the left to see its details."
                    : (selectedChannel == nil
                            ? "You can copy, paste, or delete the selected memory block as a group."
                            : "Review the saved frequency plan, zone placement, and RT-950 native options.")
                ) {
                    if let selectedChannel {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 10) {
                                            Text(selectedChannel.displayName)
                                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                            RadManBadge(text: selectedChannel.categoryTitle, accent: selectedChannel.categoryAccent)
                                        }
                                        Text(selectedChannel.frequency.isEmpty ? "No receive frequency saved" : selectedChannel.frequency + " MHz")
                                            .font(.title3.weight(.medium))
                                        HStack(spacing: 8) {
                                            RadManBadge(text: selectedChannel.modeDisplay, accent: RadManPalette.teal)
                                            if !selectedChannel.power.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                RadManBadge(text: selectedChannel.power, accent: RadManPalette.amber)
                                            }
                                            if !selectedChannel.toneSummary.isEmpty {
                                                RadManBadge(text: selectedChannel.toneSummary, accent: RadManPalette.coral)
                                            }
                                        }
                                    }
                                    Spacer()
                                }

                                HStack(spacing: 12) {
                                    Button {
                                        draft = selectedChannel
                                        isEditing = true
                                    } label: {
                                        Label("Edit Memory", systemImage: "square.and.pencil")
                                    }
                                    .buttonStyle(RadManPrimaryButtonStyle())

                                    Button(role: .destructive) {
                                        requestDeleteSelectedChannels()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .buttonStyle(RadManSecondaryButtonStyle())
                                }

                                ChannelInspectorGrid(channel: selectedChannel, zoneNames: preferredZoneNames)
                            }
                        }
                    } else if !selectedChannels.isEmpty {
                        BatchSelectionSummary(
                            channels: selectedChannels,
                            zoneNames: preferredZoneNames,
                            onCopy: copySelectedChannels,
                            onPaste: pasteCopiedChannels,
                            onDelete: requestDeleteSelectedChannels
                        )
                    } else {
                        ContentUnavailableView(
                            "Select a Channel",
                            systemImage: "dot.scope.display",
                            description: Text("Pick a memory from the list to inspect its receive frequency, transmit behaviour, signalling, and RT-950 extras.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 360)
            }
        }
        .padding(24)
        .sheet(isPresented: $isEditing) {
            ChannelEditorView(channel: draft, existingChannels: store.channels) { updatedChannel, overwriteExistingLocation in
                try store.upsert(updatedChannel, overwriteExistingLocation: overwriteExistingLocation)
                selectedIDs = [updatedChannel.id]
                statusMessage = overwriteExistingLocation
                    ? "Overwrote memory \(updatedChannel.location) with \(updatedChannel.name.isEmpty ? "the edited channel" : updatedChannel.name)."
                    : "Saved channel \(updatedChannel.name.isEmpty ? "entry" : updatedChannel.name)."
            }
        }
        .alert("Action Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: Binding(get: { comparisonReport != nil }, set: { if !$0 { comparisonReport = nil } })) {
            if let comparisonReport {
                RT950ProComparisonSheet(report: comparisonReport)
            }
        }
        .confirmationDialog(
            "Delete Selected Frequencies?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Frequencies", role: .destructive) {
                deleteSelectedChannels()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(selectedChannels.count == 1
                ? "This will remove the selected memory from RadMan."
                : "This will remove \(selectedChannels.count) selected memories from RadMan.")
        }
        .confirmationDialog(
            "Write Frequencies To Radio?",
            isPresented: $showProgramConfirmation,
            titleVisibility: .visible
        ) {
            Button("Write To Radio") {
                programRadioFromChannels()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("RadMan will read the RT-950 Pro again, save a managed backup, then program the current frequency list to the radio.")
        }
        .sheet(isPresented: $isEditingZoneNames) {
            ZoneManagerSheet(zoneNames: preferredZoneNames) { updatedZoneNames in
                store.updatePreferredZoneNames(updatedZoneNames)
                statusMessage = "Updated the RT-950 Pro zone labels."
            }
        }
    }

    private var heroSubtitle: String {
        if let selectedChannel {
            return "Focused on \(store.zoneSummaryLabel(for: selectedChannel)) / memory \(selectedChannel.location.isEmpty ? "?" : selectedChannel.location): \(selectedChannel.displayName) at \(selectedChannel.frequency.isEmpty ? "unspecified frequency" : selectedChannel.frequency + " MHz")."
        }
        if !selectedChannels.isEmpty {
            return "\(selectedChannels.count) memories selected. You can copy them, paste them below another slot, or delete them as a batch."
        }
        if let activeZoneSummary {
            let zoneName = store.zoneName(for: activeZoneSummary.zone)
            return "\(zoneName) is selected. \(activeZoneSummary.usedSlots) of \(activeZoneSummary.capacity) slots are populated, and the next free slot is \(activeZoneSummary.firstAvailableSlot.map(String.init) ?? "not available")."
        }
        if let capturedAt = store.preferredRT950ProProfile?.lastNativeCloneCapturedAt {
            return "Your current list includes \(store.channels.count) saved memories across slots 1-\(highestAssignedLocation). The most recent live radio snapshot was captured \(capturedAt.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Review and edit channel memories from CSV imports, RT-950 backups, or a live radio read. The current RT-950 Pro workflow supports \(ChannelPlanService.zoneCount) zones with \(ChannelPlanService.slotsPerZone) slots each."
    }

    private func matchesZone(_ channel: ChannelMemory) -> Bool {
        guard let activeZone else { return true }
        return channel.zoneNumber == activeZone
    }

    private func matchesSearch(_ channel: ChannelMemory) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [
            channel.location,
            channel.name,
            channel.frequency,
            channel.duplex,
            channel.offset,
            channel.tone,
            channel.mode,
            channel.comment,
            channel.categoryTitle,
        ]
        .joined(separator: " ")
        .localizedCaseInsensitiveContains(query)
    }

    private func importChannels() {
        guard let url = AppDialogs.chooseCSVFile() else { return }
        do {
            let count = try store.importChannels(from: url)
            searchText = ""
            selectedIDs = Set(memorySortedChannels.prefix(1).map(\.id))
            statusMessage = "Imported \(count) channels from \(url.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func exportChannels() {
        guard let url = AppDialogs.saveCSVFile(defaultName: "RadMan-Channels.csv") else { return }
        do {
            try store.exportChannels(to: url)
            statusMessage = "Exported \(store.channels.count) channels to \(url.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func importRT950Backup() {
        guard let url = AppDialogs.chooseRT950BackupFile() else { return }
        do {
            let result = try store.importRT950ProBackup(from: url)
            searchText = ""
            selectedIDs = Set(memorySortedChannels.prefix(1).map(\.id))
            if let embeddedProfileName = result.embeddedProfileName, !embeddedProfileName.isEmpty {
                statusMessage = "Imported \(result.channelCount) RT-950 Pro channels from \(url.lastPathComponent) and restored profile \(embeddedProfileName)."
            } else {
                statusMessage = "Imported \(result.channelCount) RT-950 Pro channels from \(url.lastPathComponent)."
            }
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func importRT950CPSCodeplug() {
        guard let url = AppDialogs.chooseRT950CPSFile() else { return }
        do {
            let result = try store.importRT950CPSCodeplug(from: url)
            searchText = ""
            selectedIDs = Set(memorySortedChannels.prefix(1).map(\.id))

            var message = "Imported \(result.importedChannelCount) RT-950 Pro frequencies from \(url.lastPathComponent)."
            if result.hasZoneNames {
                message += " Loaded \(result.importedZoneCount) zone names."
            }
            if !result.notes.isEmpty {
                message += " " + result.notes.joined(separator: " ")
            }
            statusMessage = message
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func exportRT950Backup() {
        let suggestedProfile = store.preferredRT950ProProfile
        let baseName: String
        if let suggestedProfile, !suggestedProfile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseName = suggestedProfile.name
        } else {
            baseName = "RT950Pro"
        }

        guard let url = AppDialogs.saveRT950BackupFile(defaultName: "\(baseName)-Backup.json") else { return }
        do {
            try store.exportRT950ProBackup(to: url, radioProfile: suggestedProfile)
            if let suggestedProfile {
                statusMessage = "Exported \(store.channels.count) channels to RT-950 Pro backup \(url.lastPathComponent) using profile \(suggestedProfile.name.isEmpty ? suggestedProfile.resolvedModelName : suggestedProfile.name)."
            } else {
                statusMessage = "Exported \(store.channels.count) channels to RT-950 Pro backup \(url.lastPathComponent)."
            }
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func exportRT950CPSCodeplug() {
        let suggestedProfile = store.preferredRT950ProProfile
        let baseName = (suggestedProfile?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? suggestedProfile!.name : "RT950Pro")

        guard let url = AppDialogs.saveRT950CPSFile(defaultName: "\(baseName)-Codeplug.dat") else { return }

        let templateURL: URL?
        if store.currentRT950CPSTemplateData(profile: suggestedProfile) == nil {
            guard let selectedTemplate = AppDialogs.chooseRT950CPSFile() else { return }
            templateURL = selectedTemplate
        } else {
            templateURL = nil
        }

        do {
            let templateName = try store.exportRT950CPSCodeplug(to: url, profile: suggestedProfile, templateURL: templateURL)
            statusMessage = "Exported \(store.channels.count) RT-950 Pro frequencies to \(url.lastPathComponent) using CPS template \(templateName)."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func startAddingChannel() {
        draft = .empty
        if let activeZone, let next = store.nextAvailableChannelLocation(inZone: activeZone) {
            draft.location = next
        } else {
            draft.location = store.nextAvailableChannelLocation() ?? ""
        }
        isEditing = true
    }

    private func insertBlankRow() {
        do {
            let inserted = try store.insertBlankChannel(afterLocation: selectedAnchorLocation)
            selectedIDs = [inserted.id]
            statusMessage = "Inserted a new blank row at memory \(inserted.location)."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func copySelectedChannels() {
        do {
            try ChannelClipboardService.copy(selectedChannels)
            statusMessage = "Copied \(selectedChannels.count) channel\(selectedChannels.count == 1 ? "" : "s") to the clipboard."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func pasteCopiedChannels() {
        do {
            let copied = try ChannelClipboardService.paste()
            let pasted = try store.pasteChannels(copied, afterLocation: selectedAnchorLocation)
            selectedIDs = Set(pasted.map(\.id))
            statusMessage = "Pasted \(pasted.count) channel\(pasted.count == 1 ? "" : "s") starting at memory \(pasted.first?.location ?? "?")."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func requestDeleteSelectedChannels() {
        guard !selectedChannels.isEmpty else { return }
        showDeleteConfirmation = true
    }

    private func deleteSelectedChannels() {
        let names = selectedChannels.prefix(3).map(\.displayName)
        let count = selectedChannels.count
        store.deleteChannels(ids: selectedIDs)
        selectedIDs.removeAll()
        if count > 0 {
            let preview = names.joined(separator: ", ")
            statusMessage = count == 1
                ? "Deleted channel \(preview)."
                : "Deleted \(count) channels\(preview.isEmpty ? "" : ": \(preview)")."
        }
    }

    private func programRadioFromChannels() {
        isProgrammingRadio = true
        defer { isProgrammingRadio = false }

        do {
            let backupURL = try store.programCurrentChannelsToRadio()
            statusMessage = "Wrote the current frequency list to the RT-950 Pro. Backup saved as \(backupURL.lastPathComponent)."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func previewRadioChanges() {
        isPreviewingRadioChanges = true
        defer { isPreviewingRadioChanges = false }

        do {
            comparisonReport = try store.previewCurrentChannelPlanAgainstRadio()
            statusMessage = comparisonReport?.hasChanges == true
                ? "Previewed the difference between the current RadMan frequency list and the live radio."
                : "The current RadMan frequency list already matches the live radio."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    @ViewBuilder
    private var previewButton: some View {
        Button {
            previewRadioChanges()
        } label: {
            toolbarLabel(isPreviewingRadioChanges ? "Previewing..." : "Preview", systemImage: "arrow.left.arrow.right.square")
        }
        .buttonStyle(RadManSecondaryButtonStyle())
        .disabled(store.channels.isEmpty || store.preferredRT950ProProfile == nil || isPreviewingRadioChanges || isProgrammingRadio)
    }

    @ViewBuilder
    private var writeButton: some View {
        Button {
            showProgramConfirmation = true
        } label: {
            toolbarLabel(isProgrammingRadio ? "Writing..." : "Write To Radio", systemImage: "antenna.radiowaves.left.and.right")
        }
        .buttonStyle(RadManPrimaryButtonStyle())
        .disabled(store.channels.isEmpty || store.preferredRT950ProProfile == nil || isProgrammingRadio)
    }

    @ViewBuilder
    private var addButton: some View {
        Button {
            startAddingChannel()
        } label: {
            toolbarLabel("Add Channel", systemImage: "plus")
        }
        .buttonStyle(RadManSecondaryButtonStyle())
        .disabled(nextAddLocation == nil)
    }

    @ViewBuilder
    private var importMenu: some View {
        Menu {
            Button("Import Channel CSV") {
                importChannels()
            }
            Button("Import RT-950 Pro Backup") {
                importRT950Backup()
            }
            Button("Import RT-950 Pro CPS File") {
                importRT950CPSCodeplug()
            }
        } label: {
            toolbarLabel("Import", systemImage: "square.and.arrow.down")
        }
        .menuStyle(.button)
        .buttonStyle(RadManSecondaryButtonStyle())
    }

    @ViewBuilder
    private var exportMenu: some View {
        Menu {
            Button("Export Channel CSV") {
                exportChannels()
            }
            Button("Export RT-950 Pro Backup") {
                exportRT950Backup()
            }
            Button("Export RT-950 Pro CPS File") {
                exportRT950CPSCodeplug()
            }
        } label: {
            toolbarLabel("Export", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.button)
        .buttonStyle(RadManSecondaryButtonStyle())
    }

    @ViewBuilder
    private var actionsMenu: some View {
        Menu {
            Button("Insert Row") {
                insertBlankRow()
            }

            Button("Edit Selected") {
                guard let channel = selectedChannel else { return }
                draft = channel
                isEditing = true
            }
            .disabled(selectedChannel == nil)

            Divider()

            Button("Copy Selection") {
                copySelectedChannels()
            }
            .disabled(selectedChannels.isEmpty)

            Button("Paste Below") {
                pasteCopiedChannels()
            }
            .disabled(!ChannelClipboardService.hasChannels())

            Button("Edit Zones") {
                isEditingZoneNames = true
            }

            Divider()

            Button("Delete Selection", role: .destructive) {
                requestDeleteSelectedChannels()
            }
            .disabled(selectedChannels.isEmpty)
        } label: {
            toolbarLabel("More", systemImage: "ellipsis.circle")
        }
        .menuStyle(.button)
        .buttonStyle(RadManSecondaryButtonStyle())
    }

    @ViewBuilder
    private func heroInfoPill(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.10))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func toolbarLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private func zoneChip(title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                Text("\(count)")
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? RadManPalette.teal : RadManPalette.mist)
            )
            .foregroundStyle(isSelected ? .white : RadManPalette.ink)
        }
        .buttonStyle(.plain)
    }
}

private enum ChannelPresentationMode: String, CaseIterable, Identifiable {
    case cards = "Cards"
    case table = "Table"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .cards:
            return "square.grid.2x2"
        case .table:
            return "tablecells"
        }
    }
}

private enum ChannelQuickFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case marine = "Marine"
    case airband = "Airband"
    case amateur = "Amateur"
    case pmr = "PMR"
    case toneGuard = "Tone Guard"
    case receiveOnly = "RX Only"

    var id: String { rawValue }

    func matches(_ channel: ChannelMemory) -> Bool {
        switch self {
        case .all:
            return true
        case .marine:
            return channel.category == .marine
        case .airband:
            return channel.category == .airband
        case .amateur:
            return channel.category == .amateur
        case .pmr:
            return channel.category == .pmr
        case .toneGuard:
            return !channel.toneSummary.isEmpty
        case .receiveOnly:
            return channel.duplex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "off"
        }
    }
}

private struct ChannelListRow: View {
    let channel: ChannelMemory
    let isSelected: Bool
    let zoneNames: [String]

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(channel.zoneNumber.map { "Z\($0)" } ?? "Z?")
                    .font(.caption.weight(.bold))
                Text(channel.zoneSlot.map(String.init) ?? "?")
                    .font(.headline.monospacedDigit())
            }
                .frame(width: 52, height: 52)
                .background(channel.categoryAccent.opacity(0.14))
                .foregroundStyle(channel.categoryAccent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(channel.displayName)
                        .font(.headline)
                    RadManBadge(text: channel.categoryTitle, accent: channel.categoryAccent)
                    RadManBadge(text: channel.zoneSummaryLabel(using: zoneNames), accent: RadManPalette.slate)
                }
                HStack(spacing: 10) {
                    Text(channel.frequency.isEmpty ? "No RX frequency" : channel.frequency + " MHz")
                        .font(.system(.body, design: .monospaced))
                    Text("Mem \(channel.location.ifEmpty("?"))")
                        .foregroundStyle(.secondary)
                    if !channel.txSummary.isEmpty {
                        Text(channel.txSummary)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    if !channel.modeDisplay.isEmpty {
                        RadManBadge(text: channel.modeDisplay, accent: RadManPalette.teal)
                    }
                    if !channel.power.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        RadManBadge(text: channel.power, accent: RadManPalette.amber)
                    }
                    if !channel.toneSummary.isEmpty {
                        RadManBadge(text: channel.toneSummary, accent: RadManPalette.coral)
                    }
                }
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? channel.categoryAccent.opacity(0.18) : Color.white.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? channel.categoryAccent.opacity(0.55) : .black.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct ChannelInspectorGrid: View {
    let channel: ChannelMemory
    let zoneNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RadManPanel(title: "Frequency Plan") {
                LazyVGrid(columns: inspectorColumns, spacing: 12) {
                    InspectorField(label: "Memory", value: channel.location.isEmpty ? "Unassigned" : channel.location)
                    InspectorField(label: "Zone", value: channel.zoneLabel(using: zoneNames))
                    InspectorField(label: "Zone Slot", value: channel.zoneSlotLabel)
                    InspectorField(label: "Receive", value: channel.frequency.isEmpty ? "Unset" : channel.frequency + " MHz")
                    InspectorField(label: "Transmit", value: channel.txSummary.isEmpty ? "Simplex / same as RX" : channel.txSummary)
                    InspectorField(label: "Mode", value: channel.modeDisplay)
                    InspectorField(label: "Power", value: channel.power.isEmpty ? "Unset" : channel.power)
                    InspectorField(label: "Skip", value: channel.skip.uppercased() == "S" ? "Skip during scan" : "Included in scan")
                }
            }

            RadManPanel(title: "Tone and Signalling") {
                LazyVGrid(columns: inspectorColumns, spacing: 12) {
                    InspectorField(label: "Tone Mode", value: channel.toneSummary.isEmpty ? "Carrier squelch" : channel.toneSummary)
                    InspectorField(label: "TX Tone", value: channel.rToneFreq.isEmpty ? "None" : channel.rToneFreq)
                    InspectorField(label: "RX Tone", value: channel.cToneFreq.isEmpty ? "None" : channel.cToneFreq)
                    InspectorField(label: "DTCS", value: channel.dtcsCode.isEmpty ? "None" : channel.dtcsCode)
                    InspectorField(label: "RX DTCS", value: channel.rxDtcsCode.isEmpty ? "None" : channel.rxDtcsCode)
                    InspectorField(label: "Cross Mode", value: channel.crossMode.isEmpty ? "None" : channel.crossMode)
                }
            }

            RadManPanel(title: "RT-950 Native Options", subtitle: "These fields are preserved when RadMan writes back to the radio.") {
                LazyVGrid(columns: inspectorColumns, spacing: 12) {
                    InspectorField(label: "Signal Group", value: channel.nativeSignalGroup.ifEmpty("0"))
                    InspectorField(label: "PTT ID", value: channel.nativePTTID.ifEmpty("0"))
                    InspectorField(label: "Scrambler", value: channel.nativeScrambler.ifEmpty("0"))
                    InspectorField(label: "Encryption", value: channel.nativeEncryption.ifEmpty("0"))
                    InspectorField(label: "Busy Lockout", value: channel.nativeBusyLockout ? "Enabled" : "Disabled")
                    InspectorField(label: "Learn FHSS", value: channel.nativeLearnFHSS ? "Enabled" : "Disabled")
                    InspectorField(label: "FHSS Code", value: channel.nativeFHSSCode.ifEmpty("None"))
                }
            }

            if !channel.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                RadManPanel(title: "Notes") {
                    Text(channel.comment)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var inspectorColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 180), spacing: 12)]
    }
}

private struct InspectorField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(RadManPalette.ink)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct BatchSelectionSummary: View {
    let channels: [ChannelMemory]
    let zoneNames: [String]
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(channels.count) Memories Selected")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("This is RadMan’s batch memory workflow. Copy the selection, paste it below another memory, or remove the whole block.")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(action: onCopy) {
                    Label("Copy Selection", systemImage: "doc.on.doc")
                }
                .buttonStyle(RadManPrimaryButtonStyle())

                Button(action: onPaste) {
                    Label("Paste Below", systemImage: "clipboard")
                }
                .buttonStyle(RadManSecondaryButtonStyle())

                Button(role: .destructive, action: onDelete) {
                    Label("Delete Selection", systemImage: "trash")
                }
                .buttonStyle(RadManSecondaryButtonStyle())
            }

            RadManPanel(title: "Selected Rows Preview") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(channels.prefix(8))) { channel in
                        HStack {
                            Text(channel.zoneSummaryLabel(using: zoneNames))
                                .font(.body.monospacedDigit())
                                .frame(width: 160, alignment: .leading)
                            Text(channel.displayName)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(channel.frequency.ifEmpty("No RX frequency"))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if channels.count > 8 {
                        Text("Plus \(channels.count - 8) more selected rows.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct ZoneManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var zoneNames: [String]
    let onSave: ([String]) -> Void
    @State private var localStatusMessage: String?
    @State private var localErrorMessage: String?

    init(zoneNames: [String], onSave: @escaping ([String]) -> Void) {
        _zoneNames = State(initialValue: ChannelPlanService.normalizedZoneNames(zoneNames))
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Manage Zones")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("Set the local RT-950 Pro zone labels that RadMan shows across the dashboard, channel manager, and device workflow. You can also pull named zones from a CPS `.dat` file when that file exposes them clearly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let localStatusMessage {
                RadManStatusBanner(text: localStatusMessage, tone: .success)
            }

            if let localErrorMessage {
                RadManStatusBanner(text: localErrorMessage, tone: .warning)
            }

            HStack(spacing: 12) {
                Button {
                    importFromCPS()
                } label: {
                    Label("Import From CPS", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(RadManSecondaryButtonStyle())

                Spacer()
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(0..<ChannelPlanService.zoneCount, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Zone \(index + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("Zone \(index + 1)", text: binding(for: index))
                                .textFieldStyle(.roundedBorder)
                            Text(ChannelPlanService.zoneShortLabel(for: index + 1, customNames: zoneNames))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white.opacity(0.74))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(RadManSecondaryButtonStyle())

                Spacer()

                Button {
                    onSave(zoneNames)
                    dismiss()
                } label: {
                    Label("Save Zone Names", systemImage: "square.and.arrow.down.on.square")
                }
                .buttonStyle(RadManPrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 760, height: 640)
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { zoneNames[index] },
            set: { zoneNames[index] = $0 }
        )
    }

    private func importFromCPS() {
        guard let url = AppDialogs.chooseRT950CPSFile() else { return }

        do {
            let result = try RT950ProCPSService.inspectFile(at: url)
            if result.hasZoneNames {
                zoneNames = ChannelPlanService.normalizedZoneNames(result.zoneNames)
                localStatusMessage = "Imported \(result.importedZoneCount) zone names from \(url.lastPathComponent)."
                localErrorMessage = nil
            } else {
                localStatusMessage = result.notes.joined(separator: " ")
                localErrorMessage = nil
            }
        } catch {
            localErrorMessage = error.localizedDescription
            localStatusMessage = nil
        }
    }
}


private struct ChannelEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var channel: ChannelMemory
    @State private var memoryLocationText: String
    @State private var showOverwriteConfirmation = false
    let existingChannels: [ChannelMemory]
    let onSave: (ChannelMemory, Bool) throws -> Void
    @State private var errorMessage: String?

    init(
        channel: ChannelMemory,
        existingChannels: [ChannelMemory],
        onSave: @escaping (ChannelMemory, Bool) throws -> Void
    ) {
        self.existingChannels = existingChannels
        self.onSave = onSave
        var initialChannel = channel
        if initialChannel.mode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            initialChannel.mode = "FM"
        }
        if initialChannel.dtmcsNeedsDefaults {
            initialChannel.dtmcsSanitize()
        }
        if initialChannel.nativeSignalGroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            initialChannel.nativeSignalGroup = "0"
        }
        if initialChannel.nativePTTID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            initialChannel.nativePTTID = "0"
        }
        if initialChannel.nativeScrambler.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            initialChannel.nativeScrambler = "0"
        }
        if initialChannel.nativeEncryption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            initialChannel.nativeEncryption = "0"
        }
        _channel = State(initialValue: initialChannel)
        _memoryLocationText = State(initialValue: channel.location)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(channel.name.isEmpty ? "New Channel" : "Edit Channel")
                .font(.title2.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupBox("Core Memory Fields") {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                            GridRow {
                                textInputField(title: "Memory (1-960)") {
                                    VStack(alignment: .leading, spacing: 6) {
                                        TextField("1", text: Binding(
                                            get: { memoryLocationText },
                                            set: { memoryLocationText = RadManValidationService.sanitizeDigits($0, maxLength: 3) }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))

                                        if let conflictingChannel {
                                            Text("Memory \(memoryLocationText) currently contains \(conflictingChannel.displayName). Saving will ask whether to overwrite it.")
                                                .font(.caption)
                                                .foregroundStyle(RadManPalette.coral)
                                        } else {
                                            Text("Type a memory number directly. RadMan will place it into the matching zone and slot automatically.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                textInputField(title: "Zone / Slot") {
                                    TextField("Zone / Slot", text: .constant(computedPlacementLabel))
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(true)
                                }
                                textInputField(title: "Name") {
                                    TextField("Name", text: Binding(
                                        get: { channel.name },
                                        set: { channel.name = String($0.prefix(12)) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                }
                            }
                            GridRow {
                                textInputField(title: "Memory Map") {
                                    TextField("Memory Map", text: .constant(memorySummaryLabel))
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(true)
                                }
                                textInputField(title: "Frequency (MHz)") {
                                    TextField("145.500000", text: Binding(
                                        get: { channel.frequency },
                                        set: { channel.frequency = RadManValidationService.sanitizeMHzTyping($0) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                }
                                Picker("Duplex", selection: $channel.duplex) {
                                    Text("simplex").tag("")
                                    Text("+").tag("+")
                                    Text("-").tag("-")
                                    Text("split").tag("split")
                                    Text("off").tag("off")
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                            GridRow {
                                textInputField(title: channel.duplex == "split" ? "TX Frequency (MHz)" : "Offset (MHz)") {
                                    TextField(channel.duplex == "split" ? "145.100000" : "0.600000", text: Binding(
                                        get: { channel.offset },
                                        set: { channel.offset = RadManValidationService.sanitizeMHzTyping($0) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                }
                                optionPicker(title: "Mode", selection: $channel.mode, options: RadManValidationService.channelModes, includeUnset: false)
                                optionPicker(title: "Tuning Step", selection: $channel.tStep, options: RadManValidationService.tuningSteps)
                            }
                            GridRow {
                                optionPicker(title: "Power", selection: $channel.power, options: RadManValidationService.powerLevels)
                                optionPicker(title: "Scan", selection: $channel.skip, options: RadManValidationService.scanOptions, labels: ["": "Include", "S": "Skip"])
                                Text("")
                            }
                        }
                    }

                    GroupBox("Tone and Signalling") {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                            GridRow {
                                optionPicker(title: "Tone Mode", selection: $channel.tone, options: RadManValidationService.toneModes, labels: ["": "None"])
                                optionPicker(title: "TX Tone", selection: $channel.rToneFreq, options: RadManValidationService.ctcssTones, labels: ["": "None"])
                                optionPicker(title: "RX Tone", selection: $channel.cToneFreq, options: RadManValidationService.ctcssTones, labels: ["": "None"])
                            }
                            GridRow {
                                optionPicker(title: "DTCS Code", selection: $channel.dtcsCode, options: RadManValidationService.dtcsCodes)
                                optionPicker(title: "DTCS Polarity", selection: $channel.dtcsPolarity, options: RadManValidationService.dtcsPolarities, labels: ["": "NN"])
                                optionPicker(title: "RX DTCS", selection: $channel.rxDtcsCode, options: RadManValidationService.dtcsCodes)
                            }
                            GridRow {
                                optionPicker(title: "Cross Mode", selection: $channel.crossMode, options: RadManValidationService.crossModes, labels: ["": "None"])
                                Text("")
                                Text("")
                            }
                        }
                    }

                    GroupBox("Comments and Digital Fields") {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                            GridRow {
                                textInputField(title: "Comment") {
                                    TextField("Comment", text: $channel.comment)
                                        .textFieldStyle(.roundedBorder)
                                }
                                textInputField(title: "URCALL") {
                                    TextField("URCALL", text: $channel.urcall)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            GridRow {
                                textInputField(title: "RPT1CALL") {
                                    TextField("RPT1CALL", text: $channel.rpt1call)
                                        .textFieldStyle(.roundedBorder)
                                }
                                textInputField(title: "RPT2CALL") {
                                    TextField("RPT2CALL", text: $channel.rpt2call)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            GridRow {
                                textInputField(title: "DVCODE") {
                                    TextField("DVCODE", text: Binding(
                                        get: { channel.dvcode },
                                        set: { channel.dvcode = RadManValidationService.sanitizeDigits($0, maxLength: 3) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                }
                                Text("")
                            }
                        }
                    }

                    GroupBox("RT-950 Native Extras") {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                            GridRow {
                                optionPicker(title: "Signal Group", selection: $channel.nativeSignalGroup, options: RadManValidationService.numericOptions(in: 0...15), includeUnset: false)
                                optionPicker(title: "PTT ID", selection: $channel.nativePTTID, options: RadManValidationService.numericOptions(in: 0...15), includeUnset: false)
                                textInputField(title: "FHSS Code") {
                                    TextField("ABC123", text: Binding(
                                        get: { channel.nativeFHSSCode },
                                        set: { channel.nativeFHSSCode = RadManValidationService.sanitizeHex($0, maxLength: 6) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                }
                            }
                            GridRow {
                                optionPicker(title: "Scrambler", selection: $channel.nativeScrambler, options: RadManValidationService.numericOptions(in: 0...15), includeUnset: false)
                                optionPicker(title: "Encryption", selection: $channel.nativeEncryption, options: RadManValidationService.numericOptions(in: 0...3), includeUnset: false)
                                Toggle("Busy Lockout", isOn: $channel.nativeBusyLockout)
                            }
                            GridRow {
                                Toggle("Learn FHSS", isOn: $channel.nativeLearnFHSS)
                                Text("")
                                Text("")
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    attemptSave(overwriteExistingLocation: false)
                }
                .keyboardShortcut(.defaultAction)
            }

            if let errorMessage {
                RadManStatusBanner(text: errorMessage, tone: .warning)
            }
        }
        .padding(24)
        .frame(minWidth: 780, minHeight: 640)
        .confirmationDialog(
            "Overwrite Existing Memory?",
            isPresented: $showOverwriteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Overwrite Memory", role: .destructive) {
                attemptSave(overwriteExistingLocation: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let conflictingChannel {
                Text("Memory \(memoryLocationText) already holds \(conflictingChannel.displayName). Overwriting will replace that saved frequency in RadMan.")
            } else {
                Text("That memory is already in use.")
            }
        }
    }

    private var parsedLocation: Int? {
        ChannelPlanService.locationValue(for: {
            var draft = ChannelMemory()
            draft.location = memoryLocationText
            return draft
        }())
    }

    private var conflictingChannel: ChannelMemory? {
        guard let location = parsedLocation else { return nil }
        return ChannelPlanService.conflictingChannel(at: location, excluding: channel.id, in: existingChannels)
    }

    private var computedPlacementLabel: String {
        guard let location = parsedLocation else {
            return "Choose memory 1-960"
        }
        let zone = ChannelPlanService.zone(forLocation: location)
        let slot = ChannelPlanService.slot(forLocation: location)
        return "Zone \(zone), Slot \(slot)"
    }

    private var memorySummaryLabel: String {
        guard let location = parsedLocation else {
            return "Enter a valid memory number"
        }
        return "Memory \(location) of \(ChannelPlanService.maxMemoryCount)"
    }

    private func attemptSave(overwriteExistingLocation: Bool) {
        do {
            let location = try ChannelPlanService.requiredLocation(memoryLocationText)
            if !overwriteExistingLocation, conflictingChannel != nil {
                showOverwriteConfirmation = true
                return
            }

            channel.dtmcsSanitize()
            channel.location = String(location)
            channel = try RadManValidationService.normalizeChannel(channel)
            try onSave(channel, overwriteExistingLocation)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func textInputField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func optionPicker(
        title: String,
        selection: Binding<String>,
        options: [String],
        includeUnset: Bool = true,
        labels: [String: String] = [:]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                if includeUnset && !options.contains("") {
                    Text("Unset").tag("")
                }
                ForEach(options, id: \.self) { option in
                    Text(labels[option] ?? (option.isEmpty ? "Unset" : option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

}

private extension ChannelMemory {
    var dtmcsNeedsDefaults: Bool {
        dtcsPolarity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !nativeFHSSCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !dtcsCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !rxDtcsCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !dvcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func dtmcsSanitize() {
        dtcsCode = RadManValidationService.sanitizeDigits(dtcsCode, maxLength: 3)
        rxDtcsCode = RadManValidationService.sanitizeDigits(rxDtcsCode, maxLength: 3)
        dvcode = RadManValidationService.sanitizeDigits(dvcode, maxLength: 3)
        dtcsPolarity = dtcsPolarity.isEmpty ? "NN" : dtcsPolarity
        nativeFHSSCode = RadManValidationService.sanitizeHex(nativeFHSSCode, maxLength: 6)
    }
}
