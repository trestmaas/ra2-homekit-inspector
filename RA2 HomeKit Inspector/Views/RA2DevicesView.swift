import SwiftUI

struct RA2DevicesView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\RA2Device.name)]
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
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Device Table
            if appState.ra2Devices.isEmpty {
                EmptyStateView(
                    icon: "lightbulb.slash",
                    title: "No RA2 Devices",
                    message: appState.ra2ConnectionStatus.isConnected
                        ? "No devices found. Try refreshing."
                        : "Connect to your Main Repeater to view devices."
                )
            } else {
                Table(filteredDevices, selection: $selectedDevice, sortOrder: $sortOrder) {
                    TableColumn("ID", value: \.integrationID) { device in
                        Text("\(device.integrationID)")
                            .monospacedDigit()
                    }
                    .width(50)

                    TableColumn("Name", value: \.name) { device in
                        Text(device.name)
                    }

                    TableColumn("Type") { device in
                        HStack {
                            Image(systemName: iconForDeviceType(device.deviceType))
                                .foregroundColor(.secondary)
                            Text(device.deviceType.rawValue)
                        }
                    }
                    .width(120)

                    TableColumn("Location") { device in
                        Text(device.locationName ?? "—")
                            .foregroundColor(device.locationName == nil ? .secondary : .primary)
                    }

                    TableColumn("Level") { device in
                        if let level = device.currentLevel {
                            HStack {
                                ProgressView(value: Double(level), total: 100)
                                    .frame(width: 60)
                                Text("\(level)%")
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }
                        } else {
                            Text("—")
                                .foregroundColor(.secondary)
                        }
                    }
                    .width(120)

                    TableColumn("Actions") { device in
                        HStack(spacing: 8) {
                            if device.deviceType.supportsLevel {
                                Button {
                                    Task {
                                        await setDeviceLevel(device, level: 100)
                                    }
                                } label: {
                                    Image(systemName: "sun.max")
                                }
                                .buttonStyle(.borderless)
                                .help("Set to 100%")

                                Button {
                                    Task {
                                        await setDeviceLevel(device, level: 0)
                                    }
                                } label: {
                                    Image(systemName: "moon")
                                }
                                .buttonStyle(.borderless)
                                .help("Set to 0%")

                                Button {
                                    Task {
                                        await identifyDevice(device)
                                    }
                                } label: {
                                    Image(systemName: "flashlight.on.fill")
                                }
                                .buttonStyle(.borderless)
                                .help("Identify (flash)")
                            }
                        }
                    }
                    .width(100)
                }
                .searchable(text: $searchText, prompt: "Filter devices...")
            }
        }
        .sheet(isPresented: $showConnectionSheet) {
            RA2ConnectionSheet()
        }
        .navigationTitle("RA2 Devices")
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv, forType: .string)
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

    var body: some View {
        VStack(spacing: 20) {
            Text("Connect to Main Repeater")
                .font(.headline)

            Form {
                TextField("IP Address:", text: $host)
                    .textFieldStyle(.roundedBorder)

                TextField("Port:", text: $port)
                    .textFieldStyle(.roundedBorder)

                TextField("Username:", text: $username)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password:", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Connect") {
                    Task {
                        await connect()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(host.isEmpty || isConnecting)
            }
            .padding()
        }
        .frame(width: 350)
        .padding()
        .onAppear {
            host = settings.repeaterHost
            port = String(settings.repeaterPort)
            username = settings.repeaterUsername
            password = settings.retrievePassword() ?? ""
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
