import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: Tab = .ra2Devices

    enum Tab: String, CaseIterable {
        case ra2Devices = "RA2 Devices"
        case homeKitDevices = "HomeKit Devices"
        case diagnostics = "Diagnostics"
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: iconForTab(tab))
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selectedTab {
            case .ra2Devices:
                RA2DevicesView()
            case .homeKitDevices:
                HomeKitDevicesView()
            case .diagnostics:
                DiagnosticsView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func iconForTab(_ tab: Tab) -> String {
        switch tab {
        case .ra2Devices:
            return "lightbulb"
        case .homeKitDevices:
            return "house"
        case .diagnostics:
            return "waveform.badge.magnifyingglass"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
