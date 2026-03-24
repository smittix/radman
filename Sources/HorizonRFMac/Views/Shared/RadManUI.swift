import SwiftUI

enum RadManPalette {
    static let ink = Color(red: 0.10, green: 0.14, blue: 0.18)
    static let slate = Color(red: 0.18, green: 0.24, blue: 0.29)
    static let mist = Color(red: 0.95, green: 0.97, blue: 0.99)
    static let teal = Color(red: 0.12, green: 0.67, blue: 0.64)
    static let amber = Color(red: 0.91, green: 0.67, blue: 0.20)
    static let coral = Color(red: 0.85, green: 0.38, blue: 0.26)
}

struct RadManHeroCard<Content: View>: View {
    let title: String
    let subtitle: String
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.82))
            }

            content
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            RadManPalette.ink,
                            RadManPalette.slate,
                            accent.opacity(0.9),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct RadManMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(RadManPalette.ink)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(RadManPalette.mist)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }
}

struct RadManBadge: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accent.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct RadManPanel<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.black.opacity(0.06), lineWidth: 1)
        )
    }
}

struct RadManMenuLabel: View {
    let title: String
    let systemImage: String
    var accent: Color = RadManPalette.mist

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.black.opacity(0.08), lineWidth: 1)
            )
            .foregroundStyle(RadManPalette.ink)
    }
}

enum RadManBannerTone {
    case info
    case success
    case warning

    var accent: Color {
        switch self {
        case .info:
            return RadManPalette.teal
        case .success:
            return .green
        case .warning:
            return RadManPalette.amber
        }
    }
}

struct RadManStatusBanner: View {
    let text: String
    let tone: RadManBannerTone

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tone.accent)
                .frame(width: 10, height: 10)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(RadManPalette.ink)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(tone.accent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct RadManPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minWidth: 120)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [RadManPalette.teal, RadManPalette.ink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct RadManSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(RadManPalette.mist)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.black.opacity(0.08), lineWidth: 1)
            )
            .foregroundStyle(RadManPalette.ink)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

enum ChannelCategory {
    case marine
    case airband
    case amateur
    case pmr
    case utility
}

extension ChannelMemory {
    var zoneNumber: Int? {
        ChannelPlanService.zoneValue(for: self)
    }

    var zoneSlot: Int? {
        ChannelPlanService.slotValue(for: self)
    }

    var zoneLabel: String {
        guard let zoneNumber else { return "Zone ?" }
        return "Zone \(zoneNumber)"
    }

    func zoneLabel(using zoneNames: [String]) -> String {
        guard let zoneNumber else { return "Zone ?" }
        return ChannelPlanService.zoneName(for: zoneNumber, customNames: zoneNames)
    }

    var zoneSlotLabel: String {
        guard let zoneSlot else { return "Slot ?" }
        return "Slot \(zoneSlot)"
    }

    var zoneSummaryLabel: String {
        guard let zoneNumber, let zoneSlot else { return "Zone ?, Slot ?" }
        return "Z\(zoneNumber) • S\(zoneSlot)"
    }

    func zoneSummaryLabel(using zoneNames: [String]) -> String {
        guard let zoneNumber, let zoneSlot else { return "Zone ?, Slot ?" }
        return "\(ChannelPlanService.zoneShortLabel(for: zoneNumber, customNames: zoneNames)) • S\(zoneSlot)"
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unnamed Memory" : trimmed
    }

    var frequencyMHzValue: Double? {
        Double(frequency.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var category: ChannelCategory {
        let upperName = name.uppercased()
        let mhz = frequencyMHzValue ?? 0
        if upperName.contains("SEA") || (156.0...163.5).contains(mhz) {
            return .marine
        }
        if modeDisplay == "AM" || (118.0...137.0).contains(mhz) {
            return .airband
        }
        if upperName.contains("PMR") || (446.0...446.2).contains(mhz) {
            return .pmr
        }
        if (144.0...148.0).contains(mhz) || (430.0...440.0).contains(mhz) {
            return .amateur
        }
        return .utility
    }

    var categoryTitle: String {
        switch category {
        case .marine:
            return "Marine"
        case .airband:
            return "Airband"
        case .amateur:
            return "Amateur"
        case .pmr:
            return "PMR"
        case .utility:
            return "Utility"
        }
    }

    var categoryAccent: Color {
        switch category {
        case .marine:
            return RadManPalette.teal
        case .airband:
            return RadManPalette.coral
        case .amateur:
            return RadManPalette.amber
        case .pmr:
            return Color.blue
        case .utility:
            return RadManPalette.slate
        }
    }

    var modeDisplay: String {
        mode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "FM" : mode
    }

    var toneSummary: String {
        let trimmed = tone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        switch trimmed.uppercased() {
        case "TONE":
            return rToneFreq.isEmpty ? "Tone" : "Tone \(rToneFreq)"
        case "TSQL":
            if !cToneFreq.isEmpty {
                return "TSQL \(cToneFreq)"
            }
            return "TSQL"
        case "DTCS":
            return dtcsCode.isEmpty ? "DTCS" : "DTCS \(dtcsCode)"
        case "CROSS":
            return crossMode.isEmpty ? "Cross" : crossMode
        default:
            return trimmed
        }
    }

    var txSummary: String {
        let duplexValue = duplex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch duplexValue {
        case "", "simplex":
            return ""
        case "+":
            return offset.isEmpty ? "TX +" : "TX +\(offset)"
        case "-":
            return offset.isEmpty ? "TX -" : "TX -\(offset)"
        case "split":
            return offset.isEmpty ? "Split TX" : "Split \(offset)"
        case "off":
            return "Receive only"
        default:
            return duplex
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
