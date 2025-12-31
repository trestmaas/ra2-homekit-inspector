import Foundation

// MARK: - Diagnostic Service

actor DiagnosticService {

    // MARK: - Diff Engine

    func compareDevices(ra2Devices: [RA2Device], homeKitDevices: [HomeKitDevice]) -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []

        // Normalize names for comparison
        let ra2Names = Set(ra2Devices.map { normalizeName($0.name) })
        let hkNames = Set(homeKitDevices.map { normalizeName($0.name) })

        // Find devices in RA2 but not in HomeKit
        for device in ra2Devices {
            let normalizedName = normalizeName(device.name)
            if !hkNames.contains(normalizedName) {
                results.append(DiagnosticResult(
                    mismatchType: .missingFromHomeKit,
                    ra2DeviceName: device.name,
                    ra2Location: device.locationName,
                    details: "Device '\(device.name)' (ID: \(device.integrationID)) exists in RA2 but was not found in HomeKit. Check if the device is paired with the Lutron Connect Bridge."
                ))
            }
        }

        // Find devices in HomeKit but not in RA2
        for device in homeKitDevices {
            let normalizedName = normalizeName(device.name)
            if !ra2Names.contains(normalizedName) && device.isLightService {
                results.append(DiagnosticResult(
                    mismatchType: .missingFromRA2,
                    homeKitDeviceName: device.name,
                    homeKitRoom: device.roomName,
                    details: "Device '\(device.name)' exists in HomeKit but was not found in RA2. This may be a non-Lutron device or a naming mismatch."
                ))
            }
        }

        // Find name mismatches (fuzzy matching)
        results.append(contentsOf: findNameMismatches(ra2Devices: ra2Devices, homeKitDevices: homeKitDevices))

        // Find room mismatches
        results.append(contentsOf: findRoomMismatches(ra2Devices: ra2Devices, homeKitDevices: homeKitDevices))

        return results.sorted { $0.mismatchType.rawValue < $1.mismatchType.rawValue }
    }

    private func normalizeName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private func findNameMismatches(ra2Devices: [RA2Device], homeKitDevices: [HomeKitDevice]) -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []

        for ra2Device in ra2Devices {
            // Look for similar but not exact matches
            for hkDevice in homeKitDevices {
                let similarity = stringSimilarity(ra2Device.name, hkDevice.name)
                if similarity > 0.6 && similarity < 1.0 {
                    results.append(DiagnosticResult(
                        mismatchType: .nameMismatch,
                        ra2DeviceName: ra2Device.name,
                        homeKitDeviceName: hkDevice.name,
                        ra2Location: ra2Device.locationName,
                        homeKitRoom: hkDevice.roomName,
                        details: "Possible name mismatch detected. RA2 name '\(ra2Device.name)' is similar to HomeKit name '\(hkDevice.name)' (similarity: \(Int(similarity * 100))%)."
                    ))
                }
            }
        }

        return results
    }

    private func findRoomMismatches(ra2Devices: [RA2Device], homeKitDevices: [HomeKitDevice]) -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []

        for ra2Device in ra2Devices {
            guard let ra2Location = ra2Device.locationName else { continue }

            // Find matching HomeKit device
            let normalizedRA2Name = normalizeName(ra2Device.name)
            if let matchingHK = homeKitDevices.first(where: { normalizeName($0.name) == normalizedRA2Name }),
               let hkRoom = matchingHK.roomName {
                let normalizedRA2Location = normalizeName(ra2Location)
                let normalizedHKRoom = normalizeName(hkRoom)

                if normalizedRA2Location != normalizedHKRoom {
                    results.append(DiagnosticResult(
                        mismatchType: .roomMismatch,
                        ra2DeviceName: ra2Device.name,
                        homeKitDeviceName: matchingHK.name,
                        ra2Location: ra2Location,
                        homeKitRoom: hkRoom,
                        details: "Room assignment differs. RA2 location '\(ra2Location)' does not match HomeKit room '\(hkRoom)'."
                    ))
                }
            }
        }

        return results
    }

    // MARK: - String Similarity (Levenshtein-based)

    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        let str1 = s1.lowercased()
        let str2 = s2.lowercased()

        if str1 == str2 { return 1.0 }
        if str1.isEmpty || str2.isEmpty { return 0.0 }

        let distance = levenshteinDistance(str1, str2)
        let maxLength = max(str1.count, str2.count)

        return 1.0 - (Double(distance) / Double(maxLength))
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let arr1 = Array(s1)
        let arr2 = Array(s2)
        let n = arr1.count
        let m = arr2.count

        if n == 0 { return m }
        if m == 0 { return n }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)

        for i in 0...n { matrix[i][0] = i }
        for j in 0...m { matrix[0][j] = j }

        for i in 1...n {
            for j in 1...m {
                let cost = arr1[i - 1] == arr2[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[n][m]
    }

    // MARK: - Brightness Testing

    func runBrightnessTest(device: RA2Device, ra2Service: RA2Service) async throws -> BrightnessTestResult {
        guard device.deviceType == .dimmer else {
            throw DiagnosticError.notDimmable
        }

        // Store original level
        let originalLevel = device.currentLevel ?? 0

        // Command to 100%
        try await ra2Service.setZoneLevel(integrationID: device.integrationID, level: 100, fadeTime: 1.0)

        // Wait for fade to complete
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        // Query actual level
        let observedLevel = try await ra2Service.queryZoneLevel(integrationID: device.integrationID)

        // Restore original level
        try await ra2Service.setZoneLevel(integrationID: device.integrationID, level: originalLevel, fadeTime: 1.0)

        return BrightnessTestResult(
            device: device,
            commandedLevel: 100,
            observedLevel: Int(observedLevel)
        )
    }

    func runBulkBrightnessTest(devices: [RA2Device], ra2Service: RA2Service) async throws -> [BrightnessTestResult] {
        var results: [BrightnessTestResult] = []

        let dimmableDevices = devices.filter { $0.deviceType == .dimmer }

        for device in dimmableDevices {
            do {
                let result = try await runBrightnessTest(device: device, ra2Service: ra2Service)
                results.append(result)
            } catch {
                // Continue with other devices even if one fails
                continue
            }
        }

        return results
    }
}

// MARK: - Errors

enum DiagnosticError: LocalizedError {
    case notDimmable
    case testFailed(String)
    case noDevicesFound

    var errorDescription: String? {
        switch self {
        case .notDimmable:
            return "Device does not support dimming"
        case .testFailed(let reason):
            return "Brightness test failed: \(reason)"
        case .noDevicesFound:
            return "No devices found to test"
        }
    }
}
