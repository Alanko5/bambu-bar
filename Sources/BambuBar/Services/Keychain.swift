import Foundation
import Security

/// The printer's LAN access code, kept in the login keychain per serial number.
enum Keychain {
    private static let service = "dev.rolottr.BambuBar.access-code"

    static func accessCode(for serial: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serial,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setAccessCode(_ code: String, for serial: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serial,
        ]
        let data = Data(code.utf8)
        if SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Bambu Bar printer access code"
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func removeAccessCode(for serial: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serial,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
