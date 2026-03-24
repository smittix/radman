import SwiftUI

struct ContentView: View {
    @State private var selection: AppSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("RadMan")
            .frame(minWidth: 220)
        } detail: {
            Group {
                switch selection ?? .dashboard {
                case .dashboard:
                    DashboardView()
                case .device:
                    DeviceView()
                case .channels:
                    ChannelsView()
                case .radios:
                    RadiosView()
                case .tools:
                    ToolsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
