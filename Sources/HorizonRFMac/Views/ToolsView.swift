import SwiftUI

struct ToolsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var now = Date()
    @State private var serialPorts = RT950ProUSBService.availablePorts()
    @State private var usbStatusMessage: String?
    @State private var usbErrorMessage: String?
    @State private var lastUSBIdentity: RT950ProUSBIdentificationReport?
    @State private var lastCloneReport: RT950ProUSBCloneReport?
    @State private var comparisonReport: RT950ProComparisonReport?
    @State private var isComparing = false
    @State private var isRestoringSection = false
    @State private var showAdvancedDetails = false
    @State private var pendingFullRestoreURL: URL?
    @State private var pendingSelectiveRestoreURL: URL?
    @State private var pendingSelectiveRestoreSection: RT950ProSelectiveRestoreSection?
    private let standaloneTarget = RadioCatalog.preferredStandaloneTarget
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let localFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .long
        formatter.timeZone = .current
        return formatter
    }()
    private let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .long
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private var primaryRT950Profile: RadioProfile? {
        store.preferredRT950ProProfile
    }

    private var hasStoredClone: Bool {
        primaryRT950Profile?.lastNativeCloneBase64.isEmpty == false
    }

    private var usbPreflight: RT950ProUSBPreflightReport {
        RT950ProUSBService.preflight(profile: primaryRT950Profile, availablePorts: serialPorts)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RadManHeroCard(
                    title: "RT-950 Pro Sync",
                    subtitle: heroSubtitle,
                    accent: RadManPalette.teal
                ) {
                    HStack(spacing: 12) {
                        Button {
                            readRT950IntoRadMan()
                        } label: {
                            Label("Read Radio Now", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .buttonStyle(RadManPrimaryButtonStyle())
                        .disabled(primaryRT950Profile == nil)

                        Button {
                            identifyRT950Radio()
                        } label: {
                            Label("Identify Radio", systemImage: "checkmark.shield")
                        }
                        .buttonStyle(RadManSecondaryButtonStyle())
                        .disabled(primaryRT950Profile == nil)

                        Button {
                            refreshSerialPorts()
                        } label: {
                            Label("Refresh Ports", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(RadManSecondaryButtonStyle())

                        Spacer()
                    }
                }

                if let usbStatusMessage {
                    RadManStatusBanner(text: usbStatusMessage, tone: .success)
                }

                HStack(spacing: 14) {
                    RadManMetricCard(
                        title: "Profile",
                        value: primaryRT950Profile?.name.isEmpty == false ? primaryRT950Profile!.name : (primaryRT950Profile?.resolvedModelName ?? "Not configured"),
                        subtitle: primaryRT950Profile?.serialPort.isEmpty == false ? primaryRT950Profile!.serialPort : "No serial port assigned",
                        accent: RadManPalette.teal
                    )
                    RadManMetricCard(
                        title: "Connection",
                        value: usbPreflight.isReady ? "Ready" : "Needs Attention",
                        subtitle: "\(serialPorts.count) serial ports detected",
                        accent: usbPreflight.isReady ? .green : RadManPalette.amber
                    )
                    RadManMetricCard(
                        title: "Snapshot",
                        value: hasStoredClone ? "Available" : "None",
                        subtitle: primaryRT950Profile?.lastNativeCloneCapturedAt?.formatted(date: .abbreviated, time: .shortened) ?? "No live read captured yet",
                        accent: RadManPalette.coral
                    )
                }

                HStack(alignment: .top, spacing: 18) {
                    RadManPanel(title: "1. Cable and Profile", subtitle: "Make sure RadMan knows which RT-950 Pro and serial port to use.") {
                        VStack(alignment: .leading, spacing: 12) {
                            ToolTimeRow(label: "Profile", value: primaryRT950Profile?.name.isEmpty == false ? primaryRT950Profile!.name : (primaryRT950Profile?.resolvedModelName ?? "Not configured"))
                            ToolTimeRow(label: "Configured Port", value: primaryRT950Profile?.serialPort.isEmpty == false ? primaryRT950Profile!.serialPort : "Not set")
                            ToolTimeRow(label: "Detected Ports", value: "\(serialPorts.count)")

                            if serialPorts.isEmpty {
                                Text("No serial ports are visible. Connect the RT-950 Pro cable, power the radio on, then refresh.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(serialPorts) { port in
                                        HStack {
                                            RadManBadge(text: port.name, accent: port.path == primaryRT950Profile?.serialPort ? RadManPalette.teal : RadManPalette.slate)
                                            Text(port.summary)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                        }
                                    }
                                }
                            }

                            HStack(spacing: 12) {
                                Button("Refresh Ports") {
                                    refreshSerialPorts()
                                }
                                .buttonStyle(RadManSecondaryButtonStyle())

                                Button("Use First Detected Port") {
                                    assignFirstDetectedPort()
                                }
                                .buttonStyle(RadManSecondaryButtonStyle())
                                .disabled(primaryRT950Profile == nil || serialPorts.isEmpty)
                            }
                        }
                    }

                    RadManPanel(title: "2. Identify and Read", subtitle: "Confirm the radio model, then pull a live clone into RadMan.") {
                        VStack(alignment: .leading, spacing: 12) {
                            if !usbPreflight.issues.isEmpty {
                                ForEach(usbPreflight.issues, id: \.self) { issue in
                                    RadManStatusBanner(text: issue, tone: .warning)
                                }
                            }

                            HStack(spacing: 12) {
                                Button("Identify RT-950 Pro") {
                                    identifyRT950Radio()
                                }
                                .buttonStyle(RadManSecondaryButtonStyle())
                                .disabled(primaryRT950Profile == nil)

                                Button("Read Radio Into RadMan") {
                                    readRT950IntoRadMan()
                                }
                                .buttonStyle(RadManPrimaryButtonStyle())
                                .disabled(primaryRT950Profile == nil)
                            }

                            if let lastUSBIdentity {
                                DeviceSyncField(label: "Last Model", value: lastUSBIdentity.modelIdentifier)
                                DeviceSyncField(label: "Baud", value: "\(lastUSBIdentity.baudRate)")
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 18) {
                    RadManPanel(title: "3. Save and Review", subtitle: "Capture a backup, import a clone file, and review channels before writing.") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Button("Save Last Clone As…") {
                                    saveStoredClone()
                                }
                                .buttonStyle(RadManSecondaryButtonStyle())
                                .disabled(!hasStoredClone)

                                Button("Import Native Clone File…") {
                                    importCloneFile()
                                }
                                .buttonStyle(RadManSecondaryButtonStyle())
                            }

                            HStack(spacing: 12) {
                                Button(isComparing ? "Comparing..." : "Compare Current Frequencies vs Live Radio") {
                                    compareCurrentFrequenciesWithRadio()
                                }
                                .buttonStyle(RadManPrimaryButtonStyle())
                                .disabled(primaryRT950Profile == nil || store.channels.isEmpty || isComparing)

                                Button("Compare Backup Clone vs Live Radio…") {
                                    compareBackupCloneWithRadio()
                                }
                                .buttonStyle(RadManSecondaryButtonStyle())
                                .disabled(primaryRT950Profile == nil || isComparing)

                                Button("Compare Two Clone Files…") {
                                    compareTwoCloneFiles()
                                }
                                .buttonStyle(RadManSecondaryButtonStyle())
                                .disabled(isComparing)
                            }

                            ForEach(usbPreflight.guidance, id: \.self) { item in
                                Text("• \(item)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    RadManPanel(title: "4. Restore and Recovery", subtitle: "Use this area for full-clone restore work and recovery tasks.") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Write edited frequencies from the Channel Manager, where the current memory list is visible while you program the radio.")
                                .foregroundStyle(.secondary)

                            Button("Restore Full Backup To Radio…") {
                                beginRestoreCloneToRadio()
                            }
                            .buttonStyle(RadManPrimaryButtonStyle())
                            .disabled(primaryRT950Profile == nil)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Selective restore from a native clone")
                                    .font(.headline)

                                HStack(spacing: 12) {
                                    Button("Channels Only…") {
                                        beginRestoreSectionFromClone(.channels)
                                    }
                                    .buttonStyle(RadManSecondaryButtonStyle())
                                    .disabled(primaryRT950Profile == nil || isRestoringSection)

                                    Button("APRS Only…") {
                                        beginRestoreSectionFromClone(.aprs)
                                    }
                                    .buttonStyle(RadManSecondaryButtonStyle())
                                    .disabled(primaryRT950Profile == nil || isRestoringSection)
                                }

                                HStack(spacing: 12) {
                                    Button("Core Settings Only…") {
                                        beginRestoreSectionFromClone(.coreSettings)
                                    }
                                    .buttonStyle(RadManSecondaryButtonStyle())
                                    .disabled(primaryRT950Profile == nil || isRestoringSection)

                                    Button("DTMF Only…") {
                                        beginRestoreSectionFromClone(.dtmf)
                                    }
                                    .buttonStyle(RadManSecondaryButtonStyle())
                                    .disabled(primaryRT950Profile == nil || isRestoringSection)
                                }
                            }

                            Text("Current channel set: \(store.channels.count) memories loaded in RadMan")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                RadManPanel(title: "Status and Compatibility", subtitle: "Useful context while working with a live radio and external files.") {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Time")
                                .font(.headline)
                            ToolTimeRow(label: "Local", value: localFormatter.string(from: now))
                            ToolTimeRow(label: "UTC", value: utcFormatter.string(from: now))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Native Support")
                                .font(.headline)
                            ToolTimeRow(label: "Model", value: standaloneTarget.model.rawValue)
                            ToolTimeRow(label: "Status", value: standaloneTarget.supportLevel.rawValue)
                            ToolTimeRow(label: "Recommended", value: standaloneTarget.recommendedConnection.rawValue)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("File Exchange")
                                .font(.headline)
                            Text("Channel CSV import/export is built in.")
                            Text("Native RT-950 Pro clone backups are also supported directly inside RadMan.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                RadManPanel(title: "Advanced Session Details", subtitle: "Low-level handshake and clone diagnostics for troubleshooting.") {
                    DisclosureGroup("Show transport details", isExpanded: $showAdvancedDetails) {
                        VStack(alignment: .leading, spacing: 10) {
                            if let lastUSBIdentity {
                                DeviceSyncField(label: "Handshake Blob", value: lastUSBIdentity.handshakeBlobHex)
                            }
                            if let lastCloneReport {
                                DeviceSyncField(label: "Clone Bytes", value: "\(lastCloneReport.cloneByteCount)")
                                DeviceSyncField(label: "Clone SHA256", value: lastCloneReport.cloneSHA256)
                                DeviceSyncField(label: "Negotiated XOR", value: lastCloneReport.negotiatedXORKey)
                                DeviceSyncField(label: "Hex Preview", value: lastCloneReport.hexPreview)
                                DeviceSyncField(label: "ASCII Preview", value: lastCloneReport.asciiPreview)
                            }
                        }
                        .padding(.top, 12)
                    }
                }
            }
            .padding(24)
        }
        .onReceive(timer) { newValue in
            now = newValue
        }
        .alert("USB Action Failed", isPresented: Binding(get: { usbErrorMessage != nil }, set: { if !$0 { usbErrorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(usbErrorMessage ?? "")
        }
        .sheet(isPresented: Binding(get: { comparisonReport != nil }, set: { if !$0 { comparisonReport = nil } })) {
            if let comparisonReport {
                RT950ProComparisonSheet(report: comparisonReport)
            }
        }
        .confirmationDialog(
            "Restore Full Backup To Radio?",
            isPresented: Binding(
                get: { pendingFullRestoreURL != nil },
                set: { newValue in
                    if !newValue {
                        pendingFullRestoreURL = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore Backup") {
                if let pendingFullRestoreURL {
                    performRestoreCloneToRadio(from: pendingFullRestoreURL)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("RadMan will save a managed backup from the live radio, then restore \(pendingFullRestoreURL?.lastPathComponent ?? "the selected clone") to the RT-950 Pro.")
        }
        .confirmationDialog(
            "Restore Selected Section To Radio?",
            isPresented: Binding(
                get: { pendingSelectiveRestoreURL != nil && pendingSelectiveRestoreSection != nil },
                set: { newValue in
                    if !newValue {
                        pendingSelectiveRestoreURL = nil
                        pendingSelectiveRestoreSection = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore Section") {
                if let pendingSelectiveRestoreSection, let pendingSelectiveRestoreURL {
                    performRestoreSectionFromClone(pendingSelectiveRestoreSection, sourceURL: pendingSelectiveRestoreURL)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("RadMan will save a managed backup from the live radio, then restore \(pendingSelectiveRestoreSection?.rawValue.lowercased() ?? "the selected section") from \(pendingSelectiveRestoreURL?.lastPathComponent ?? "the chosen clone file").")
        }
    }

    private func refreshSerialPorts() {
        serialPorts = RT950ProUSBService.availablePorts()
        usbStatusMessage = "Refreshed serial ports. \(serialPorts.count) visible."
    }

    private func assignFirstDetectedPort() {
        guard var profile = primaryRT950Profile else { return }
        guard let detectedPort = serialPorts.first(where: \.isLikelyUSBSerial) ?? serialPorts.first else { return }
        profile.serialPort = detectedPort.path
        profile.preferredConnection = .usbCable
        profile.preferNativeWorkflow = true
        store.upsert(profile)
        usbStatusMessage = "Assigned \(detectedPort.path) to \(profile.name.isEmpty ? profile.resolvedModelName : profile.name)."
    }

    private func identifyRT950Radio() {
        guard let profile = primaryRT950Profile else {
            usbErrorMessage = RT950ProUSBServiceError.missingProfile.localizedDescription
            return
        }

        do {
            let report = try RT950ProUSBService.identifyRadio(profile: profile)
            lastUSBIdentity = report
            usbStatusMessage = "Confirmed \(report.modelIdentifier) on \(report.serialPort) at \(report.baudRate) baud."
            usbErrorMessage = nil
        } catch {
            usbErrorMessage = error.localizedDescription
        }
    }

    private func readRT950IntoRadMan() {
        guard let profile = primaryRT950Profile else {
            usbErrorMessage = RT950ProUSBServiceError.missingProfile.localizedDescription
            return
        }

        do {
            let report = try RT950ProUSBService.downloadClone(profile: profile)
            lastUSBIdentity = report.identification
            lastCloneReport = report
            let importedCount = try store.applyRT950CloneReport(report, profile: profile)
            if let cloneData = Data(base64Encoded: report.rawCloneBase64) {
                let profileName = profile.name.isEmpty ? profile.resolvedModelName : profile.name
                let backupURL = try store.saveManagedBackup(cloneData: cloneData, profileName: profileName, label: "live-read")
                usbStatusMessage = "Read \(importedCount) populated channels and a native RT-950 Pro clone into RadMan. Automatic backup saved to \(backupURL.lastPathComponent)."
            } else {
                usbStatusMessage = "Read \(importedCount) populated channels and a native RT-950 Pro clone into RadMan."
            }
            usbErrorMessage = nil
        } catch {
            usbErrorMessage = error.localizedDescription
        }
    }

    private func saveStoredClone() {
        guard let profile = primaryRT950Profile else {
            usbErrorMessage = RT950ProUSBServiceError.missingProfile.localizedDescription
            return
        }

        let defaultName = "RT950Pro-Clone-\(timestampString(from: profile.lastNativeCloneCapturedAt ?? .now)).bin"
        guard let url = AppDialogs.saveRT950CloneImageFile(defaultName: defaultName) else { return }

        do {
            try store.exportRT950CloneImage(to: url, profile: profile)
            usbStatusMessage = "Saved the last native RT-950 Pro clone as \(url.lastPathComponent)."
            usbErrorMessage = nil
        } catch {
            usbErrorMessage = error.localizedDescription
        }
    }

    private func importCloneFile() {
        guard let url = AppDialogs.chooseRT950CloneImageFile() else { return }

        do {
            let importedCount = try store.importRT950CloneImage(from: url, profile: primaryRT950Profile)
            usbStatusMessage = "Imported native clone \(url.lastPathComponent) and decoded \(importedCount) populated channels into RadMan."
            usbErrorMessage = nil
        } catch {
            usbErrorMessage = error.localizedDescription
        }
    }

    private func beginRestoreCloneToRadio() {
        guard primaryRT950Profile != nil else {
            usbErrorMessage = RT950ProUSBServiceError.missingProfile.localizedDescription
            return
        }
        guard let sourceURL = AppDialogs.chooseRT950CloneImageFile() else { return }
        pendingFullRestoreURL = sourceURL
    }

    private func performRestoreCloneToRadio(from sourceURL: URL) {
        guard let profile = primaryRT950Profile else {
            usbErrorMessage = RT950ProUSBServiceError.missingProfile.localizedDescription
            pendingFullRestoreURL = nil
            return
        }
        do {
            let cloneData = try Data(contentsOf: sourceURL)
            let liveBackup = try RT950ProUSBService.downloadClone(profile: profile)
            guard let liveCloneData = Data(base64Encoded: liveBackup.rawCloneBase64) else {
                throw RT950ProUSBServiceError.invalidCloneData
            }

            let profileName = profile.name.isEmpty ? profile.resolvedModelName : profile.name
            let backupURL = try store.saveManagedBackup(cloneData: liveCloneData, profileName: profileName, label: "pre-restore")
            let uploadReport = try RT950ProUSBService.uploadClone(profile: profile, cloneData: cloneData)
            _ = try store.applyRT950CloneData(
                cloneData,
                modelIdentifier: uploadReport.identification.modelIdentifier,
                handshakeBlobHex: uploadReport.identification.handshakeBlobHex,
                capturedAt: .now,
                profile: profile
            )

            usbStatusMessage = "Restored native clone \(sourceURL.lastPathComponent) to the RT-950 Pro. Pre-restore backup saved to \(backupURL.lastPathComponent)."
            usbErrorMessage = nil
        } catch {
            usbErrorMessage = error.localizedDescription
        }
        pendingFullRestoreURL = nil
    }

    private func compareCurrentFrequenciesWithRadio() {
        isComparing = true
        defer { isComparing = false }

        do {
            comparisonReport = try store.previewCurrentChannelPlanAgainstRadio(profile: primaryRT950Profile)
            usbStatusMessage = comparisonReport?.hasChanges == true
                ? "Compared the current RadMan frequency plan against the live radio."
                : "The current RadMan frequency plan already matches the live radio."
            usbErrorMessage = nil
        } catch {
            usbErrorMessage = error.localizedDescription
        }
    }

    private func compareBackupCloneWithRadio() {
        guard let sourceURL = AppDialogs.chooseRT950CloneImageFile() else { return }

        isComparing = true
        defer { isComparing = false }

        do {
            let cloneData = try Data(contentsOf: sourceURL)
            comparisonReport = try store.compareCloneDataWithRadio(cloneData, cloneLabel: sourceURL.lastPathComponent, profile: primaryRT950Profile)
            usbStatusMessage = comparisonReport?.hasChanges == true
                ? "Compared \(sourceURL.lastPathComponent) against the live radio."
                : "\(sourceURL.lastPathComponent) already matches the live radio."
            usbErrorMessage = nil
        } catch {
            usbErrorMessage = error.localizedDescription
        }
    }

    private func compareTwoCloneFiles() {
        guard let firstURL = AppDialogs.chooseRT950CloneImageFile() else { return }
        guard let secondURL = AppDialogs.chooseRT950CloneImageFile() else { return }

        isComparing = true
        defer { isComparing = false }

        do {
            let firstData = try Data(contentsOf: firstURL)
            let secondData = try Data(contentsOf: secondURL)
            comparisonReport = try RT950ProComparisonService.compareCloneData(
                firstData,
                beforeLabel: firstURL.lastPathComponent,
                against: secondData,
                afterLabel: secondURL.lastPathComponent
            )
            usbStatusMessage = comparisonReport?.hasChanges == true
                ? "Compared \(firstURL.lastPathComponent) against \(secondURL.lastPathComponent)."
                : "The selected clone files already match."
            usbErrorMessage = nil
        } catch {
            usbErrorMessage = error.localizedDescription
        }
    }

    private func beginRestoreSectionFromClone(_ section: RT950ProSelectiveRestoreSection) {
        guard primaryRT950Profile != nil else {
            usbErrorMessage = RT950ProUSBServiceError.missingProfile.localizedDescription
            return
        }
        guard let sourceURL = AppDialogs.chooseRT950CloneImageFile() else { return }
        pendingSelectiveRestoreSection = section
        pendingSelectiveRestoreURL = sourceURL
    }

    private func performRestoreSectionFromClone(_ section: RT950ProSelectiveRestoreSection, sourceURL: URL) {
        guard let profile = primaryRT950Profile else {
            usbErrorMessage = RT950ProUSBServiceError.missingProfile.localizedDescription
            pendingSelectiveRestoreSection = nil
            pendingSelectiveRestoreURL = nil
            return
        }
        isRestoringSection = true
        defer { isRestoringSection = false }

        do {
            let cloneData = try Data(contentsOf: sourceURL)
            let backupURL = try store.restoreSectionFromCloneData(section, cloneData: cloneData, profile: profile)
            usbStatusMessage = "Restored \(section.rawValue.lowercased()) from \(sourceURL.lastPathComponent). Backup saved as \(backupURL.lastPathComponent)."
            usbErrorMessage = nil
        } catch {
            usbErrorMessage = error.localizedDescription
        }
        pendingSelectiveRestoreSection = nil
        pendingSelectiveRestoreURL = nil
    }

    private var heroSubtitle: String {
        if let profile = primaryRT950Profile {
            let profileName = profile.name.isEmpty ? profile.resolvedModelName : profile.name
            let port = profile.serialPort.isEmpty ? "no serial port assigned yet" : profile.serialPort
            return "Use this guided workflow to identify, read, back up, and write your \(profileName). RadMan is currently pointed at \(port)."
        }
        return "Set up an RT-950 Pro profile, assign its programming cable, then use the steps below to sync the radio safely."
    }

    private func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

private struct ToolTimeRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.body.monospaced())
        }
    }
}

private struct DeviceSyncField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
