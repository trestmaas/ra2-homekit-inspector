import SwiftUI
import UIKit

struct HomeKitDevicesView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedDevice: HomeKitDevice?
    @State private var isRefreshing = false
    @State private var filterLightsOnly = true
    @State private var selectedHome: String = "All Homes"

    var availableHomes: [String] {
        let homes = Set(appState.homeKitDevices.map { $0.homeName })
        return ["All Homes"] + homes.sorted()
    }

    var filteredDevices: [HomeKitDevice] {
        var devices = appState.homeKitDevices

        if filterLightsOnly {
            devices = devices.filter { $0.isLightService }
        }

        if selectedHome != "All Homes" {
            devices = devices.filter { $0.homeName == selectedHome }
        }

        if !searchText.isEmpty {
            devices = devices.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.roomName?.localizedCaseInsensitiveContains(searchText) == true ||
                $0.homeName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return devices
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                ConnectionStatusView(status: appState.homeKitStatus)

                Spacer()

                Picker("Home:", selection: $selectedHome) {
                    ForEach(availableHomes, id: \.self) { home in
                        Text(home).tag(home)
                    }
                }
                .frame(width: 150)

                Toggle("Lights Only", isOn: $filterLightsOnly)

                Button {
                    Task {
                        await refreshDevices()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)

                Button {
                    copyToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(appState.homeKitDevices.isEmpty)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))

            Divider()

            // Device List
            if appState.homeKitDevices.isEmpty {
                EmptyStateView(
                    icon: "house.slash",
                    title: "No HomeKit Devices",
                    message: "Grant HomeKit access to view your devices."
                )
            } else {
                List(filteredDevices, selection: $selectedDevice) { device in
                    HomeKitDeviceRow(device: device)
                }
                .searchable(text: $searchText, prompt: "Filter devices...")
            }
        }
        .navigationTitle("HomeKit Devices")
        .task {
            await loadDevices()
        }
    }

    private func loadDevices() async {
        appState.homeKitStatus = .connecting

        let homes = await appState.homeKitService.fetchHomes()
        let devices = await appState.homeKitService.fetchDevices()

        await MainActor.run {
            appState.homeKitHomes = homes
            appState.homeKitDevices = devices
            appState.homeKitStatus = devices.isEmpty ? .error("No devices found") : .connected
        }
    }

    private func refreshDevices() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await loadDevices()
    }

    private func copyToClipboard() {
        var csv = "Name,Room,Home,Type,Brightness,Reachable\n"
        for device in filteredDevices {
            let brightness = device.brightness.map { "\($0)%" } ?? ""
            let type = device.isLightService ? "Light" : "Other"
            let reachable = device.isReachable ? "Yes" : "No"
            csv += "\"\(device.name)\",\"\(device.roomName ?? "")\",\"\(device.homeName)\",\"\(type)\",\(brightness),\(reachable)\n"
        }
        UIPasteboard.general.string = csv
    }
}

struct HomeKitDeviceRow: View {
    let device: HomeKitDevice

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: device.isReachable ? "circle.fill" : "circle")
                        .foregroundColor(device.isReachable ? .green : .red)
                        .font(.caption2)
                    Text(device.name)
                        .font(.headline)
                }

                HStack {
                    if let room = device.roomName {
                        Text(room)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(device.homeName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if device.supportsBrightness, let brightness = device.brightness {
                VStack(alignment: .trailing) {
                    Text("\(brightness)%")
                        .monospacedDigit()
                        .font(.caption)
                    ProgressView(value: Double(brightness), total: 100)
                        .frame(width: 60)
                }
            }

            Image(systemName: device.isLightService ? "lightbulb" : "square.grid.2x2")
                .foregroundColor(.secondary)
                .frame(width: 30)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HomeKitDevicesView()
        .environmentObject(AppState())
}
