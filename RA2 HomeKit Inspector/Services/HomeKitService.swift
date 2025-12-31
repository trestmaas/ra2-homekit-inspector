import Foundation
import HomeKit

// MARK: - HomeKit Service

@MainActor
class HomeKitService: NSObject, ObservableObject {
    private let homeManager: HMHomeManager
    @Published var authorizationStatus: HMHomeManagerAuthorizationStatus = .determined

    @Published var homes: [HMHome] = []
    @Published var isLoading = false
    @Published var error: HomeKitError?

    override init() {
        self.homeManager = HMHomeManager()
        super.init()
        self.homeManager.delegate = self
    }

    // MARK: - Authorization

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    // MARK: - Data Fetching

    func fetchHomes() async -> [HomeKitHome] {
        isLoading = true
        defer { isLoading = false }

        // Wait for home manager to be ready
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        return homeManager.homes.map { HomeKitHome(from: $0) }
    }

    func fetchDevices() async -> [HomeKitDevice] {
        var allDevices: [HomeKitDevice] = []

        for home in homeManager.homes {
            for accessory in home.accessories {
                let device = HomeKitDevice(from: accessory, homeName: home.name)
                allDevices.append(device)
            }
        }

        return allDevices
    }

    func fetchLightDevices() async -> [HomeKitDevice] {
        let allDevices = await fetchDevices()
        return allDevices.filter { $0.isLightService }
    }

    // MARK: - Device Details

    func refreshDeviceBrightness(_ device: HomeKitDevice) async -> Int? {
        guard let home = homeManager.homes.first(where: { $0.name == device.homeName }),
              let accessory = home.accessories.first(where: { $0.uniqueIdentifier == device.homeKitID }) else {
            return nil
        }

        for service in accessory.services where service.serviceType == HMServiceTypeLightbulb {
            if let brightnessChar = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeBrightness }) {
                do {
                    try await brightnessChar.readValue()
                    return brightnessChar.value as? Int
                } catch {
                    self.error = .readFailed(error.localizedDescription)
                    return nil
                }
            }
        }

        return nil
    }

    // MARK: - Accessory Lookup

    func findAccessory(byName name: String) -> HMAccessory? {
        for home in homeManager.homes {
            if let accessory = home.accessories.first(where: { $0.name.lowercased() == name.lowercased() }) {
                return accessory
            }
        }
        return nil
    }

    func findAccessory(inRoom roomName: String, homeName: String) -> [HMAccessory] {
        guard let home = homeManager.homes.first(where: { $0.name == homeName }),
              let room = home.rooms.first(where: { $0.name == roomName }) else {
            return []
        }

        return home.accessories.filter { $0.room == room }
    }
}

// MARK: - HMHomeManagerDelegate

extension HomeKitService: HMHomeManagerDelegate {
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            self.homes = manager.homes
        }
    }

    nonisolated func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }
}

// MARK: - Errors

enum HomeKitError: LocalizedError {
    case notAuthorized
    case noHomesFound
    case accessoryNotFound
    case readFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "HomeKit access not authorized. Please grant permission in System Settings > Privacy & Security > HomeKit."
        case .noHomesFound:
            return "No HomeKit homes found. Please set up a home in the Home app."
        case .accessoryNotFound:
            return "Accessory not found in HomeKit."
        case .readFailed(let message):
            return "Failed to read characteristic: \(message)"
        case .writeFailed(let message):
            return "Failed to write characteristic: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notAuthorized:
            return "Open System Settings and grant HomeKit access to this app."
        case .noHomesFound:
            return "Use the Home app to create a home and add accessories."
        default:
            return nil
        }
    }
}
