import Foundation
import Security

/// Minimal Keychain wrapper for storing the GitHub token.
enum Keychain {
    static let service = "dev.8air.Gauge"
    static let githubToken = "github-token"
    /// Set only after the user saves a token, so we never touch the Keychain (and trigger macOS password
    /// prompts, which reappear after each ad-hoc-signed rebuild) unless there is something stored.
    private static let flagKey = "keychainHasToken"
    private static var cache: [String: String] = [:]

    @discardableResult
    static func save(_ value: String, for account: String) -> Bool {
        delete(account)
        guard !value.isEmpty else { return true }
        UserDefaults.standard.set(true, forKey: flagKey)
        cache[account] = value
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(_ account: String) -> String? {
        if let c = cache[account] { return c }
        guard UserDefaults.standard.bool(forKey: flagKey) else { return nil }
        defer { if let v = cache[account], v.isEmpty { cache[account] = nil } }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)
        if let value { cache[account] = value }
        return value
    }

    static func delete(_ account: String) {
        cache[account] = nil
        UserDefaults.standard.set(false, forKey: flagKey)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
