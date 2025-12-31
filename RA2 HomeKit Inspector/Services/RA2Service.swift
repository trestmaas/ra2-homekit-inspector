import Foundation
import Network

// MARK: - Lutron Integration Protocol Commands

enum RA2Command {
    case login(username: String, password: String)
    case queryZoneLevel(integrationID: Int)
    case setZoneLevel(integrationID: Int, level: Int, fadeTime: Double)
    case activateScene(keypadID: Int, buttonNumber: Int)
    case queryDevices
    case ping

    var commandString: String {
        switch self {
        case .login(let username, let password):
            return "\(username)\r\n\(password)\r\n"
        case .queryZoneLevel(let id):
            return "?OUTPUT,\(id),1\r\n"
        case .setZoneLevel(let id, let level, let fadeTime):
            return "#OUTPUT,\(id),1,\(level),\(String(format: "%.2f", fadeTime))\r\n"
        case .activateScene(let keypadID, let buttonNumber):
            return "#DEVICE,\(keypadID),\(buttonNumber),3\r\n" // Action 3 = Press
        case .queryDevices:
            return "?SYSTEM,1\r\n"
        case .ping:
            return "?SYSTEM,1\r\n"
        }
    }
}

// MARK: - RA2 Response Types

enum RA2Response {
    case zoneLevel(integrationID: Int, level: Double)
    case deviceInfo(integrationID: Int, name: String, type: RA2DeviceType)
    case loginPrompt
    case loginSuccess
    case loginFailure
    case error(String)
    case unknown(String)

    static func parse(_ line: String) -> RA2Response {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains("login:") || trimmed.contains("LOGIN:") {
            return .loginPrompt
        }

        if trimmed.contains("GNET>") {
            return .loginSuccess
        }

        if trimmed.hasPrefix("~OUTPUT,") {
            // Parse zone level response: ~OUTPUT,<id>,1,<level>
            let parts = trimmed.dropFirst(8).split(separator: ",")
            if parts.count >= 3,
               let id = Int(parts[0]),
               let level = Double(parts[2]) {
                return .zoneLevel(integrationID: id, level: level)
            }
        }

        if trimmed.hasPrefix("~DEVICE,") {
            // Parse device response
            let parts = trimmed.dropFirst(8).split(separator: ",")
            if parts.count >= 2,
               let id = Int(parts[0]) {
                return .deviceInfo(integrationID: id, name: String(parts[1]), type: .unknown)
            }
        }

        if trimmed.lowercased().contains("invalid") || trimmed.lowercased().contains("error") {
            return .error(trimmed)
        }

        return .unknown(trimmed)
    }
}

// MARK: - RA2 Service

actor RA2Service {
    private var connection: NWConnection?
    private var isConnected = false
    private var responseBuffer = ""
    private var pendingResponses: [CheckedContinuation<[RA2Response], Error>] = []

    private let host: String
    private let port: UInt16
    private let username: String
    private let password: String

    init(host: String = "", port: UInt16 = 23, username: String = "lutron", password: String = "integration") {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    // MARK: - Connection Management

    func connect(host: String, port: UInt16 = 23, username: String, password: String) async throws {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        connection = NWConnection(to: endpoint, using: parameters)

        return try await withCheckedThrowingContinuation { continuation in
            connection?.stateUpdateHandler = { [weak self] state in
                Task { [weak self] in
                    await self?.handleStateChange(state, continuation: continuation, username: username, password: password)
                }
            }
            connection?.start(queue: .global())
        }
    }

    private func handleStateChange(_ state: NWConnection.State, continuation: CheckedContinuation<Void, Error>?, username: String, password: String) {
        switch state {
        case .ready:
            isConnected = true
            startReceiving()
            // Send login credentials after connection
            Task {
                try? await sendCommand(.login(username: username, password: password))
            }
            continuation?.resume()
        case .failed(let error):
            isConnected = false
            continuation?.resume(throwing: error)
        case .cancelled:
            isConnected = false
        default:
            break
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    var connectionStatus: Bool {
        isConnected
    }

    // MARK: - Data Transmission

    private func sendCommand(_ command: RA2Command) async throws {
        guard let connection = connection, isConnected else {
            throw RA2Error.notConnected
        }

        let data = command.commandString.data(using: .utf8)!

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] content, _, isComplete, error in
            Task { [weak self] in
                await self?.handleReceive(content: content, isComplete: isComplete, error: error)
            }
        }
    }

    private func handleReceive(content: Data?, isComplete: Bool, error: Error?) {
        if let data = content, let string = String(data: data, encoding: .utf8) {
            responseBuffer += string
            processBuffer()
        }

        if !isComplete && error == nil {
            startReceiving()
        }
    }

    private func processBuffer() {
        let lines = responseBuffer.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return }

        var responses: [RA2Response] = []
        for i in 0..<(lines.count - 1) {
            let line = String(lines[i])
            if !line.isEmpty {
                responses.append(RA2Response.parse(line))
            }
        }

        responseBuffer = String(lines.last ?? "")

        // Resume any pending continuations
        for continuation in pendingResponses {
            continuation.resume(returning: responses)
        }
        pendingResponses.removeAll()
    }

    // MARK: - Public API

    func queryZoneLevel(integrationID: Int) async throws -> Double {
        try await sendCommand(.queryZoneLevel(integrationID: integrationID))
        // In a real implementation, we'd wait for the response
        // For now, return a placeholder
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        return 0.0
    }

    func setZoneLevel(integrationID: Int, level: Int, fadeTime: Double = 0.0) async throws {
        guard level >= 0 && level <= 100 else {
            throw RA2Error.invalidLevel
        }
        try await sendCommand(.setZoneLevel(integrationID: integrationID, level: level, fadeTime: fadeTime))
    }

    func activateScene(keypadID: Int, buttonNumber: Int) async throws {
        try await sendCommand(.activateScene(keypadID: keypadID, buttonNumber: buttonNumber))
    }

    func identifyZone(integrationID: Int) async throws {
        // Flash the zone by cycling 0 -> 100 -> 0
        try await setZoneLevel(integrationID: integrationID, level: 100, fadeTime: 0.5)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try await setZoneLevel(integrationID: integrationID, level: 0, fadeTime: 0.5)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try await setZoneLevel(integrationID: integrationID, level: 100, fadeTime: 0.5)
    }
}

// MARK: - Errors

enum RA2Error: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case authenticationFailed
    case invalidLevel
    case timeout
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to RadioRA 2 Main Repeater"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .authenticationFailed:
            return "Authentication failed. Check username and password."
        case .invalidLevel:
            return "Invalid level. Must be 0-100."
        case .timeout:
            return "Connection timed out"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}
