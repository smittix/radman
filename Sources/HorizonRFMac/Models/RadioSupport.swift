import Foundation

enum BuiltInRadioModel: String, Codable, CaseIterable, Identifiable, Hashable {
    case radtelRT950Pro = "Radtel RT-950 Pro"
    case genericCSVInterop = "Generic CSV / File Interop"

    var id: String { rawValue }
}

enum RadioConnectionKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case usbCable = "USB Cable"
    case bluetooth = "Bluetooth"
    case csvFile = "CSV / Backup File"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .usbCable:
            return "Best path for direct macOS programming."
        case .bluetooth:
            return "Possible later, but usually more reverse-engineering work."
        case .csvFile:
            return "Best for offline interop and migration."
        }
    }
}

enum NativeSupportLevel: String, Codable, Identifiable, Hashable {
    case schemaReady = "Schema Ready"
    case fileWorkflowPlanned = "File Workflow Planned"
    case usbDriverPlanned = "USB Driver Planned"
    case directProgrammingReady = "Direct Programming Ready"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .schemaReady:
            return "The app fully understands the memory fields, but not the radio protocol yet."
        case .fileWorkflowPlanned:
            return "File and backup compatibility is the next standalone step."
        case .usbDriverPlanned:
            return "Direct native programming is planned around a first-party USB driver."
        case .directProgrammingReady:
            return "The app can talk to the radio directly over its native workflow."
        }
    }
}

struct RadioDefinition: Identifiable, Hashable {
    let model: BuiltInRadioModel
    let vendor: String
    let supportLevel: NativeSupportLevel
    let recommendedConnection: RadioConnectionKind
    let supportedConnections: [RadioConnectionKind]
    let summary: String
    let currentNativeFunctions: [String]
    let nextNativeMilestones: [String]
    let compatibilityNotes: [String]

    var id: BuiltInRadioModel { model }
}

protocol RadioDriver {
    var definition: RadioDefinition { get }
    func validate(channels: [ChannelMemory]) -> [String]
}

struct RT950ProDriver: RadioDriver {
    let definition = RadioCatalog.definition(for: .radtelRT950Pro)

    func validate(channels: [ChannelMemory]) -> [String] {
        var issues: [String] = []
        if channels.isEmpty {
            issues.append("No channels are loaded for the RT-950 Pro profile yet.")
        }
        if channels.contains(where: { $0.frequency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append("One or more channels are missing a receive frequency.")
        }

        let nonEmptyLocations = channels.map(\.location).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if Set(nonEmptyLocations).count != nonEmptyLocations.count {
            issues.append("Duplicate channel locations were found.")
        }

        return issues
    }
}

enum RadioCatalog {
    static func definition(for model: BuiltInRadioModel) -> RadioDefinition {
        switch model {
        case .radtelRT950Pro:
            return RadioDefinition(
                model: .radtelRT950Pro,
                vendor: "Radtel",
                supportLevel: .directProgrammingReady,
                recommendedConnection: .usbCable,
                supportedConnections: [.usbCable, .csvFile, .bluetooth],
                summary: "Primary standalone target. RadMan can read native RT-950 Pro clone images, decode channels and settings, create backups, and write updated channel memories back over USB.",
                currentNativeFunctions: [
                    "RT-950 Pro memory schema editing",
                    "Built-in channel CSV import/export",
                    "RT-950 Pro CPS zone-name import",
                    "USB serial port discovery and preflight checks",
                    "Native RT-950 Pro identify and clone download",
                    "Decoded VFO/function/DTMF/APRS summaries",
                    "Core radio settings editing with full-clone safety checks",
                    "APRS settings editing with full-clone safety checks",
                    "Native clone import/export and managed backups",
                    "USB channel write-back using live clone preservation",
                    "Direct channel programming from Channel Manager",
                ],
                nextNativeMilestones: [
                    "Map more RT-950 clone sections into editable UI controls",
                    "Explore Bluetooth workflows later",
                    "Investigate any true live-control protocol if one exists",
                ],
                compatibilityNotes: [
                    "Use channel CSV export for migration and sharing.",
                    "Use USB first for reliable direct programming on macOS.",
                ]
            )
        case .genericCSVInterop:
            return RadioDefinition(
                model: .genericCSVInterop,
                vendor: "Generic",
                supportLevel: .schemaReady,
                recommendedConnection: .csvFile,
                supportedConnections: [.csvFile],
                summary: "Fallback profile for generic CSV exchange when a first-party radio driver is not available yet.",
                currentNativeFunctions: [
                    "Generic channel editing",
                    "CSV import/export",
                ],
                nextNativeMilestones: [
                    "Map common schemas into first-party drivers over time.",
                ],
                compatibilityNotes: [
                    "Useful for non-target radios while native drivers are still being added.",
                ]
            )
        }
    }

    static var nativeDefinitions: [RadioDefinition] {
        BuiltInRadioModel.allCases.map(definition).filter { $0.model != .genericCSVInterop }
    }

    static var preferredStandaloneTarget: RadioDefinition {
        definition(for: .radtelRT950Pro)
    }

    static func driver(for model: BuiltInRadioModel) -> (any RadioDriver)? {
        switch model {
        case .radtelRT950Pro:
            return RT950ProDriver()
        case .genericCSVInterop:
            return nil
        }
    }
}
