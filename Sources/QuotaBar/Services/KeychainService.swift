import Foundation
import Security
import QuotaBarInfrastructure

/// A thin wrapper over the Security framework storing per-provider secrets keyed by
/// `(service, account)` — exactly the coordinates held in `AuthConfig`. The Security
/// framework is itself thread-safe, so this holds no mutable state of its own.
final class KeychainService: CredentialStoring, @unchecked Sendable {
    init() {}

    func setSecret(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        var query = baseQuery(service: service, account: account)
        SecItemDelete(query as CFDictionary)   // replace semantics
        query[kSecValueData as String] = data
        // Restrict to this device, never included in iCloud Keychain sync or backups —
        // only matters on add; deliberately not part of baseQuery() so reads/deletes
        // still match items that predate this attribute.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.osStatus(status) }
    }

    func secret(service: String, account: String) throws -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.osStatus(status)
        }
    }

    func deleteSecret(service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    enum KeychainError: Error, LocalizedError {
        case osStatus(OSStatus)
        var errorDescription: String? {
            switch self {
            case .osStatus(let s):
                let msg = SecCopyErrorMessageString(s, nil) as String? ?? "code \(s)"
                return "Keychain error: \(msg)"
            }
        }
    }
}
