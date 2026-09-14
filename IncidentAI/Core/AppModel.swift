import Foundation
import IncidentCore
import Observation
import OSLog
import Security

protocol Telemetry: Sendable {
    func record(_ event: String)
    func failure(_ error: Error, operation: String)
}

struct LocalTelemetry: Telemetry {
    private let logger = Logger(subsystem: "com.erykszczesniak.IncidentAI", category: "operations")
    func record(_ event: String) {
        logger.info("Operation: \(event, privacy: .public)")
    }

    func failure(_ error: Error, operation: String) {
        logger.error("Operation failed: \(operation, privacy: .public), type: \(String(describing: type(of: error)), privacy: .public)")
    }
}

enum KeychainStore {
    static let service = "com.erykszczesniak.IncidentAI"
    static func read() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "api-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var item = query
            for (key, value) in attributes {
                item[key] = value
            }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw APIError.server("Could not securely save your API key.") }
        } else if result != errSecSuccess {
            throw APIError.server("Could not update your API key in Keychain.")
        }
    }
}

@MainActor @Observable final class AppModel {
    var api: any IncidentAPI
    var isDemo: Bool
    var serverURL: String
    var revision = UUID()
    var selectedIncidentID: UUID?
    var notificationMessage: String?
    let telemetry: any Telemetry = LocalTelemetry()

    init() {
        #if DEBUG
            let launchURL = ProcessInfo.processInfo.environment["INCIDENT_AI_LIVE_URL"]
            let launchKey = ProcessInfo.processInfo.environment["INCIDENT_AI_API_KEY"]
        #else
            let launchURL: String? = nil
            let launchKey: String? = nil
        #endif
        let savedURL = launchURL ?? UserDefaults.standard.string(forKey: "serverURL") ?? "http://127.0.0.1:8000"
        let useDemo = launchURL == nil && !UserDefaults.standard.bool(forKey: "liveMode")
        serverURL = savedURL
        isDemo = useDemo
        if !useDemo, let url = URL(string: savedURL), let live = try? LiveAPIClient(baseURL: url, apiKey: launchKey ?? KeychainStore.read()) {
            api = live
        } else {
            api = MockAPIClient(); isDemo = true
        }
    }

    func configure(demo: Bool, url: String, key: String) throws {
        if demo {
            api = MockAPIClient()
        } else {
            guard let base = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw APIError.invalidURL }
            let client = try LiveAPIClient(baseURL: base, apiKey: key)
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidInput("Enter your API key to connect.") }
            try KeychainStore.save(key)
            api = client
        }
        isDemo = demo
        serverURL = url
        UserDefaults.standard.set(url, forKey: "serverURL")
        UserDefaults.standard.set(!demo, forKey: "liveMode")
        revision = UUID()
        telemetry.record(demo ? "demo_enabled" : "live_enabled")
    }
}
