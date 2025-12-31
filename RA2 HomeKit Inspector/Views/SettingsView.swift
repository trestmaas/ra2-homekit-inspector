import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var settings = SettingsManager.shared
    @State private var password = ""
    @State private var showPassword = false
    @State private var isSaving = false
    @State private var saveMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Main Repeater IP:", text: $settings.repeaterHost)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Port:")
                    TextField("", value: $settings.repeaterPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }

                TextField("Username:", text: $settings.repeaterUsername)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    if showPassword {
                        TextField("Password:", text: $password)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Password:", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                Toggle("Connect on Launch", isOn: $settings.autoConnectOnLaunch)
            } header: {
                Label("RadioRA 2 Connection", systemImage: "cable.connector")
            }

            Section {
                HStack {
                    Button("Save Credentials") {
                        saveCredentials()
                    }
                    .disabled(settings.repeaterHost.isEmpty || password.isEmpty)

                    if let message = saveMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(message.contains("Error") ? .red : .green)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About RA2 HomeKit Inspector")
                        .font(.headline)

                    Text("Version 1.0.0")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("A diagnostic tool for Lutron RadioRA 2 and Apple HomeKit integration.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    Text("This app connects locally to your RadioRA 2 Main Repeater and reads HomeKit data. No cloud services are used. No data leaves your network.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Label("About", systemImage: "info.circle")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .padding()
        .onAppear {
            password = settings.retrievePassword() ?? ""
        }
    }

    private func saveCredentials() {
        do {
            try settings.savePassword(password)
            saveMessage = "Credentials saved to Keychain"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                saveMessage = nil
            }
        } catch {
            saveMessage = "Error: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
