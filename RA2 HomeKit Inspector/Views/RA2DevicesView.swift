import SwiftUI
import UIKit

struct RA2DevicesView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedDevice: RA2Device?
    @State private var showConnectionSheet = false
    @State private var isRefreshing = false

    var filteredDevices: [RA2Device] {
        if searchText.isEmpty {
            return appState.ra2Devices
        }
        return appState.ra2Devices.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.locationName?.localizedCaseInsensitiveContains(searchText) == true ||
            String($0.integrationID).contains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                ConnectionStatusView(status: appState.ra2ConnectionStatus)

                Spacer()

                Button {
                    showConnectionSheet = true
                } label: {
                    Label("Connect", systemImage: "cable.connector")
                }
                .disabled(appState.ra2ConnectionStatus.isConnected)

                Button {
                    Task {
                        await refreshDevices()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!appState.ra2ConnectionStatus.isConnected || isRefreshing)

                Button {
                    copyToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(appState.ra2Devices.isEmpty)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))

            Divider()

            // Device List
            if appState.ra2Devices.isEmpty {
                EmptyStateView(
                    icon: "lightbulb.slash",
                    title: "No RA2 Devices",
                    message: appState.ra2ConnectionStatus.isConnected
                        ? "No devices found. Try refreshing."
                        : "Connect to your Main Repeater to view devices."
                )
            } else {
                List(filteredDevices, selection: $selectedDevice) { device in
                    RA2DeviceRow(
                        device: device,
                        onSetLevel: { level in
                            Task { await setDeviceLevel(device, level: level) }
                        },
                        onIdentify: {
                            Task { await identifyDevice(device) }
                        }
                    )
                }
                .searchable(text: $searchText, prompt: "Filter devices...")
            }
        }
        .sheet(isPresented: $showConnectionSheet) {
            RA2ConnectionSheet()
        }
        .navigationTitle("RA2 Devices")
    }

    private func refreshDevices() async {
        isRefreshing = true
        defer { isRefreshing = false }
        // Would call RA2 service to refresh device list
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }

    private func setDeviceLevel(_ device: RA2Device, level: Int) async {
        do {
            try await appState.ra2Service.setZoneLevel(integrationID: device.integrationID, level: level)
        } catch {
            appState.currentError = AppError(
                title: "Failed to Set Level",
                message: error.localizedDescription,
                recoveryAction: nil
            )
        }
    }

    private func identifyDevice(_ device: RA2Device) async {
        do {
            try await appState.ra2Service.identifyZone(integrationID: device.integrationID)
        } catch {
            appState.currentError = AppError(
                title: "Failed to Identify Device",
                message: error.localizedDescription,
                recoveryAction: nil
            )
        }
    }

    private func copyToClipboard() {
        var csv = "Integration ID,Name,Type,Location,Level\n"
        for device in filteredDevices {
            let level = device.currentLevel.map { "\($0)%" } ?? ""
            csv += "\(device.integrationID),\"\(device.name)\",\"\(device.deviceType.rawValue)\",\"\(device.locationName ?? "")\",\(level)\n"
        }
        UIPasteboard.general.string = csv
    }
}

struct RA2DeviceRow: View {
    let device: RA2Device
    let onSetLevel: (Int) -> Void
    let onIdentify: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(device.integrationID)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    Text(device.name)
                        .font(.headline)
                }

                HStack {
                    Image(systemName: iconForDeviceType(device.deviceType))
                        .foregroundColor(.secondary)
                    Text(device.deviceType.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let location = device.locationName {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(location)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if let level = device.currentLevel {
                VStack(alignment: .trailing) {
                    Text("\(level)%")
                        .monospacedDigit()
                        .font(.caption)
                    ProgressView(value: Double(level), total: 100)
                        .frame(width: 60)
                }
            }

            if device.deviceType.supportsLevel {
                HStack(spacing: 8) {
                    Button { onSetLevel(100) } label: {
                        Image(systemName: "sun.max")
                    }
                    .buttonStyle(.borderless)

                    Button { onSetLevel(0) } label: {
                        Image(systemName: "moon")
                    }
                    .buttonStyle(.borderless)

                    Button { onIdentify() } label: {
                        Image(systemName: "flashlight.on.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func iconForDeviceType(_ type: RA2DeviceType) -> String {
        switch type {
        case .dimmer:
            return "lightbulb"
        case .switch:
            return "light.switch.2"
        case .keypad:
            return "rectangle.split.3x3"
        case .occupancySensor:
            return "figure.walk.motion"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

// MARK: - Connection Sheet

struct RA2ConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject private var settings = SettingsManager.shared

    @State private var host = ""
    @State private var port = "23"
    @State private var username = "lutron"
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    // Discovery state
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var discoveredDevices: [DiscoveredDevice] = []
    @State private var showDiscoveryResults = false

    private let discoveryService = NetworkDiscoveryService()

    var body: some View {
        NavigationView {
            Form {
                Section("Connection") {
                    HStack {
                        TextField("IP Address", text: $host)
                        Button {
                            Task { await startDiscovery() }
                        } label: {
                            if isScanning {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "magnifyingglass.circle")
                            }
                        }
                        .disabled(isScanning)
                        .help("Scan network for Lutron devices")
                    }

                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                }

                if isScanning {
                    Section("Scanning Network") {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: scanProgress)
                            Text("Scanning for Lutron devices... \(Int(scanProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if !discoveredDevices.isEmpty {
                    Section("Discovered Devices") {
                        ForEach(discoveredDevices) { device in
                            Button {
                                host = device.ipAddress
                                port = "23"
                            } label: {
                                HStack {
                                    Image(systemName: device.isLutron ? "checkmark.circle.fill" : "questionmark.circle")
                                        .foregroundColor(device.isLutron ? .green : .orange)
                                    VStack(alignment: .leading) {
                                        Text(device.ipAddress)
                                            .font(.headline)
                                        if device.isLutron {
                                            Text("Lutron Device Detected")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        } else {
                                            Text("Telnet port open")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if host == device.ipAddress {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Connect to Main Repeater")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        Task {
                            await connect()
                        }
                    }
                    .disabled(host.isEmpty || isConnecting)
                }
            }
        }
        .frame(minWidth: 450, minHeight: 400)
        .onAppear {
            host = settings.repeaterHost
            port = String(settings.repeaterPort)
            username = settings.repeaterUsername
            password = settings.retrievePassword() ?? ""

            // Auto-scan if no host is configured
            if host.isEmpty {
                Task { await startDiscovery() }
            }
        }
    }

    private func startDiscovery() async {
        isScanning = true
        scanProgress = 0
        discoveredDevices = []
        errorMessage = nil

        let devices = await discoveryService.scanForLutronDevices { scanned, total in
            Task { @MainActor in
                scanProgress = Double(scanned) / Double(total)
            }
        }

        await MainActor.run {
            discoveredDevices = devices
            isScanning = false

            // Auto-select if we found a Lutron device
            if let lutronDevice = devices.first(where: { $0.isLutron }) {
                host = lutronDevice.ipAddress
            }

            if devices.isEmpty {
                errorMessage = "No devices found. Make sure you're on the same network as the repeater."
            }
        }
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil

        do {
            // Save settings
            settings.repeaterHost = host
            settings.repeaterPort = Int(port) ?? 23
            settings.repeaterUsername = username
            try settings.savePassword(password)

            // Connect
            try await appState.ra2Service.connect(
                host: host,
                port: UInt16(Int(port) ?? 23),
                username: username,
                password: password
            )

            await MainActor.run {
                appState.ra2ConnectionStatus = .connected
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                appState.ra2ConnectionStatus = .error(error.localizedDescription)
            }
        }

        isConnecting = false
    }
}

#Preview {
    RA2DevicesView()
        .environmentObject(AppState())
}
