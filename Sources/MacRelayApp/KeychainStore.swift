import Foundation
import MacRelayCore
import Security

enum KeychainStore {
    private static let service = "org.macrelay.MacRelay.pairing.v1"
    static func read(_ account: String) throws -> PairingKey? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
            let code = String(data: data, encoding: .utf8)
        else { throw StoreError.unavailable }
        return try PairingKey(code: code)
    }
    static func save(_ key: PairingKey, account: String) throws {
        let query = baseQuery(account)
        let data = Data(key.code.utf8)
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(query as CFDictionary, update)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let result = SecItemAdd(add as CFDictionary, nil)
            guard result == errSecSuccess else { throw StoreError.unavailable }
        } else if status != errSecSuccess {
            throw StoreError.unavailable
        }
    }
    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false,
        ]
    }
    enum StoreError: LocalizedError {
        case unavailable
        var errorDescription: String? { "MacRelay could not access its local pairing key in Keychain." }
    }
}
