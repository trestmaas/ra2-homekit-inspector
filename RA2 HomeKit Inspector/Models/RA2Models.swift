import Foundation

// MARK: - RA2 Device Types

enum RA2DeviceType: String, Codable, CaseIterable {
    case dimmer = "Dimmer"
    case `switch` = "Switch"
    case keypad = "Keypad"
    case occupancySensor = "Occupancy Sensor"
    case unknown = "Unknown"

    var supportsLevel: Bool {
        switch self {
        case .dimmer:
            return true
        default:
            return false
        }
    }
}

// MARK: - RA2 Device

struct RA2Device: Identifiable, Hashable {
    let id: UUID
    let integrationID: Int
    let name: String
    let deviceType: RA2DeviceType
    let locationName: String?
    var currentLevel: Int? // 0-100 for dimmers, nil for non-dimmable

    init(integrationID: Int, name: String, deviceType: RA2DeviceType, locationName: String? = nil, currentLevel: Int? = nil) {
        self.id = UUID()
        self.integrationID = integrationID
        self.name = name
        self.deviceType = deviceType
        self.locationName = locationName
        self.currentLevel = currentLevel
    }

    var displayName: String {
        if let location = locationName {
            return "\(location) - \(name)"
        }
        return name
    }
}

// MARK: - RA2 Scene

struct RA2Scene: Identifiable, Hashable {
    let id: UUID
    let integrationID: Int
    let name: String
    let buttonNumber: Int
    let keypadID: Int

    init(integrationID: Int, name: String, buttonNumber: Int, keypadID: Int) {
        self.id = UUID()
        self.integrationID = integrationID
        self.name = name
        self.buttonNumber = buttonNumber
        self.keypadID = keypadID
    }
}

// MARK: - RA2 Zone (for component tracking)

struct RA2Zone: Identifiable, Hashable {
    let id: UUID
    let integrationID: Int
    let name: String
    var level: Int // 0-100

    init(integrationID: Int, name: String, level: Int = 0) {
        self.id = UUID()
        self.integrationID = integrationID
        self.name = name
        self.level = level
    }
}
