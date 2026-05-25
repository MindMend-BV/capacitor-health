import Foundation
import Security

final class BackgroundHealthPreferences {
    private let service = "capgo_health_background_sync"
    private let account = "background_sync_config"

    func getConfig() -> BackgroundSyncConfig? {
        guard let data = readKeychainData() else { return nil }
        do {
            return try JSONDecoder().decode(BackgroundSyncConfig.self, from: data)
        } catch {
            NSLog("[BackgroundHealthPrefs] Unable to decode background sync config: \(error)")
            return nil
        }
    }

    func requireConfig() throws -> BackgroundSyncConfig {
        guard let config = getConfig() else {
            throw NSError(
                domain: "BackgroundHealthSync",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Background sync is not configured."]
            )
        }
        return config
    }

    func saveConfig(_ config: BackgroundSyncConfig) throws {
        let data = try JSONEncoder().encode(config)
        try writeKeychainData(data)
    }

    func setEnabled(_ enabled: Bool) {
        guard var config = getConfig() else { return }
        config.enabled = enabled
        try? saveConfig(config)
    }

    func clearConfiguration() {
        deleteKeychainItem()
    }

    private func readKeychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return data
    }

    private func writeKeychainData(_ data: Data) throws {
        deleteKeychainItem()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: "BackgroundHealthSync",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to persist background sync config (status \(status))."]
            )
        }
    }

    private func deleteKeychainItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
