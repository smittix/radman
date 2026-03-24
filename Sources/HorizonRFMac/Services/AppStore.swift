import CryptoKit
import Foundation
import SwiftUI

enum RT950ProSelectiveRestoreSection: String, CaseIterable, Identifiable {
    case channels = "Channels Only"
    case aprs = "APRS Only"
    case coreSettings = "Core Settings Only"
    case dtmf = "DTMF Only"

    var id: String { rawValue }

    var backupLabel: String {
        switch self {
        case .channels:
            return "pre-restore-channels"
        case .aprs:
            return "pre-restore-aprs"
        case .coreSettings:
            return "pre-restore-core-settings"
        case .dtmf:
            return "pre-restore-dtmf"
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    private static let appSupportFolderName = "RadMan"
    private static let legacyAppSupportFolderName = "HorizonRFMac"

    @Published var radios: [RadioProfile] = []
    @Published var contacts: [ContactLog] = []
    @Published var heardRecords: [HeardFrequencyRecord] = []
    @Published var channels: [ChannelMemory] = []

    init() {
        load()
    }

    var storageURL: URL {
        appSupportBaseURL
            .appendingPathComponent(Self.appSupportFolderName, isDirectory: true)
            .appendingPathComponent("store.json", isDirectory: false)
    }

    private var legacyStorageURL: URL {
        appSupportBaseURL
            .appendingPathComponent(Self.legacyAppSupportFolderName, isDirectory: true)
            .appendingPathComponent("store.json", isDirectory: false)
    }

    private var appSupportBaseURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL
    }

    var sortedChannels: [ChannelMemory] {
        channels.sorted {
            if $0.locationSortValue == $1.locationSortValue {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.locationSortValue < $1.locationSortValue
        }
    }

    var sortedContacts: [ContactLog] {
        contacts.sorted { $0.timestamp > $1.timestamp }
    }

    var sortedHeardRecords: [HeardFrequencyRecord] {
        heardRecords.sorted { $0.timestamp > $1.timestamp }
    }

    var sortedRadios: [RadioProfile] {
        radios.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var preferredRT950ProProfile: RadioProfile? {
        sortedRadios.first { $0.builtInModel == .radtelRT950Pro }
    }

    var preferredZoneNames: [String] {
        ChannelPlanService.normalizedZoneNames(preferredRT950ProProfile?.zoneNames ?? [])
    }

    var preferredRT950CPSTemplateName: String? {
        let trimmed = preferredRT950ProProfile?.lastRT950CPSTemplateFileName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var recentContacts: [ContactLog] {
        Array(sortedContacts.prefix(5))
    }

    var recentHeard: [HeardFrequencyRecord] {
        Array(sortedHeardRecords.prefix(5))
    }

    var backupsDirectoryURL: URL {
        storageURL
            .deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
    }

    var channelCapacity: Int {
        ChannelPlanService.maxMemoryCount
    }

    func zoneName(for zone: Int) -> String {
        ChannelPlanService.zoneName(for: zone, customNames: preferredZoneNames)
    }

    func zoneShortLabel(for zone: Int) -> String {
        ChannelPlanService.zoneShortLabel(for: zone, customNames: preferredZoneNames)
    }

    func workAreaDisplayName(for rawValue: String) -> String {
        ChannelPlanService.workAreaDisplayName(for: rawValue, customNames: preferredZoneNames)
    }

    func zoneSummaryLabel(for channel: ChannelMemory) -> String {
        guard
            let zone = ChannelPlanService.zoneValue(for: channel),
            let slot = ChannelPlanService.slotValue(for: channel)
        else {
            return "Zone ?, Slot ?"
        }
        return "\(zoneShortLabel(for: zone)) • S\(slot)"
    }

    func zoneLabel(for channel: ChannelMemory) -> String {
        guard let zone = ChannelPlanService.zoneValue(for: channel) else {
            return "Zone ?"
        }
        return zoneName(for: zone)
    }

    func load() {
        do {
            let fileURL: URL
            if FileManager.default.fileExists(atPath: storageURL.path) {
                fileURL = storageURL
            } else if FileManager.default.fileExists(atPath: legacyStorageURL.path) {
                fileURL = legacyStorageURL
            } else {
                return
            }
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(AppSnapshot.self, from: data)
            let (normalizedChannels, didNormalizeChannels) = Self.normalizeChannelIDs(in: snapshot.channels)
            radios = snapshot.radios
            contacts = snapshot.contacts
            heardRecords = snapshot.heardRecords
            channels = normalizedChannels
            if fileURL == legacyStorageURL || didNormalizeChannels {
                save()
            }
        } catch {
            print("Failed to load app data: \(error.localizedDescription)")
        }
    }

    func save() {
        do {
            let directory = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            let normalizedChannels = Self.normalizeChannelIDs(in: channels).channels
            let snapshot = AppSnapshot(
                radios: radios,
                contacts: contacts,
                heardRecords: heardRecords,
                channels: normalizedChannels
            )
            channels = normalizedChannels
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save app data: \(error.localizedDescription)")
        }
    }

    func upsert(_ radio: RadioProfile) {
        if let index = radios.firstIndex(where: { $0.id == radio.id }) {
            radios[index] = radio
        } else {
            radios.append(radio)
        }
        save()
    }

    func deleteRadios(ids: Set<UUID>) {
        radios.removeAll { ids.contains($0.id) }
        save()
    }

    func upsert(_ contact: ContactLog) throws {
        let contact = try RadManValidationService.normalizeContact(contact)
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[index] = contact
        } else {
            contacts.append(contact)
        }
        save()
    }

    func deleteContacts(ids: Set<UUID>) {
        contacts.removeAll { ids.contains($0.id) }
        save()
    }

    func upsert(_ record: HeardFrequencyRecord) throws {
        let record = try RadManValidationService.normalizeHeardRecord(record)
        if let index = heardRecords.firstIndex(where: { $0.id == record.id }) {
            heardRecords[index] = record
        } else {
            heardRecords.append(record)
        }
        save()
    }

    func deleteHeardRecords(ids: Set<UUID>) {
        heardRecords.removeAll { ids.contains($0.id) }
        save()
    }

    func upsert(_ channel: ChannelMemory) throws {
        channels = try ChannelPlanService.upserting(try RadManValidationService.normalizeChannel(channel), into: channels)
        save()
    }

    func upsert(_ channel: ChannelMemory, overwriteExistingLocation: Bool) throws {
        channels = try ChannelPlanService.upserting(
            try RadManValidationService.normalizeChannel(channel),
            into: channels,
            overwriteExistingLocation: overwriteExistingLocation
        )
        save()
    }

    func deleteChannels(ids: Set<UUID>) {
        channels.removeAll { ids.contains($0.id) }
        save()
    }

    func importChannels(from url: URL) throws -> Int {
        channels = try ChannelPlanService.prepareImportedChannels(
            CHIRPCSVService.importChannels(from: url).map { try RadManValidationService.normalizeChannel($0) }
        )
        save()
        return channels.count
    }

    @discardableResult
    func importRT950CPSZoneNames(from url: URL, profile: RadioProfile? = nil) throws -> RT950ProCPSImportResult {
        let result = try RT950ProCPSService.inspectFile(at: url)
        guard result.hasZoneNames else {
            return result
        }

        var targetProfile = profile ?? preferredRT950ProProfile ?? defaultRT950Profile()
        targetProfile.zoneNames = ChannelPlanService.normalizedZoneNames(result.zoneNames)
        upsert(targetProfile)
        return result
    }

    func updatePreferredZoneNames(_ zoneNames: [String], profile: RadioProfile? = nil) {
        var targetProfile = profile ?? preferredRT950ProProfile ?? defaultRT950Profile()
        targetProfile.zoneNames = ChannelPlanService.normalizedZoneNames(zoneNames)
        upsert(targetProfile)
    }

    func exportChannels(to url: URL) throws {
        try CHIRPCSVService.exportChannels(sortedChannels, to: url)
    }

    @discardableResult
    func importRT950CPSCodeplug(from url: URL, profile: RadioProfile? = nil) throws -> RT950ProCPSImportResult {
        let result = try RT950ProCPSService.importCodeplug(at: url)
        let validatedChannels = try ChannelPlanService.prepareImportedChannels(
            result.importedChannels.map { try RadManValidationService.normalizeChannel($0) }
        )

        var targetProfile = profile ?? preferredRT950ProProfile ?? defaultRT950Profile()
        if result.hasZoneNames {
            targetProfile.zoneNames = ChannelPlanService.normalizedZoneNames(result.zoneNames)
        }
        targetProfile.lastRT950CPSTemplateBase64 = result.templateDataBase64
        targetProfile.lastRT950CPSTemplateFileName = result.fileName

        channels = validatedChannels
        upsert(targetProfile)
        return result
    }

    @discardableResult
    func importRT950ProBackup(from url: URL) throws -> RT950ProBackupImportResult {
        let result = try RT950ProBackupService.importBackup(from: url)
        let validatedChannels = try ChannelPlanService.prepareImportedChannels(
            result.document.channels.map { try RadManValidationService.normalizeChannel($0) }
        )
        channels = validatedChannels

        if let importedProfile = result.document.radioProfile {
            if let index = radios.firstIndex(where: { $0.id == importedProfile.id }) {
                radios[index] = importedProfile
            } else {
                radios.append(importedProfile)
            }
        }

        save()
        return result
    }

    func exportRT950ProBackup(to url: URL, radioProfile: RadioProfile?) throws {
        try RT950ProBackupService.exportBackup(channels: sortedChannels, radioProfile: radioProfile, to: url)
    }

    @discardableResult
    func exportRT950CPSCodeplug(to url: URL, profile: RadioProfile? = nil, templateURL: URL? = nil) throws -> String {
        var targetProfile = profile ?? preferredRT950ProProfile ?? defaultRT950Profile()
        let templateName: String
        let templateData: Data

        if let templateURL {
            templateData = try Data(contentsOf: templateURL)
            templateName = templateURL.lastPathComponent
            targetProfile.lastRT950CPSTemplateBase64 = templateData.base64EncodedString()
            targetProfile.lastRT950CPSTemplateFileName = templateName
            upsert(targetProfile)
        } else if
            let base64 = targetProfile.hasStoredCPSTemplate ? targetProfile.lastRT950CPSTemplateBase64 : nil,
            let data = Data(base64Encoded: base64)
        {
            templateData = data
            templateName = targetProfile.lastRT950CPSTemplateFileName.ifEmpty("Stored Template")
        } else {
            throw RT950ProCPSServiceError.missingTemplate
        }

        try RT950ProCPSService.exportCodeplug(
            channels: sortedChannels,
            zoneNames: ChannelPlanService.normalizedZoneNames(targetProfile.zoneNames),
            to: url,
            templateData: templateData
        )
        return templateName
    }

    @discardableResult
    func applyRT950CloneData(
        _ cloneData: Data,
        modelIdentifier: String = "RT-950",
        handshakeBlobHex: String = "",
        capturedAt: Date = .now,
        profile: RadioProfile? = nil
    ) throws -> Int {
        let decodedChannels = try RT950ProCloneCodec.channels(from: cloneData)
        let sha256 = sha256Hex(for: cloneData)

        var targetProfile = profile ?? preferredRT950ProProfile ?? defaultRT950Profile()
        targetProfile.lastNativeModelIdentifier = modelIdentifier
        targetProfile.lastNativeHandshakeBlobHex = handshakeBlobHex
        targetProfile.lastNativeCloneBase64 = cloneData.base64EncodedString()
        targetProfile.lastNativeCloneSHA256 = sha256
        targetProfile.lastNativeCloneCapturedAt = capturedAt

        channels = ChannelPlanService.sorted(decodedChannels)
        try ChannelPlanService.validate(channels)
        upsert(targetProfile)
        save()
        return decodedChannels.count
    }

    @discardableResult
    func applyRT950CloneReport(_ report: RT950ProUSBCloneReport, profile: RadioProfile? = nil) throws -> Int {
        guard let cloneData = Data(base64Encoded: report.rawCloneBase64) else {
            throw RT950ProUSBServiceError.invalidCloneData
        }

        return try applyRT950CloneData(
            cloneData,
            modelIdentifier: report.identification.modelIdentifier,
            handshakeBlobHex: report.identification.handshakeBlobHex,
            capturedAt: report.identification.startedAt,
            profile: profile
        )
    }

    @discardableResult
    func importRT950CloneImage(from url: URL, profile: RadioProfile? = nil) throws -> Int {
        let data = try Data(contentsOf: url)
        return try applyRT950CloneData(
            data,
            modelIdentifier: "RT-950",
            handshakeBlobHex: "",
            capturedAt: .now,
            profile: profile
        )
    }

    func exportRT950CloneImage(to url: URL, profile: RadioProfile? = nil) throws {
        let targetProfile = profile ?? preferredRT950ProProfile
        guard let base64 = targetProfile?.lastNativeCloneBase64, let data = Data(base64Encoded: base64) else {
            throw RT950ProUSBServiceError.invalidCloneData
        }
        try data.write(to: url, options: .atomic)
    }

    func currentRT950CloneData(profile: RadioProfile? = nil) -> Data? {
        let targetProfile = profile ?? preferredRT950ProProfile
        return targetProfile?.lastNativeCloneBase64.isEmpty == false
            ? Data(base64Encoded: targetProfile!.lastNativeCloneBase64)
            : nil
    }

    func currentRT950CPSTemplateData(profile: RadioProfile? = nil) -> Data? {
        let targetProfile = profile ?? preferredRT950ProProfile
        return targetProfile?.hasStoredCPSTemplate == true
            ? Data(base64Encoded: targetProfile!.lastRT950CPSTemplateBase64)
            : nil
    }

    @discardableResult
    func programCurrentChannelsToRadio(profile: RadioProfile? = nil) throws -> URL {
        let normalizedChannels = try channels.map { try RadManValidationService.normalizeChannel($0) }
        return try programPatchedRT950Clone(backupLabel: "pre-write", profile: profile) { liveCloneData in
            try RT950ProCloneCodec.applyingChannels(normalizedChannels, to: liveCloneData)
        }
    }

    @discardableResult
    func programAPRSToRadio(_ entry: RT950ProAPRSEntry, profile: RadioProfile? = nil) throws -> URL {
        try programPatchedRT950Clone(backupLabel: "pre-aprs", profile: profile) { liveCloneData in
            try RT950ProCloneCodec.applyingAPRS(entry, to: liveCloneData)
        }
    }

    @discardableResult
    func programFunctionSettingsToRadio(_ entry: RT950ProFunctionSettingsEntry, profile: RadioProfile? = nil) throws -> URL {
        try programPatchedRT950Clone(backupLabel: "pre-core-settings", profile: profile) { liveCloneData in
            try RT950ProCloneCodec.applyingFunctionSettings(entry, to: liveCloneData)
        }
    }

    @discardableResult
    func programDTMFToRadio(_ entry: RT950ProDTMFEntry, profile: RadioProfile? = nil) throws -> URL {
        try programPatchedRT950Clone(backupLabel: "pre-dtmf", profile: profile) { liveCloneData in
            try RT950ProCloneCodec.applyingDTMF(entry, to: liveCloneData)
        }
    }

    func previewCurrentChannelPlanAgainstRadio(profile: RadioProfile? = nil) throws -> RT950ProComparisonReport {
        guard let targetProfile = profile ?? preferredRT950ProProfile else {
            throw RT950ProUSBServiceError.missingProfile
        }
        let liveBackup = try RT950ProUSBService.downloadClone(profile: targetProfile)
        guard let liveCloneData = Data(base64Encoded: liveBackup.rawCloneBase64) else {
            throw RT950ProUSBServiceError.invalidCloneData
        }
        return try RT950ProComparisonService.compareLiveRadio(liveCloneData: liveCloneData, againstChannels: sortedChannels)
    }

    func compareCloneDataWithRadio(_ cloneData: Data, cloneLabel: String, profile: RadioProfile? = nil) throws -> RT950ProComparisonReport {
        guard let targetProfile = profile ?? preferredRT950ProProfile else {
            throw RT950ProUSBServiceError.missingProfile
        }
        let liveBackup = try RT950ProUSBService.downloadClone(profile: targetProfile)
        guard let liveCloneData = Data(base64Encoded: liveBackup.rawCloneBase64) else {
            throw RT950ProUSBServiceError.invalidCloneData
        }
        return try RT950ProComparisonService.compareCloneData(
            cloneData,
            beforeLabel: cloneLabel,
            against: liveCloneData,
            afterLabel: "Live Radio"
        )
    }

    @discardableResult
    func restoreSectionFromCloneData(_ section: RT950ProSelectiveRestoreSection, cloneData: Data, profile: RadioProfile? = nil) throws -> URL {
        switch section {
        case .channels:
            return try programPatchedRT950Clone(backupLabel: section.backupLabel, profile: profile) { liveCloneData in
                guard cloneData.count >= RT950ProCloneCodec.channelSectionBytes else {
                    throw RT950ProCloneCodecError.cloneTooSmall(cloneData.count)
                }
                guard liveCloneData.count >= RT950ProCloneCodec.channelSectionBytes else {
                    throw RT950ProCloneCodecError.cloneTooSmall(liveCloneData.count)
                }

                var patchedClone = liveCloneData
                patchedClone.replaceSubrange(0..<RT950ProCloneCodec.channelSectionBytes, with: cloneData.prefix(RT950ProCloneCodec.channelSectionBytes))
                return patchedClone
            }
        case .aprs:
            let entry = try RT950ProCloneCodec.aprsEntry(from: cloneData)
            return try programAPRSToRadio(entry, profile: profile)
        case .coreSettings:
            let entry = try RT950ProCloneCodec.functionSettingsEntry(from: cloneData)
            return try programFunctionSettingsToRadio(entry, profile: profile)
        case .dtmf:
            let entry = try RT950ProCloneCodec.dtmfEntry(from: cloneData)
            return try programDTMFToRadio(entry, profile: profile)
        }
    }

    func saveManagedBackup(cloneData: Data, profileName: String, label: String) throws -> URL {
        try FileManager.default.createDirectory(at: backupsDirectoryURL, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: .now)
        let fileName = "\(profileName.replacingOccurrences(of: " ", with: "-"))-\(label)-\(timestamp).bin"
        let url = backupsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
        try cloneData.write(to: url, options: .atomic)
        return url
    }

    func nextAvailableChannelLocation() -> String? {
        ChannelPlanService.nextAvailableLocation(in: channels).map(String.init)
    }

    func nextAvailableChannelLocation(inZone zone: Int) -> String? {
        ChannelPlanService.nextAvailableLocation(inZone: zone, channels: channels).map(String.init)
    }

    func insertBlankChannel(afterLocation: Int?) throws -> ChannelMemory {
        let result = try ChannelPlanService.insertBlankChannel(into: channels, afterLocation: afterLocation)
        channels = result.channels
        save()
        return result.inserted
    }

    func pasteChannels(_ copiedChannels: [ChannelMemory], afterLocation: Int?) throws -> [ChannelMemory] {
        let result = try ChannelPlanService.pasteChannels(copiedChannels, into: channels, afterLocation: afterLocation)
        channels = result.channels
        save()
        return result.pasted
    }

    private func defaultRT950Profile() -> RadioProfile {
        var profile = RadioProfile()
        profile.name = "RT-950 Pro"
        profile.model = BuiltInRadioModel.radtelRT950Pro.rawValue
        profile.builtInModel = .radtelRT950Pro
        profile.preferredConnection = .usbCable
        profile.preferNativeWorkflow = true
        return profile
    }

    private func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private func programPatchedRT950Clone(
        backupLabel: String,
        profile: RadioProfile? = nil,
        patcher: (Data) throws -> Data
    ) throws -> URL {
        guard let targetProfile = profile ?? preferredRT950ProProfile else {
            throw RT950ProUSBServiceError.missingProfile
        }

        let liveBackup = try RT950ProUSBService.downloadClone(profile: targetProfile)
        guard let liveCloneData = Data(base64Encoded: liveBackup.rawCloneBase64) else {
            throw RT950ProUSBServiceError.invalidCloneData
        }

        let profileName = targetProfile.name.isEmpty ? targetProfile.resolvedModelName : targetProfile.name
        let backupURL = try saveManagedBackup(cloneData: liveCloneData, profileName: profileName, label: backupLabel)
        let patchedClone = try patcher(liveCloneData)
        let uploadReport = try RT950ProUSBService.uploadClone(profile: targetProfile, cloneData: patchedClone)
        _ = try applyRT950CloneData(
            patchedClone,
            modelIdentifier: uploadReport.identification.modelIdentifier,
            handshakeBlobHex: uploadReport.identification.handshakeBlobHex,
            capturedAt: .now,
            profile: targetProfile
        )
        return backupURL
    }

    private static func normalizeChannelIDs(in source: [ChannelMemory]) -> (channels: [ChannelMemory], changed: Bool) {
        var seen = Set<UUID>()
        var changed = false

        let normalized = source.map { original -> ChannelMemory in
            var channel = original
            if seen.contains(channel.id) {
                channel.id = UUID()
                changed = true
            }
            seen.insert(channel.id)
            return channel
        }

        return (normalized, changed)
    }
}
