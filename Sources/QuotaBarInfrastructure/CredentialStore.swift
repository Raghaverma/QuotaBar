import Foundation
import StatsUsageDomain

/// A credential-store seam. The executable provides a Keychain-backed conformer;
/// tests provide an in-memory one. Keeps the secret-access boundary explicit.
public protocol CredentialStoring: Sendable {
    func secret(service: String, account: String) throws -> String?
    func setSecret(_ value: String, service: String, account: String) throws
    func deleteSecret(service: String, account: String) throws
}

public extension CredentialStoring {
    /// Resolve a secret from an `AuthConfig`'s coordinates, if present.
    func secret(for auth: AuthConfig) throws -> String? {
        guard let service = auth.keychainService, let account = auth.keychainAccount else { return nil }
        return try secret(service: service, account: account)
    }
}

/// A simple lock-guarded in-memory store, handy for previews and tests.
public final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()
    public init() {}

    private func key(_ service: String, _ account: String) -> String { "\(service)\u{0}\(account)" }

    public func secret(service: String, account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key(service, account)]
    }
    public func setSecret(_ value: String, service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key(service, account)] = value
    }
    public func deleteSecret(service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key(service, account)] = nil
    }
}
