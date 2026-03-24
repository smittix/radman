import Foundation

enum CHIRPCSVServiceError: LocalizedError {
    case emptyFile
    case missingHeaders([String])
    case noChannelRows

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The selected CSV file is empty."
        case let .missingHeaders(headers):
            return "The CSV file is missing required channel fields: \(headers.joined(separator: ", "))"
        case .noChannelRows:
            return "The selected CSV file did not contain any channel rows."
        }
    }
}

enum CHIRPCSVService {
    static func importChannels(from url: URL) throws -> [ChannelMemory] {
        let text = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\u{feff}", with: "")
        let rows = try CSVCodec.parse(text)
        guard let headerRow = rows.first else {
            throw CHIRPCSVServiceError.emptyFile
        }

        let headers = headerRow.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let missingHeaders = ChannelMemory.requiredImportHeaders.filter { !headers.contains($0) }
        if !missingHeaders.isEmpty {
            throw CHIRPCSVServiceError.missingHeaders(missingHeaders)
        }

        var channels: [ChannelMemory] = []
        for row in rows.dropFirst() {
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }

            var mappedRow: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                mappedRow[header] = index < row.count ? row[index] : ""
            }
            channels.append(ChannelMemory(row: mappedRow))
        }

        if channels.isEmpty {
            throw CHIRPCSVServiceError.noChannelRows
        }

        return channels
    }

    static func exportChannels(_ channels: [ChannelMemory], to url: URL) throws {
        let rows = [ChannelMemory.csvHeaders] + channels.map(\.csvRow)
        let text = CSVCodec.encode(rows)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
