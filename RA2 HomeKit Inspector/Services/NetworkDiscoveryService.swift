import Foundation
import Network

// MARK: - Discovered Device

struct DiscoveredDevice: Identifiable, Hashable {
    let id = UUID()
    let ipAddress: String
    let port: UInt16
    let isLutron: Bool
    let responseText: String?

    var displayName: String {
        if isLutron {
            return "Lutron Repeater (\(ipAddress))"
        }
        return "Unknown Device (\(ipAddress))"
    }
}

// MARK: - Network Discovery Service

actor NetworkDiscoveryService {
    private var isScanning = false
    private var discoveredDevices: [DiscoveredDevice] = []

    // MARK: - Get Local Network Info

    func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }

        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            // Check for IPv4
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)

                // Skip loopback
                if name == "lo0" { continue }

                // Prefer en0 (WiFi) or en1 (Ethernet)
                if name.hasPrefix("en") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostname)

                    // Prefer 192.168.x.x addresses
                    if address?.hasPrefix("192.168") == true {
                        break
                    }
                }
            }
        }

        return address
    }

    func getNetworkPrefix() -> String? {
        guard let localIP = getLocalIPAddress() else { return nil }

        // Extract first 3 octets (assumes /24 network)
        let components = localIP.split(separator: ".")
        guard components.count == 4 else { return nil }

        return "\(components[0]).\(components[1]).\(components[2])"
    }

    // MARK: - Network Scanning

    func scanForLutronDevices(progressHandler: @escaping (Int, Int) -> Void) async -> [DiscoveredDevice] {
        guard !isScanning else { return [] }
        isScanning = true
        discoveredDevices = []

        defer { isScanning = false }

        guard let prefix = getNetworkPrefix() else {
            return []
        }

        // Common IP addresses to check first (typical static IPs for repeaters)
        let priorityAddresses = [
            "\(prefix).1",    // Often the router, but worth checking
            "\(prefix).2",
            "\(prefix).10",
            "\(prefix).100",
            "\(prefix).101",
            "\(prefix).200",
            "\(prefix).254"
        ]

        // Generate full range
        var allAddresses = priorityAddresses
        for i in 1...254 {
            let addr = "\(prefix).\(i)"
            if !priorityAddresses.contains(addr) {
                allAddresses.append(addr)
            }
        }

        let totalAddresses = allAddresses.count
        var scannedCount = 0

        // Scan in batches for better performance
        let batchSize = 20

        for batch in stride(from: 0, to: allAddresses.count, by: batchSize) {
            let endIndex = min(batch + batchSize, allAddresses.count)
            let batchAddresses = Array(allAddresses[batch..<endIndex])

            await withTaskGroup(of: DiscoveredDevice?.self) { group in
                for address in batchAddresses {
                    group.addTask {
                        await self.checkForLutronDevice(at: address, port: 23)
                    }
                }

                for await result in group {
                    scannedCount += 1
                    progressHandler(scannedCount, totalAddresses)

                    if let device = result {
                        discoveredDevices.append(device)
                    }
                }
            }

            // Early exit if we found a Lutron device
            if discoveredDevices.contains(where: { $0.isLutron }) {
                break
            }
        }

        return discoveredDevices.sorted { $0.isLutron && !$1.isLutron }
    }

    private func checkForLutronDevice(at address: String, port: UInt16) async -> DiscoveredDevice? {
        let timeout: TimeInterval = 1.0

        return await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(address),
                port: NWEndpoint.Port(rawValue: port)!
            )

            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            let connection = NWConnection(to: endpoint, using: parameters)
            var hasResumed = false
            var responseData = Data()

            let timeoutWork = DispatchWorkItem {
                if !hasResumed {
                    hasResumed = true
                    connection.cancel()
                    continuation.resume(returning: nil)
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Connection succeeded, try to read response
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { content, _, _, _ in
                        timeoutWork.cancel()

                        if let data = content {
                            responseData.append(data)
                        }

                        let responseText = String(data: responseData, encoding: .utf8) ?? ""
                        let isLutron = responseText.lowercased().contains("login") ||
                                       responseText.lowercased().contains("lutron") ||
                                       responseText.lowercased().contains("gnet")

                        if !hasResumed {
                            hasResumed = true
                            connection.cancel()
                            continuation.resume(returning: DiscoveredDevice(
                                ipAddress: address,
                                port: port,
                                isLutron: isLutron,
                                responseText: responseText.isEmpty ? nil : responseText
                            ))
                        }
                    }

                case .failed, .cancelled:
                    timeoutWork.cancel()
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: nil)
                    }

                default:
                    break
                }
            }

            connection.start(queue: .global())
        }
    }

    // MARK: - Quick Check

    func quickCheckAddress(_ address: String, port: UInt16 = 23) async -> DiscoveredDevice? {
        return await checkForLutronDevice(at: address, port: port)
    }
}
