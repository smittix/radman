import Foundation

enum CSVCodecError: LocalizedError {
    case malformedQuotedField

    var errorDescription: String? {
        switch self {
        case .malformedQuotedField:
            return "The CSV file contains malformed quoted fields."
        }
    }
}

enum CSVCodec {
    static func parse(_ text: String) throws -> [[String]] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let characters = Array(normalized)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInsideQuotes = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if isInsideQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        isInsideQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    if !field.isEmpty {
                        throw CSVCodecError.malformedQuotedField
                    }
                    isInsideQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default:
                    field.append(character)
                }
            }

            index += 1
        }

        if isInsideQuotes {
            throw CSVCodecError.malformedQuotedField
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }

    static func encode(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { field in
                let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
                    return "\"\(escaped)\""
                }
                return escaped
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }
}
