import Foundation
import Combine

@MainActor
class AppState: ObservableObject {
    // RA2 Connection State
    @Published var ra2ConnectionStatus: ConnectionStatus = .disconnected
    @Published var ra2Devices: [RA2Device] = []
    @Published var ra2Scenes: [RA2Scene] = []

    // HomeKit State
    @Published var homeKitStatus: ConnectionStatus = .disconnected
    @Published var homeKitHomes: [HomeKitHome] = []
    @Published var homeKitDevices: [HomeKitDevice] = []

    // Diagnostics
    @Published var diagnosticResults: [DiagnosticResult] = []
    @Published var brightnessTestResults: [BrightnessTestResult] = []

    // Error State
    @Published var currentError: AppError?

    // Services
    let ra2Service: RA2Service
    let homeKitService: HomeKitService

    init() {
        self.ra2Service = RA2Service()
        self.homeKitService = HomeKitService()
    }
}

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var displayText: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

struct AppError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let recoveryAction: String?
}
