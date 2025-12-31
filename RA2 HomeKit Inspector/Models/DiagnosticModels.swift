import Foundation

// MARK: - Diagnostic Result Types

enum MismatchType: String, CaseIterable {
    case missingFromHomeKit = "Missing from HomeKit"
    case missingFromRA2 = "Missing from RA2"
    case nameMismatch = "Name Mismatch"
    case roomMismatch = "Room Mismatch"
    case sceneMismatch = "Scene Mismatch"

    var icon: String {
        switch self {
        case .missingFromHomeKit:
            return "exclamationmark.triangle"
        case .missingFromRA2:
            return "questionmark.circle"
        case .nameMismatch:
            return "textformat.abc"
        case .roomMismatch:
            return "rectangle.portrait.and.arrow.right"
        case .sceneMismatch:
            return "square.3.layers.3d"
        }
    }
}

// MARK: - Diagnostic Result

struct DiagnosticResult: Identifiable, Hashable {
    let id: UUID
    let mismatchType: MismatchType
    let ra2DeviceName: String?
    let homeKitDeviceName: String?
    let ra2Location: String?
    let homeKitRoom: String?
    let details: String
    let timestamp: Date

    init(
        mismatchType: MismatchType,
        ra2DeviceName: String? = nil,
        homeKitDeviceName: String? = nil,
        ra2Location: String? = nil,
        homeKitRoom: String? = nil,
        details: String
    ) {
        self.id = UUID()
        self.mismatchType = mismatchType
        self.ra2DeviceName = ra2DeviceName
        self.homeKitDeviceName = homeKitDeviceName
        self.ra2Location = ra2Location
        self.homeKitRoom = homeKitRoom
        self.details = details
        self.timestamp = Date()
    }
}

// MARK: - Brightness Test Result

enum TrimStatus: String {
    case noTrim = "No Trim Detected"
    case likelyTrimmed = "Likely High-End Trim"
    case unknown = "Unknown"

    var icon: String {
        switch self {
        case .noTrim:
            return "checkmark.circle.fill"
        case .likelyTrimmed:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

struct BrightnessTestResult: Identifiable, Hashable {
    let id: UUID
    let device: RA2Device
    let commandedLevel: Int
    let observedLevel: Int
    let trimStatus: TrimStatus
    let notes: String
    let timestamp: Date

    init(device: RA2Device, commandedLevel: Int, observedLevel: Int) {
        self.id = UUID()
        self.device = device
        self.commandedLevel = commandedLevel
        self.observedLevel = observedLevel
        self.timestamp = Date()

        if observedLevel == commandedLevel {
            self.trimStatus = .noTrim
            self.notes = "Zone reached full commanded level."
        } else if observedLevel < commandedLevel {
            self.trimStatus = .likelyTrimmed
            let difference = commandedLevel - observedLevel
            self.notes = "Zone reported \(observedLevel)% when commanded to \(commandedLevel)%. Difference of \(difference)% suggests high-end trim is active. Check RA2 programming to verify trim settings."
        } else {
            self.trimStatus = .unknown
            self.notes = "Unexpected result: observed level exceeds commanded level."
        }
    }
}

// MARK: - Export Helpers

extension DiagnosticResult {
    var csvRow: String {
        let type = mismatchType.rawValue
        let ra2Name = ra2DeviceName ?? ""
        let hkName = homeKitDeviceName ?? ""
        let ra2Loc = ra2Location ?? ""
        let hkRoom = homeKitRoom ?? ""
        return "\"\(type)\",\"\(ra2Name)\",\"\(hkName)\",\"\(ra2Loc)\",\"\(hkRoom)\",\"\(details)\""
    }

    static var csvHeader: String {
        "\"Mismatch Type\",\"RA2 Device\",\"HomeKit Device\",\"RA2 Location\",\"HomeKit Room\",\"Details\""
    }
}

extension BrightnessTestResult {
    var csvRow: String {
        "\"\(device.name)\",\"\(device.integrationID)\",\"\(commandedLevel)\",\"\(observedLevel)\",\"\(trimStatus.rawValue)\",\"\(notes)\""
    }

    static var csvHeader: String {
        "\"Device Name\",\"Integration ID\",\"Commanded Level\",\"Observed Level\",\"Trim Status\",\"Notes\""
    }
}
