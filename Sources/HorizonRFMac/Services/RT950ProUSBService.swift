import CryptoKit
import Foundation

struct RT950ProUSBPreflightReport {
    let profileName: String
    let serialPort: String
    let availablePorts: [SerialPortInfo]
    let issues: [String]
    let guidance: [String]

    var isReady: Bool {
        issues.isEmpty
    }
}

struct RT950ProUSBIdentificationReport: Codable, Hashable {
    let targetModel: BuiltInRadioModel
    let profileName: String
    let serialPort: String
    let startedAt: Date
    let baudRate: Int
    let handshakeBlobHex: String
    let modelIdentifier: String
}

struct RT950ProUSBCloneReport: Codable, Hashable {
    let identification: RT950ProUSBIdentificationReport
    let negotiationFrameHex: String
    let negotiatedXORKey: String
    let cloneByteCount: Int
    let cloneSHA256: String
    let rawCloneBase64: String
    let hexPreview: String
    let asciiPreview: String
}

struct RT950ProUSBUploadReport: Hashable {
    let identification: RT950ProUSBIdentificationReport
    let cloneByteCount: Int
    let cloneSHA256: String
}

enum RT950ProUSBServiceError: LocalizedError {
    case missingProfile
    case unsupportedProfile(BuiltInRadioModel)
    case missingSerialPort
    case serialPortUnavailable(String)
    case unexpectedHandshakeAcknowledgement(String)
    case unexpectedEncryptionAcknowledgement(String)
    case invalidModelIdentifier(String)
    case invalidReplyHeader(expected: String, actual: String)
    case invalidNegotiationMaterial
    case invalidCloneData
    case writeAcknowledgementMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .missingProfile:
            return "Create an RT-950 Pro radio profile first."
        case let .unsupportedProfile(model):
            return "The selected profile uses \(model.rawValue), not the RT-950 Pro."
        case .missingSerialPort:
            return "Select a serial port on the RT-950 Pro profile first."
        case let .serialPortUnavailable(path):
            return "The configured serial port \(path) is not currently available."
        case let .unexpectedHandshakeAcknowledgement(actual):
            return "The RT-950 Pro did not acknowledge the native handshake. Received \(actual)."
        case let .unexpectedEncryptionAcknowledgement(actual):
            return "The RT-950 Pro rejected the encryption negotiation. Received \(actual)."
        case let .invalidModelIdentifier(identifier):
            return "The radio reported an unexpected model identifier: \(identifier)."
        case let .invalidReplyHeader(expected, actual):
            return "The RT-950 Pro returned an unexpected block header. Expected \(expected), received \(actual)."
        case .invalidNegotiationMaterial:
            return "The RT-950 Pro negotiation frame could not be built."
        case .invalidCloneData:
            return "The RT-950 Pro clone data could not be decoded."
        case let .writeAcknowledgementMismatch(expected, actual):
            return "The RT-950 Pro did not acknowledge a write block. Expected \(expected), received \(actual)."
        }
    }
}

struct RT950ProCloneSegment: Hashable {
    let readCommand: UInt8
    let writeCommand: UInt8
    let start: UInt16
    let length: Int
}

enum RT950ProUSBService {
    static let defaultBaudRate = 115200
    static let blockSize = 0x80
    static let handshakeString = Data("PROGRAMBT9000U".utf8)
    static let handshakeAcknowledge = Data([0x06])
    static let probeCommand = Data([0x46])
    static let modelCommand = Data([0x4D])
    static let endCommand = Data([0x45])
    static let encryptionStrings = [
        "BHT ",
        "CO 7",
        "A ES",
        " EIY",
        "M PQ",
        "XN Y",
        "RVB ",
        " HQP",
        "W RC",
        "MS N",
        " SAT",
        "K DH",
        "ZO R",
        "C SL",
        "6RB ",
        " JCG",
        "PN V",
        "J PK",
        "EK L",
        "I LZ",
    ]
    static let defaultSegments = [
        RT950ProCloneSegment(readCommand: 0x52, writeCommand: 0x57, start: 0x0000, length: 0x7800),
        RT950ProCloneSegment(readCommand: 0x52, writeCommand: 0x57, start: 0x8000, length: 0x0100),
        RT950ProCloneSegment(readCommand: 0x52, writeCommand: 0x57, start: 0x9000, length: 0x0100),
        RT950ProCloneSegment(readCommand: 0x52, writeCommand: 0x57, start: 0xA000, length: 0x0200),
        RT950ProCloneSegment(readCommand: 0x52, writeCommand: 0x57, start: 0xB000, length: 0x0200),
        RT950ProCloneSegment(readCommand: 0x52, writeCommand: 0x57, start: 0xD000, length: 0x0300),
        RT950ProCloneSegment(readCommand: 0x54, writeCommand: 0x55, start: 0x0000, length: 0x0080),
    ]
    static let expectedCloneByteCount = defaultSegments.reduce(0) { $0 + $1.length }

    static func availablePorts() -> [SerialPortInfo] {
        SerialPortService.candidatePorts()
    }

    static func preflight(profile: RadioProfile?, availablePorts: [SerialPortInfo] = availablePorts()) -> RT950ProUSBPreflightReport {
        let trimmedName = profile?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileName = (trimmedName?.isEmpty == false) ? trimmedName! : "RT-950 Pro"
        let serialPort = profile?.serialPort ?? ""
        var issues: [String] = []
        var guidance: [String] = [
            "Use the official RT-950 / RT-950 Pro programming cable for the most reliable native workflow.",
            "Connect the radio before launching a live USB download attempt.",
            "Keep a RadMan RT-950 Pro backup before experimenting with a new radio session.",
        ]

        guard let profile else {
            issues.append("No RT-950 Pro profile is configured yet.")
            guidance.append("Create a radio profile and set it to Radtel RT-950 Pro.")
            return RT950ProUSBPreflightReport(profileName: profileName, serialPort: serialPort, availablePorts: availablePorts, issues: issues, guidance: guidance)
        }

        if profile.builtInModel != .radtelRT950Pro {
            issues.append("The selected profile is \(profile.builtInModel.rawValue), not Radtel RT-950 Pro.")
        }

        if serialPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("No serial port is configured on the RT-950 Pro profile.")
            if let suggestedPort = availablePorts.first(where: \.isLikelyUSBSerial)?.path ?? availablePorts.first?.path {
                guidance.append("Assign the detected port \(suggestedPort) to the RT-950 Pro profile.")
            }
        } else if !availablePorts.contains(where: { $0.path == serialPort }) {
            issues.append("The configured serial port is not currently visible on this Mac.")
            if availablePorts.isEmpty {
                guidance.append("No serial ports are visible right now. Connect the cable and power the radio on.")
            } else if let suggestedPort = availablePorts.first(where: \.isLikelyUSBSerial)?.path ?? availablePorts.first?.path {
                guidance.append("The closest visible candidate is \(suggestedPort).")
            }
        }

        if availablePorts.isEmpty {
            issues.append("No candidate serial ports are currently available.")
        }

        guidance.append("When we implement the full RT-950 Pro download protocol, this same profile/port setup will be reused.")
        return RT950ProUSBPreflightReport(profileName: profileName, serialPort: serialPort, availablePorts: availablePorts, issues: issues, guidance: guidance)
    }

    static func identifyRadio(profile: RadioProfile) throws -> RT950ProUSBIdentificationReport {
        guard profile.builtInModel == .radtelRT950Pro else {
            throw RT950ProUSBServiceError.unsupportedProfile(profile.builtInModel)
        }

        let serialPort = profile.serialPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serialPort.isEmpty else {
            throw RT950ProUSBServiceError.missingSerialPort
        }
        guard SerialPortService.portExists(serialPort) else {
            throw RT950ProUSBServiceError.serialPortUnavailable(serialPort)
        }

        return try SerialPortService.withConnection(path: serialPort, baudRate: defaultBaudRate) { connection in
            try identifyRadio(
                using: connection,
                profileName: resolvedProfileName(profile),
                serialPort: serialPort,
                baudRate: defaultBaudRate
            )
        }
    }

    static func identifyRadio(
        using connection: any SerialPortConnection,
        profileName: String,
        serialPort: String,
        baudRate: Int = defaultBaudRate
    ) throws -> RT950ProUSBIdentificationReport {
        try connection.flushIO()
        try connection.write(handshakeString)

        let acknowledgement = try connection.readExact(count: 1, timeout: 2.0)
        guard acknowledgement == handshakeAcknowledge else {
            throw RT950ProUSBServiceError.unexpectedHandshakeAcknowledgement(acknowledgement.hexString())
        }

        try connection.write(probeCommand)
        let probeBlob = try connection.readExact(count: 16, timeout: 2.0)

        try connection.write(modelCommand)
        let rawModel = try connection.readExact(count: 12, timeout: 2.0)
        let modelIdentifier = decodeASCII(rawModel)

        guard modelIdentifier.localizedCaseInsensitiveContains("RT-950") else {
            throw RT950ProUSBServiceError.invalidModelIdentifier(modelIdentifier)
        }

        return RT950ProUSBIdentificationReport(
            targetModel: .radtelRT950Pro,
            profileName: profileName,
            serialPort: serialPort,
            startedAt: Date(),
            baudRate: baudRate,
            handshakeBlobHex: probeBlob.hexString(),
            modelIdentifier: modelIdentifier
        )
    }

    static func downloadClone(profile: RadioProfile) throws -> RT950ProUSBCloneReport {
        guard profile.builtInModel == .radtelRT950Pro else {
            throw RT950ProUSBServiceError.unsupportedProfile(profile.builtInModel)
        }

        let serialPort = profile.serialPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serialPort.isEmpty else {
            throw RT950ProUSBServiceError.missingSerialPort
        }
        guard SerialPortService.portExists(serialPort) else {
            throw RT950ProUSBServiceError.serialPortUnavailable(serialPort)
        }

        return try SerialPortService.withConnection(path: serialPort, baudRate: defaultBaudRate) { connection in
            try downloadClone(
                using: connection,
                profileName: resolvedProfileName(profile),
                serialPort: serialPort,
                baudRate: defaultBaudRate
            )
        }
    }

    static func downloadClone(
        using connection: any SerialPortConnection,
        profileName: String,
        serialPort: String,
        baudRate: Int = defaultBaudRate,
        segments: [RT950ProCloneSegment] = defaultSegments,
        negotiationByte: UInt8? = nil,
        negotiationMaterial: [UInt8]? = nil
    ) throws -> RT950ProUSBCloneReport {
        let identification = try identifyRadio(
            using: connection,
            profileName: profileName,
            serialPort: serialPort,
            baudRate: baudRate
        )

        let (frame, key) = try buildEncryptionFrame(
            negotiationByte: negotiationByte,
            negotiationMaterial: negotiationMaterial
        )

        try connection.write(frame)
        let encryptionAcknowledgement = try connection.readExact(count: 1, timeout: 2.0)
        guard encryptionAcknowledgement == handshakeAcknowledge else {
            throw RT950ProUSBServiceError.unexpectedEncryptionAcknowledgement(encryptionAcknowledgement.hexString())
        }

        var cloneData = Data()

        for segment in segments {
            for offset in stride(from: 0, to: segment.length, by: blockSize) {
                let address = Int(segment.start) + offset
                let header = Data([
                    segment.readCommand,
                    UInt8((address >> 8) & 0xFF),
                    UInt8(address & 0xFF),
                    UInt8(blockSize),
                ])

                try connection.write(header)
                let reply = try connection.readExact(count: 4 + blockSize, timeout: 3.0)
                let actualHeader = reply.prefix(4)
                guard actualHeader == header else {
                    throw RT950ProUSBServiceError.invalidReplyHeader(
                        expected: header.hexString(),
                        actual: Data(actualHeader).hexString()
                    )
                }

                let encryptedPayload = Data(reply.dropFirst(4))
                cloneData.append(xorTransform(payload: encryptedPayload, key: key))
            }
        }

        try connection.write(endCommand)

        guard !cloneData.isEmpty else {
            throw RT950ProUSBServiceError.invalidCloneData
        }

        let digest = SHA256.hash(data: cloneData)
        let sha256 = digest.map { String(format: "%02x", $0) }.joined()

        return RT950ProUSBCloneReport(
            identification: identification,
            negotiationFrameHex: frame.hexString(),
            negotiatedXORKey: key,
            cloneByteCount: cloneData.count,
            cloneSHA256: sha256,
            rawCloneBase64: cloneData.base64EncodedString(),
            hexPreview: hexPreview(for: cloneData),
            asciiPreview: asciiPreview(for: cloneData)
        )
    }

    static func writeCloneReport(_ report: RT950ProUSBCloneReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
    }

    static func writeCloneImage(_ report: RT950ProUSBCloneReport, to url: URL) throws {
        guard let data = Data(base64Encoded: report.rawCloneBase64) else {
            throw RT950ProUSBServiceError.invalidCloneData
        }
        try data.write(to: url, options: .atomic)
    }

    static func uploadClone(profile: RadioProfile, cloneData: Data) throws -> RT950ProUSBUploadReport {
        try uploadClone(profile: profile, cloneData: cloneData, segments: defaultSegments)
    }

    static func uploadClone(
        profile: RadioProfile,
        cloneData: Data,
        segments: [RT950ProCloneSegment]
    ) throws -> RT950ProUSBUploadReport {
        guard profile.builtInModel == .radtelRT950Pro else {
            throw RT950ProUSBServiceError.unsupportedProfile(profile.builtInModel)
        }

        let serialPort = profile.serialPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serialPort.isEmpty else {
            throw RT950ProUSBServiceError.missingSerialPort
        }
        guard SerialPortService.portExists(serialPort) else {
            throw RT950ProUSBServiceError.serialPortUnavailable(serialPort)
        }

        return try SerialPortService.withConnection(path: serialPort, baudRate: defaultBaudRate) { connection in
            try uploadClone(
                using: connection,
                cloneData: cloneData,
                profileName: resolvedProfileName(profile),
                serialPort: serialPort,
                baudRate: defaultBaudRate,
                segments: segments
            )
        }
    }

    static func uploadClone(
        using connection: any SerialPortConnection,
        cloneData: Data,
        profileName: String,
        serialPort: String,
        baudRate: Int = defaultBaudRate,
        segments: [RT950ProCloneSegment] = defaultSegments,
        negotiationByte: UInt8? = nil,
        negotiationMaterial: [UInt8]? = nil
    ) throws -> RT950ProUSBUploadReport {
        let expectedLength = segments.reduce(0) { $0 + $1.length }
        guard cloneData.count == expectedLength else {
            throw RT950ProUSBServiceError.invalidCloneData
        }

        let identification = try identifyRadio(
            using: connection,
            profileName: profileName,
            serialPort: serialPort,
            baudRate: baudRate
        )

        let (frame, key) = try buildEncryptionFrame(
            negotiationByte: negotiationByte,
            negotiationMaterial: negotiationMaterial
        )

        try connection.write(frame)
        let encryptionAcknowledgement = try connection.readExact(count: 1, timeout: 2.0)
        guard encryptionAcknowledgement == handshakeAcknowledge else {
            throw RT950ProUSBServiceError.unexpectedEncryptionAcknowledgement(encryptionAcknowledgement.hexString())
        }

        var cursor = 0
        for segment in segments {
            for offset in stride(from: 0, to: segment.length, by: blockSize) {
                let address = Int(segment.start) + offset
                let header = Data([
                    segment.writeCommand,
                    UInt8((address >> 8) & 0xFF),
                    UInt8(address & 0xFF),
                    UInt8(blockSize),
                ])

                let chunk = Data(cloneData[cursor..<(cursor + blockSize)])
                cursor += blockSize
                let payload = xorTransform(payload: chunk, key: key)
                try connection.write(header + payload)

                let acknowledgement = try connection.readExact(count: 1, timeout: 2.0)
                guard acknowledgement == handshakeAcknowledge else {
                    throw RT950ProUSBServiceError.writeAcknowledgementMismatch(
                        expected: handshakeAcknowledge.hexString(),
                        actual: acknowledgement.hexString()
                    )
                }
            }
        }

        try connection.write(endCommand)

        let digest = SHA256.hash(data: cloneData)
        let sha256 = digest.map { String(format: "%02x", $0) }.joined()
        return RT950ProUSBUploadReport(
            identification: identification,
            cloneByteCount: cloneData.count,
            cloneSHA256: sha256
        )
    }

    static func buildEncryptionFrame(
        negotiationByte: UInt8? = nil,
        negotiationMaterial: [UInt8]? = nil
    ) throws -> (frame: Data, key: String) {
        let code = negotiationByte ?? UInt8((Int.random(in: 1...2) << 4) | Int.random(in: 0...4))
        let material = negotiationMaterial ?? (0..<19).map { _ in UInt8(Int.random(in: 0..<encryptionStrings.count)) }

        guard material.count == 19 else {
            throw RT950ProUSBServiceError.invalidNegotiationMaterial
        }

        var frame = Data(repeating: 0, count: 25)
        frame.replaceSubrange(0..<4, with: Data("SEND".utf8))
        frame[4] = code
        for (index, value) in material.enumerated() {
            frame[5 + index] = value
        }

        let selectionIndex: Int
        if code & 0x20 != 0 {
            selectionIndex = Int(code - 0x20) * 2 + 1
        } else {
            selectionIndex = Int(code - 0x10) * 2
        }
        let keyLookupIndex = selectionIndex + 1
        guard (5..<frame.count).contains(4 + keyLookupIndex) else {
            throw RT950ProUSBServiceError.invalidNegotiationMaterial
        }

        let symbolIndex = Int(frame[4 + keyLookupIndex])
        guard encryptionStrings.indices.contains(symbolIndex) else {
            throw RT950ProUSBServiceError.invalidNegotiationMaterial
        }

        return (frame, encryptionStrings[symbolIndex])
    }

    static func xorTransform(payload: Data, key: String) -> Data {
        let keyBytes = Array(key.utf8)
        guard !keyBytes.isEmpty else { return payload }

        var output = Array(payload)
        var keyIndex = 0

        for index in output.indices {
            let value = output[index]
            let keyByte = keyBytes[keyIndex]
            keyIndex = (keyIndex + 1) % keyBytes.count

            if keyByte != 0x20 && value != 0x00 && value != 0xFF && value != keyByte && value != (keyByte ^ 0xFF) {
                output[index] = value ^ keyByte
            }
        }

        return Data(output)
    }

    private static func hexPreview(for data: Data, limit: Int = 64) -> String {
        guard !data.isEmpty else { return "No bytes captured." }
        return data.prefix(limit).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func asciiPreview(for data: Data, limit: Int = 64) -> String {
        guard !data.isEmpty else { return "No bytes captured." }
        let scalars = data.prefix(limit).map { byte -> Character in
            if (32...126).contains(byte) {
                return Character(UnicodeScalar(byte))
            }
            return "."
        }
        return String(scalars)
    }

    private static func resolvedProfileName(_ profile: RadioProfile) -> String {
        profile.name.isEmpty ? profile.resolvedModelName : profile.name
    }

    private static func decodeASCII(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ").union(.whitespacesAndNewlines))
    }
}

private extension Data {
    func hexString() -> String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
