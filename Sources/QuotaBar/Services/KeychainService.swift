import Foundation
import Security
import StatsUsageInfrastructure

/// A thin wrapper over the Security framework storing per-provider secrets keyed by
/// `(service, account)` — exactly the coordinates held in `AuthConfig`. Includes an
/// optional snapshot cache so one refresh round doesn't hammer the Keychain.
final class KeychainService: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshotCache: [String: String?]?

    init() {}

    private func cacheKey(_ service: String, _ account: String) -> String { "\(service)\u{0}\(account)" }

    func setSecret(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        var query = baseQuery(service: service, account: account)
        SecItemDelete(query as CFDictionary)   // replace semantics
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.osStatus(status) }
        lock.lock(); snapshotCache?[cacheKey(service, account)] = value; lock.unlock()
    }

    func secret(service: String, account: String) throws -> String? {
        let key = cacheKey(service, account)
        lock.lock()
        if let cache = snapshotCache, let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        let result: String?
        switch status {
        case errSecSuccess:
            result = (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
        case errSecItemNotFound:
            result = nil
        default:
            throw KeychainError.osStatus(status)
        }
        lock.lock(); if snapshotCache != nil { snapshotCache?[key] = result }; lock.unlock()
        return result
    }

    func deleteSecret(service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
        lock.lock(); snapshotCache?[cacheKey(service, account)] = .some(nil); lock.unlock()
    }

    /// Begin memoizing reads for the duration of a single refresh cycle.
    func beginSnapshot() { lock.lock(); snapshotCache = [:]; lock.unlock() }
    func endSnapshot() { lock.lock(); snapshotCache = nil; lock.unlock() }

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
