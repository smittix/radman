import SwiftUI

struct RT950ProComparisonSheet: View {
    let report: RT950ProComparisonReport

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Comparison Preview")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("Review the differences between \(report.beforeLabel) and \(report.afterLabel) before you program, restore, or replace radio data.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                RadManMetricCard(
                    title: report.beforeLabel,
                    value: report.sections.isEmpty ? "No Changes" : "\(report.totalChangeCount)",
                    subtitle: "Current side",
                    accent: RadManPalette.slate
                )
                RadManMetricCard(
                    title: report.afterLabel,
                    value: report.sections.isEmpty ? "No Changes" : "\(report.totalChangeCount)",
                    subtitle: "Target side",
                    accent: RadManPalette.teal
                )
                RadManMetricCard(
                    title: "Changed Fields",
                    value: "\(report.totalChangeCount)",
                    subtitle: report.sections.isEmpty ? "The compared data matches." : "\(report.sections.count) section\(report.sections.count == 1 ? "" : "s") differ",
                    accent: RadManPalette.coral
                )
            }

            ScrollView {
                if report.sections.isEmpty {
                    ContentUnavailableView(
                        "No Differences Found",
                        systemImage: "checkmark.seal",
                        description: Text("The compared channel plan and device settings already match.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(report.sections) { section in
                            RadManPanel(title: section.kind.rawValue, subtitle: section.summary) {
                                VStack(spacing: 12) {
                                    ForEach(section.items) { item in
                                        ComparisonRow(item: item, beforeLabel: report.beforeLabel, afterLabel: report.afterLabel)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(RadManPrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 920, height: 720)
    }
}

private struct ComparisonRow: View {
    let item: RT950ProComparisonItem
    let beforeLabel: String
    let afterLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.label)
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                comparisonColumn(title: beforeLabel, value: item.beforeValue, accent: RadManPalette.slate)
                comparisonColumn(title: afterLabel, value: item.afterValue, accent: RadManPalette.teal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func comparisonColumn(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(RadManPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
