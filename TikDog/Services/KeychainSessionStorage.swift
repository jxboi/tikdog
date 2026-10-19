import Foundation
import Security
import TikDogCore

struct KeychainSessionStorage: SessionStorage {
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.tikdog.session", kSecAttrAccount as String: "supabase"] }
    func load() throws -> AuthSession? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw TikDogError.server("Couldn't read your secure session.") }
        return try JSONDecoder().decode(AuthSession.self, from: data)
    }
    func save(_ session: AuthSession?) throws {
        guard let session else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw TikDogError.server("Couldn't remove your secure session. Please retry.") }
            return
        }
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw TikDogError.server("Couldn't save your secure session.") }; return
        }
        guard status == errSecSuccess else { throw TikDogError.server("Couldn't update your secure session.") }
    }
}
