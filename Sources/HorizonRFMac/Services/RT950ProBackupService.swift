import Foundation

enum RT950ProBackupServiceError: LocalizedError {
    case invalidFormat
    case unsupportedTargetModel(BuiltInRadioModel)
    case noChannels
    case unsupportedProfileModel(BuiltInRadioModel)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "The selected file is not a RadMan RT-950 Pro backup."
        case let .unsupportedTargetModel(model):
            return "This backup targets \(model.rawValue), not the RT-950 Pro."
        case .noChannels:
            return "No channels are available in this RT-950 Pro backup."
        case let .unsupportedProfileModel(model):
            return "The selected radio profile uses \(model.rawValue), which is not supported by the RT-950 Pro backup workflow."
        }
    }
}

struct RT950ProBackupDocument: Codable {
    static let formatIdentifier = "com.radman.rt950pro.backup"
    static let legacyFormatIdentifier = "com.horizonrf.rt950pro.backup"
    static let currentVersion = 1

    var format: String = formatIdentifier
    var version: Int = currentVersion
    var targetModel: BuiltInRadioModel = .radtelRT950Pro
    var exportedAt: Date = .now
    var exportedBy: String = "RadMan"
    var schemaFields: [String] = ChannelMemory.csvHeaders
    var radioProfile: RadioProfile?
    var channels: [ChannelMemory]

    init(
        format: String = formatIdentifier,
        version: Int = currentVersion,
        targetModel: BuiltInRadioModel = .radtelRT950Pro,
        exportedAt: Date = .now,
        exportedBy: String = "RadMan",
        schemaFields: [String] = ChannelMemory.csvHeaders,
        radioProfile: RadioProfile? = nil,
        channels: [ChannelMemory]
    ) {
        self.format = format
        self.version = version
        self.targetModel = targetModel
        self.exportedAt = exportedAt
        self.exportedBy = exportedBy
        self.schemaFields = schemaFields
        self.radioProfile = radioProfile
        self.channels = channels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? ""
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        targetModel = try container.decodeIfPresent(BuiltInRadioModel.self, forKey: .targetModel) ?? .radtelRT950Pro
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .distantPast
        exportedBy = try container.decodeIfPresent(String.self, forKey: .exportedBy) ?? "Unknown"
        schemaFields = try container.decodeIfPresent([String].self, forKey: .schemaFields) ?? ChannelMemory.csvHeaders
        radioProfile = try container.decodeIfPresent(RadioProfile.self, forKey: .radioProfile)
        channels = try container.decodeIfPresent([ChannelMemory].self, forKey: .channels) ?? []
    }
}

struct RT950ProBackupImportResult {
    let document: RT950ProBackupDocument

    var channelCount: Int {
        document.channels.count
    }

    var embeddedProfileName: String? {
        document.radioProfile?.name
    }
}

enum RT950ProBackupService {
    static func importBackup(from url: URL) throws -> RT950ProBackupImportResult {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(RT950ProBackupDocument.self, from: data)

        guard [RT950ProBackupDocument.formatIdentifier, RT950ProBackupDocument.legacyFormatIdentifier].contains(document.format) else {
            throw RT950ProBackupServiceError.invalidFormat
        }
        guard document.targetModel == .radtelRT950Pro else {
            throw RT950ProBackupServiceError.unsupportedTargetModel(document.targetModel)
        }
        guard !document.channels.isEmpty else {
            throw RT950ProBackupServiceError.noChannels
        }

        return RT950ProBackupImportResult(document: document)
    }

    static func exportBackup(channels: [ChannelMemory], radioProfile: RadioProfile?, to url: URL) throws {
        guard !channels.isEmpty else {
            throw RT950ProBackupServiceError.noChannels
        }
        if let radioProfile, radioProfile.builtInModel != .radtelRT950Pro {
            throw RT950ProBackupServiceError.unsupportedProfileModel(radioProfile.builtInModel)
        }

        let document = RT950ProBackupDocument(
            radioProfile: radioProfile,
            channels: channels
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
    }
}
