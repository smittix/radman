import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case device = "Device"
    case channels = "Channels"
    case radios = "Radios"
    case tools = "Tools"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard:
            return "rectangle.grid.2x2"
        case .device:
            return "memorychip"
        case .channels:
            return "waveform.path.ecg.rectangle"
        case .radios:
            return "antenna.radiowaves.left.and.right"
        case .tools:
            return "wrench.and.screwdriver"
        }
    }
}

struct AppSnapshot: Codable {
    var radios: [RadioProfile] = []
    var contacts: [ContactLog] = []
    var heardRecords: [HeardFrequencyRecord] = []
    var channels: [ChannelMemory] = []
}

struct RadioProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String = ""
    var model: String = BuiltInRadioModel.radtelRT950Pro.rawValue
    var builtInModel: BuiltInRadioModel = .radtelRT950Pro
    var preferredConnection: RadioConnectionKind = .usbCable
    var preferNativeWorkflow: Bool = true
    var chirpID: String = ""
    var serialPort: String = ""
    var notes: String = ""
    var lastNativeModelIdentifier: String = ""
    var lastNativeHandshakeBlobHex: String = ""
    var lastNativeCloneBase64: String = ""
    var lastNativeCloneSHA256: String = ""
    var lastNativeCloneCapturedAt: Date?
    var zoneNames: [String] = []
    var lastRT950CPSTemplateBase64: String = ""
    var lastRT950CPSTemplateFileName: String = ""

    init() {}

    var definition: RadioDefinition {
        RadioCatalog.definition(for: builtInModel)
    }

    var resolvedModelName: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? builtInModel.rawValue : trimmed
    }

    var hasStoredCPSTemplate: Bool {
        !lastRT950CPSTemplateBase64.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        let decodedModel = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        let decodedCHIRPID = try container.decodeIfPresent(String.self, forKey: .chirpID) ?? ""
        let decodedSerialPort = try container.decodeIfPresent(String.self, forKey: .serialPort) ?? ""
        let decodedNotes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        let inferredModel = Self.inferBuiltInModel(model: decodedModel, chirpID: decodedCHIRPID)

        id = decodedID
        name = decodedName
        model = decodedModel.isEmpty ? inferredModel.rawValue : decodedModel
        builtInModel = try container.decodeIfPresent(BuiltInRadioModel.self, forKey: .builtInModel) ?? inferredModel
        preferredConnection = try container.decodeIfPresent(RadioConnectionKind.self, forKey: .preferredConnection) ?? definition.recommendedConnection
        preferNativeWorkflow = try container.decodeIfPresent(Bool.self, forKey: .preferNativeWorkflow) ?? true
        chirpID = decodedCHIRPID
        serialPort = decodedSerialPort
        notes = decodedNotes
        lastNativeModelIdentifier = try container.decodeIfPresent(String.self, forKey: .lastNativeModelIdentifier) ?? ""
        lastNativeHandshakeBlobHex = try container.decodeIfPresent(String.self, forKey: .lastNativeHandshakeBlobHex) ?? ""
        lastNativeCloneBase64 = try container.decodeIfPresent(String.self, forKey: .lastNativeCloneBase64) ?? ""
        lastNativeCloneSHA256 = try container.decodeIfPresent(String.self, forKey: .lastNativeCloneSHA256) ?? ""
        lastNativeCloneCapturedAt = try container.decodeIfPresent(Date.self, forKey: .lastNativeCloneCapturedAt)
        zoneNames = try container.decodeIfPresent([String].self, forKey: .zoneNames) ?? []
        lastRT950CPSTemplateBase64 = try container.decodeIfPresent(String.self, forKey: .lastRT950CPSTemplateBase64) ?? ""
        lastRT950CPSTemplateFileName = try container.decodeIfPresent(String.self, forKey: .lastRT950CPSTemplateFileName) ?? ""
    }

    private static func inferBuiltInModel(model: String, chirpID: String) -> BuiltInRadioModel {
        let haystack = "\(model) \(chirpID)".lowercased()
        if haystack.contains("950") {
            return .radtelRT950Pro
        }
        return .genericCSVInterop
    }
}

struct ContactLog: Identifiable, Codable, Hashable {
    var id = UUID()
    var callsign: String = ""
    var operatorName: String = ""
    var frequency: String = ""
    var mode: String = ""
    var radioName: String = ""
    var location: String = ""
    var signalSent: String = ""
    var signalReceived: String = ""
    var notes: String = ""
    var timestamp: Date = .now
}

struct HeardFrequencyRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var frequency: String = ""
    var mode: String = ""
    var radioName: String = ""
    var source: String = ""
    var signalReport: String = ""
    var location: String = ""
    var notes: String = ""
    var timestamp: Date = .now
}

struct ChannelMemory: Identifiable, Codable, Hashable {
    static let requiredImportHeaders = [
        "Frequency",
    ]

    static let csvHeaders = [
        "Location",
        "Name",
        "Frequency",
        "Duplex",
        "Offset",
        "Tone",
        "rToneFreq",
        "cToneFreq",
        "DtcsCode",
        "DtcsPolarity",
        "RxDtcsCode",
        "CrossMode",
        "Mode",
        "TStep",
        "Skip",
        "Power",
        "Comment",
        "URCALL",
        "RPT1CALL",
        "RPT2CALL",
        "DVCODE",
    ]

    var id = UUID()
    var location: String = ""
    var name: String = ""
    var frequency: String = ""
    var duplex: String = ""
    var offset: String = ""
    var tone: String = ""
    var rToneFreq: String = ""
    var cToneFreq: String = ""
    var dtcsCode: String = ""
    var dtcsPolarity: String = ""
    var rxDtcsCode: String = ""
    var crossMode: String = ""
    var mode: String = ""
    var tStep: String = ""
    var skip: String = ""
    var power: String = ""
    var comment: String = ""
    var urcall: String = ""
    var rpt1call: String = ""
    var rpt2call: String = ""
    var dvcode: String = ""
    var nativeSignalGroup: String = ""
    var nativePTTID: String = ""
    var nativeBusyLockout: Bool = false
    var nativeScrambler: String = ""
    var nativeEncryption: String = ""
    var nativeLearnFHSS: Bool = false
    var nativeFHSSCode: String = ""

    static var empty: ChannelMemory {
        ChannelMemory()
    }

    init() {}

    init(row: [String: String]) {
        location = row["Location", default: ""]
        name = row["Name", default: ""]
        frequency = row["Frequency", default: ""]
        duplex = row["Duplex", default: ""]
        offset = row["Offset", default: ""]
        tone = row["Tone", default: ""]
        rToneFreq = row["rToneFreq", default: ""]
        cToneFreq = row["cToneFreq", default: ""]
        dtcsCode = row["DtcsCode", default: ""]
        dtcsPolarity = row["DtcsPolarity", default: ""]
        rxDtcsCode = row["RxDtcsCode", default: ""]
        crossMode = row["CrossMode", default: ""]
        mode = row["Mode", default: ""]
        tStep = row["TStep", default: ""]
        skip = row["Skip", default: ""]
        power = row["Power", default: ""]
        comment = row["Comment", default: ""]
        urcall = row["URCALL", default: ""]
        rpt1call = row["RPT1CALL", default: ""]
        rpt2call = row["RPT2CALL", default: ""]
        dvcode = row["DVCODE", default: ""]
    }

    var isEffectivelyEmpty: Bool {
        frequency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var csvRow: [String] {
        [
            location,
            name,
            frequency,
            duplex,
            offset,
            tone,
            rToneFreq,
            cToneFreq,
            dtcsCode,
            dtcsPolarity,
            rxDtcsCode,
            crossMode,
            mode,
            tStep,
            skip,
            power,
            comment,
            urcall,
            rpt1call,
            rpt2call,
            dvcode,
        ]
    }

    var locationSortValue: Int {
        Int(location) ?? Int.max
    }
}
