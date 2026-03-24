import Foundation

enum RadManValidationError: LocalizedError {
    case invalidMHz(String)
    case missingMHz(String)
    case invalidOption(field: String, value: String)

    var errorDescription: String? {
        switch self {
        case let .invalidMHz(value):
            return "Frequency '\(value)' is not a valid MHz value."
        case let .missingMHz(field):
            return "\(field) must be entered in MHz."
        case let .invalidOption(field, value):
            return value.isEmpty
                ? "\(field) cannot be left blank."
                : "\(field) value '\(value)' is not supported by the RT-950 Pro."
        }
    }
}

enum RadManValidationService {
    static let duplexOptions = ["", "+", "-", "split", "off"]
    static let channelModes = ["FM", "NFM", "AM"]
    static let tuningSteps = ["", "2.5", "5.0", "6.25", "8.33", "10.0", "12.5", "25.0"]
    static let powerLevels = ["High", "Medium", "Low"]
    static let scanOptions = ["", "S"]
    static let toneModes = ["", "Tone", "TSQL", "DTCS", "Cross"]
    static let dtcsPolarities = ["NN", "NR", "RN", "RR"]
    static let crossModes = ["", "Tone->Tone", "DTCS->DTCS", "->DTCS", "->Tone", "Tone->DTCS", "DTCS->Tone"]
    static let ctcssTones = [
        "", "67.0", "69.3", "71.9", "74.4", "77.0", "79.7", "82.5", "85.4", "88.5",
        "91.5", "94.8", "97.4", "100.0", "103.5", "107.2", "110.9", "114.8", "118.8", "123.0",
        "127.3", "131.8", "136.5", "141.3", "146.2", "151.4", "156.7", "159.8", "162.2", "165.5",
        "167.9", "171.3", "173.8", "177.3", "179.9", "183.5", "186.2", "189.9", "192.8", "196.6",
        "199.5", "203.5", "206.5", "210.7", "218.1", "225.7", "229.1", "233.6", "241.8", "250.3", "254.1",
    ]
    static let dtcsCodes = [
        "023", "025", "026", "031", "032", "036", "043", "047", "051", "053", "054", "065", "071", "072", "073", "074",
        "114", "115", "116", "122", "125", "131", "132", "134", "143", "145", "152", "155", "156", "162", "165", "172",
        "174", "205", "212", "223", "225", "226", "243", "244", "245", "246", "251", "252", "255", "261", "263", "265",
        "266", "271", "274", "306", "311", "315", "325", "331", "332", "343", "346", "351", "356", "364", "365", "371",
        "411", "412", "413", "423", "431", "432", "445", "446", "452", "454", "455", "462", "464", "465", "466", "503",
        "506", "516", "523", "526", "532", "546", "565", "606", "612", "624", "627", "631", "632", "645", "654", "662",
        "664", "703", "712", "723", "731", "732", "734", "743", "754",
    ]

    static func numericOptions(in range: ClosedRange<Int>, includeUnset: Bool = true) -> [String] {
        let values = range.map(String.init)
        return includeUnset ? [""] + values : values
    }

    static func sanitizeASCII(_ value: String, maxLength: Int, uppercase: Bool = true) -> String {
        let base = uppercase ? value.uppercased() : value
        let scalars = base.unicodeScalars.filter(\.isASCII)
        let ascii = String(String.UnicodeScalarView(scalars))
        return String(ascii.prefix(maxLength))
    }

    static func sanitizeDigits(_ value: String, maxLength: Int? = nil) -> String {
        let digits = value.filter(\.isNumber)
        if let maxLength {
            return String(digits.prefix(maxLength))
        }
        return digits
    }

    static func sanitizeHex(_ value: String, maxLength: Int) -> String {
        let filtered = value.uppercased().filter { "0123456789ABCDEF".contains($0) }
        return String(filtered.prefix(maxLength))
    }

    static func sanitizeDTMF(_ value: String, maxLength: Int) -> String {
        let filtered = value.uppercased().filter { "0123456789ABCD*#".contains($0) }
        return String(filtered.prefix(maxLength))
    }

    static func sanitizeMHzTyping(_ value: String) -> String {
        var hasDecimalPoint = false
        let filtered = value.filter { character in
            if character.isNumber { return true }
            if character == "." && !hasDecimalPoint {
                hasDecimalPoint = true
                return true
            }
            return false
        }

        let parts = filtered.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 2 {
            return String(parts[0]) + "." + String(parts[1].prefix(6))
        }
        return filtered
    }

    static func normalizeMHz(_ value: String) throws -> String {
        let typed = sanitizeMHzTyping(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return "" }
        guard let numeric = Double(typed) else {
            throw RadManValidationError.invalidMHz(value)
        }
        return String(format: "%.6f", numeric)
    }

    static func requireMHz(_ value: String, field: String) throws -> String {
        let normalized = try normalizeMHz(value)
        guard !normalized.isEmpty else {
            throw RadManValidationError.missingMHz(field)
        }
        return normalized
    }

    static func validateOption(
        _ value: String,
        field: String,
        allowed: [String],
        allowEmpty: Bool = true
    ) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard allowEmpty else {
                throw RadManValidationError.invalidOption(field: field, value: "")
            }
            return ""
        }
        guard allowed.contains(trimmed) else {
            throw RadManValidationError.invalidOption(field: field, value: trimmed)
        }
        return trimmed
    }

    static func normalizeChannel(_ channel: ChannelMemory) throws -> ChannelMemory {
        var normalized = channel
        normalized.name = String(normalized.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
        normalized.frequency = try normalizeMHz(normalized.frequency)
        normalized.duplex = try validateOption(normalized.duplex, field: "Duplex", allowed: duplexOptions)
        if normalized.duplex == "+" || normalized.duplex == "-" || normalized.duplex == "split" {
            normalized.offset = try requireMHz(
                normalized.offset,
                field: normalized.duplex == "split" ? "TX frequency" : "Offset"
            )
        } else {
            normalized.offset = try normalizeMHz(normalized.offset)
        }
        normalized.mode = try validateOption(
            normalized.mode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "FM" : normalized.mode,
            field: "Mode",
            allowed: channelModes,
            allowEmpty: false
        )
        normalized.tStep = try validateOption(normalized.tStep, field: "Tuning Step", allowed: tuningSteps)
        normalized.power = try validateOption(normalized.power, field: "Power", allowed: powerLevels)
        normalized.skip = try validateOption(normalized.skip, field: "Scan", allowed: scanOptions)
        normalized.tone = try validateOption(normalized.tone, field: "Tone Mode", allowed: toneModes)
        normalized.rToneFreq = try validateOption(normalized.rToneFreq, field: "TX Tone", allowed: ctcssTones)
        normalized.cToneFreq = try validateOption(normalized.cToneFreq, field: "RX Tone", allowed: ctcssTones)
        normalized.dtcsCode = try validateOption(normalized.dtcsCode, field: "DTCS Code", allowed: [""] + dtcsCodes)
        normalized.dtcsPolarity = try validateOption(
            normalized.dtcsPolarity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "NN" : normalized.dtcsPolarity,
            field: "DTCS Polarity",
            allowed: dtcsPolarities,
            allowEmpty: false
        )
        normalized.rxDtcsCode = try validateOption(normalized.rxDtcsCode, field: "RX DTCS", allowed: [""] + dtcsCodes)
        normalized.crossMode = try validateOption(normalized.crossMode, field: "Cross Mode", allowed: crossModes)
        normalized.nativeSignalGroup = try validateOption(
            normalized.nativeSignalGroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "0" : normalized.nativeSignalGroup,
            field: "Signal Group",
            allowed: numericOptions(in: 0...15, includeUnset: false),
            allowEmpty: false
        )
        normalized.nativePTTID = try validateOption(
            normalized.nativePTTID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "0" : normalized.nativePTTID,
            field: "PTT ID",
            allowed: numericOptions(in: 0...15, includeUnset: false),
            allowEmpty: false
        )
        normalized.nativeScrambler = try validateOption(
            normalized.nativeScrambler.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "0" : normalized.nativeScrambler,
            field: "Scrambler",
            allowed: numericOptions(in: 0...15, includeUnset: false),
            allowEmpty: false
        )
        normalized.nativeEncryption = try validateOption(
            normalized.nativeEncryption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "0" : normalized.nativeEncryption,
            field: "Encryption",
            allowed: numericOptions(in: 0...3, includeUnset: false),
            allowEmpty: false
        )
        normalized.dvcode = sanitizeDigits(normalized.dvcode, maxLength: 3)
        normalized.nativeFHSSCode = sanitizeHex(normalized.nativeFHSSCode, maxLength: 6)
        return normalized
    }

    static func normalizeContact(_ contact: ContactLog) throws -> ContactLog {
        var normalized = contact
        normalized.callsign = sanitizeASCII(normalized.callsign, maxLength: 12)
        normalized.frequency = try normalizeMHz(normalized.frequency)
        return normalized
    }

    static func normalizeHeardRecord(_ record: HeardFrequencyRecord) throws -> HeardFrequencyRecord {
        var normalized = record
        normalized.frequency = try normalizeMHz(normalized.frequency)
        return normalized
    }
}
