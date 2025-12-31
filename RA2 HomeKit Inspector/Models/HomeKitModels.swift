import Foundation
import HomeKit

// MARK: - HomeKit Home

struct HomeKitHome: Identifiable, Hashable {
    let id: UUID
    let homeKitID: UUID
    let name: String
    var rooms: [HomeKitRoom]

    init(from home: HMHome) {
        self.id = UUID()
        self.homeKitID = home.uniqueIdentifier
        self.name = home.name
        self.rooms = home.rooms.map { HomeKitRoom(from: $0) }
    }

    init(homeKitID: UUID, name: String, rooms: [HomeKitRoom] = []) {
        self.id = UUID()
        self.homeKitID = homeKitID
        self.name = name
        self.rooms = rooms
    }
}

// MARK: - HomeKit Room

struct HomeKitRoom: Identifiable, Hashable {
    let id: UUID
    let homeKitID: UUID
    let name: String

    init(from room: HMRoom) {
        self.id = UUID()
        self.homeKitID = room.uniqueIdentifier
        self.name = room.name
    }

    init(homeKitID: UUID, name: String) {
        self.id = UUID()
        self.homeKitID = homeKitID
        self.name = name
    }
}

// MARK: - HomeKit Device

struct HomeKitDevice: Identifiable, Hashable {
    let id: UUID
    let homeKitID: UUID
    let name: String
    let roomName: String?
    let homeName: String
    let isReachable: Bool
    let isLightService: Bool
    let supportsBrightness: Bool
    var brightness: Int? // 0-100, nil if not applicable

    init(from accessory: HMAccessory, homeName: String) {
        self.id = UUID()
        self.homeKitID = accessory.uniqueIdentifier
        self.name = accessory.name
        self.roomName = accessory.room?.name
        self.homeName = homeName
        self.isReachable = accessory.isReachable

        // Check for light services
        let lightServices = accessory.services.filter { $0.serviceType == HMServiceTypeLightbulb }
        self.isLightService = !lightServices.isEmpty

        // Check for brightness characteristic
        var hasBrightness = false
        var currentBrightness: Int? = nil

        for service in lightServices {
            if let brightnessChar = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeBrightness }) {
                hasBrightness = true
                if let value = brightnessChar.value as? Int {
                    currentBrightness = value
                }
                break
            }
        }

        self.supportsBrightness = hasBrightness
        self.brightness = currentBrightness
    }

    init(homeKitID: UUID, name: String, roomName: String?, homeName: String, isReachable: Bool, isLightService: Bool, supportsBrightness: Bool, brightness: Int?) {
        self.id = UUID()
        self.homeKitID = homeKitID
        self.name = name
        self.roomName = roomName
        self.homeName = homeName
        self.isReachable = isReachable
        self.isLightService = isLightService
        self.supportsBrightness = supportsBrightness
        self.brightness = brightness
    }

    var displayName: String {
        if let room = roomName {
            return "\(room) - \(name)"
        }
        return name
    }
}
