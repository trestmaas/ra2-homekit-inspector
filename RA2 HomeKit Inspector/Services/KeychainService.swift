import Foundation
import Security

// MARK: - Keychain Service

struct KeychainService {
    private static let serviceName = "com.ra2homekitinspector"

    enum KeychainError: LocalizedError {
        case duplicateItem
        case itemNotFound
        case unexpectedStatus(OSStatus)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .duplicateItem:
                return "Item already exists in keychain"
            case .itemNotFound:
                return "Item not found in keychain"
            case .unexpectedStatus(let status):
                return "Keychain error: \(status)"
            case .invalidData:
                return "Invalid data format"
            }
        }
    }

    // MARK: - Save Credentials

    static func saveCredentials(host: String, username: String, password: String) throws {
        let account = "\(username)@\(host)"

        guard let passwordData = password.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        // Try to delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Retrieve Credentials

    static func retrieveCredentials(host: String, username: String) throws -> String {
        let account = "\(username)@\(host)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return password
    }

    // MARK: - Delete Credentials

    static func deleteCredentials(host: String, username: String) throws {
        let account = "\(username)@\(host)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Check if Credentials Exist

    static func credentialsExist(host: String, username: String) -> Bool {
        let account = "\(username)@\(host)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}

// MARK: - User Defaults Keys

enum SettingsKeys {
    static let repeaterHost = "ra2_repeater_host"
    static let repeaterPort = "ra2_repeater_port"
    static let repeaterUsername = "ra2_repeater_username"
    static let autoConnectOnLaunch = "auto_connect_on_launch"
    static let lastSelectedHome = "last_selected_home"
}

// MARK: - Settings Manager

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var repeaterHost: String {
        didSet {
            UserDefaults.standard.set(repeaterHost, forKey: SettingsKeys.repeaterHost)
        }
    }

    @Published var repeaterPort: Int {
        didSet {
            UserDefaults.standard.set(repeaterPort, forKey: SettingsKeys.repeaterPort)
        }
    }

    @Published var repeaterUsername: String {
        didSet {
            UserDefaults.standard.set(repeaterUsername, forKey: SettingsKeys.repeaterUsername)
        }
    }

    @Published var autoConnectOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(autoConnectOnLaunch, forKey: SettingsKeys.autoConnectOnLaunch)
        }
    }

    private init() {
        self.repeaterHost = UserDefaults.standard.string(forKey: SettingsKeys.repeaterHost) ?? ""
        let storedPort = UserDefaults.standard.integer(forKey: SettingsKeys.repeaterPort)
        self.repeaterPort = storedPort == 0 ? 23 : storedPort
        self.repeaterUsername = UserDefaults.standard.string(forKey: SettingsKeys.repeaterUsername) ?? "lutron"
        self.autoConnectOnLaunch = UserDefaults.standard.bool(forKey: SettingsKeys.autoConnectOnLaunch)
    }

    var hasCredentials: Bool {
        !repeaterHost.isEmpty && KeychainService.credentialsExist(host: repeaterHost, username: repeaterUsername)
    }

    func savePassword(_ password: String) throws {
        guard !repeaterHost.isEmpty else { return }
        try KeychainService.saveCredentials(host: repeaterHost, username: repeaterUsername, password: password)
    }

    func retrievePassword() -> String? {
        guard !repeaterHost.isEmpty else { return nil }
        return try? KeychainService.retrieveCredentials(host: repeaterHost, username: repeaterUsername)
    }
}
