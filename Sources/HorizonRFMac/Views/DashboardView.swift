import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    private let standaloneTarget = RadioCatalog.preferredStandaloneTarget

    private var profile: RadioProfile? {
        store.preferredRT950ProProfile
    }

    private var memoryMix: [(String, Int, Color)] {
        [
            ("Marine", store.channels.filter { $0.category == .marine }.count, RadManPalette.teal),
            ("Airband", store.channels.filter { $0.category == .airband }.count, RadManPalette.coral),
            ("Amateur", store.channels.filter { $0.category == .amateur }.count, RadManPalette.amber),
            ("PMR", store.channels.filter { $0.category == .pmr }.count, .blue),
        ]
        .filter { $0.1 > 0 }
    }

    private var featuredChannels: [ChannelMemory] {
        Array(store.sortedChannels.prefix(6))
    }

    private var freeSlots: Int {
        max(0, store.channelCapacity - store.channels.count)
    }

    private var occupiedZones: [ChannelZoneSummary] {
        ChannelPlanService.zoneSummaries(from: store.channels).filter { $0.usedSlots > 0 }
    }

    private var utilizationPercent: Int {
        guard store.channelCapacity > 0 else { return 0 }
        return Int((Double(store.channels.count) / Double(store.channelCapacity) * 100.0).rounded())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RadManHeroCard(
                    title: "Operations Dashboard",
                    subtitle: heroSubtitle,
                    accent: RadManPalette.teal
                ) {
                    HStack(spacing: 10) {
                        RadManBadge(text: standaloneTarget.supportLevel.rawValue, accent: RadManPalette.teal)
                        RadManBadge(text: standaloneTarget.recommendedConnection.rawValue, accent: RadManPalette.amber)
                        if let port = profile?.serialPort, !port.isEmpty {
                            RadManBadge(text: port, accent: RadManPalette.coral)
                        }
                    }
                }

                HStack(spacing: 16) {
                    RadManMetricCard(title: "Channels", value: "\(store.channels.count)", subtitle: "Loaded memories ready to review or write", accent: RadManPalette.teal)
                    RadManMetricCard(title: "Capacity", value: "\(store.channelCapacity)", subtitle: "Total RT-950 Pro memory slots", accent: RadManPalette.coral)
                    RadManMetricCard(title: "Free Slots", value: "\(freeSlots)", subtitle: "Available memories before the radio is full", accent: RadManPalette.amber)
                    RadManMetricCard(title: "Radios", value: "\(store.radios.count)", subtitle: "Profiles configured in RadMan", accent: RadManPalette.slate)
                }

                HStack(alignment: .top, spacing: 18) {
                    RadManPanel(title: "Device Status", subtitle: "What RadMan currently knows about your RT-950 Pro.") {
                        VStack(alignment: .leading, spacing: 10) {
                            DashboardDataRow(label: "Profile", value: profile?.name.ifEmpty(profile?.resolvedModelName ?? "Not configured") ?? "Not configured")
                            DashboardDataRow(label: "Last Read", value: profile?.lastNativeCloneCapturedAt?.formatted(date: .abbreviated, time: .shortened) ?? "No live read yet")
                            DashboardDataRow(label: "Port", value: profile?.serialPort.ifEmpty("Not assigned") ?? "Not assigned")
                            DashboardDataRow(label: "Model", value: profile?.lastNativeModelIdentifier.ifEmpty(profile?.resolvedModelName ?? standaloneTarget.model.rawValue) ?? standaloneTarget.model.rawValue)
                        }
                    }

                    RadManPanel(title: "Memory Mix", subtitle: "A quick view of the channel library currently loaded.") {
                        if memoryMix.isEmpty {
                            Text("No memory categories available yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(memoryMix, id: \.0) { item in
                                    HStack {
                                        RadManBadge(text: item.0, accent: item.2)
                                        Spacer()
                                        Text("\(item.1)")
                                            .font(.system(.headline, design: .rounded))
                                    }
                                }
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 18) {
                    RadManPanel(title: "Featured Memories", subtitle: "A few channels from the active library so the dashboard feels alive.") {
                        if featuredChannels.isEmpty {
                            Text("Read the RT-950 Pro or import a channel file to populate the library.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(featuredChannels) { channel in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(channel.displayName)
                                                .font(.headline)
                                            Text(channel.frequency + " MHz")
                                                .font(.system(.subheadline, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                            Text(store.zoneSummaryLabel(for: channel))
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        RadManBadge(text: channel.categoryTitle, accent: channel.categoryAccent)
                                    }
                                }
                            }
                        }
                    }

                    RadManPanel(title: "Programming Overview", subtitle: "A quick operational summary for the current RT-950 Pro workspace.") {
                        VStack(alignment: .leading, spacing: 16) {
                            DashboardActivityRow(
                                title: "Memory Utilization",
                                subtitle: "\(utilizationPercent)% of RT-950 Pro memory currently populated",
                                timestamp: "\(store.channels.count) / \(store.channelCapacity) slots"
                            )
                            DashboardActivityRow(
                                title: "Programming Path",
                                subtitle: "Native USB clone workflow with full-device backup safety",
                                timestamp: profile?.serialPort.ifEmpty("Port not assigned") ?? "Port not assigned"
                            )
                            DashboardActivityRow(
                                title: "Editable Areas",
                                subtitle: "Channels, core settings, DTMF, and APRS are writable. Device VFO state is read-only.",
                                timestamp: "Safe sync only"
                            )
                        }
                    }
                }

                RadManPanel(title: "Zone Overview", subtitle: "Native RT-950 Pro zones are fixed at 15 banks of 64 slots each.") {
                    if occupiedZones.isEmpty {
                        Text("Read the radio or import channels to see zone occupancy.")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                            ForEach(occupiedZones) { zone in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(store.zoneName(for: zone.zone))
                                        .font(.headline)
                                    Text("\(zone.usedSlots) / \(zone.capacity) used")
                                        .font(.system(.title3, design: .rounded).weight(.bold))
                                    Text("\(zone.freeSlots) free • next slot \(zone.firstAvailableSlot.map(String.init) ?? "full")")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color.white.opacity(0.74))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var heroSubtitle: String {
        if let profile {
            let name = profile.name.ifEmpty(profile.resolvedModelName)
            let capture = profile.lastNativeCloneCapturedAt?.formatted(date: .abbreviated, time: .shortened) ?? "no live snapshot yet"
            return "Tracking \(store.channels.count) memories for \(name). The latest device snapshot was captured \(capture)."
        }
        return "RadMan is ready to manage RT-950 Pro memories, backups, USB programming, and device settings from one native Mac interface."
    }
}

private struct DashboardDataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

private struct DashboardActivityRow: View {
    let title: String
    let subtitle: String
    let timestamp: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(timestamp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
