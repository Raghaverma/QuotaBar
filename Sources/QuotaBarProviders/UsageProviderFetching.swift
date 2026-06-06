import Foundation

/// Stable identity for a provider, independent of concrete implementation.
public struct UsageProviderIdentity: Hashable, Sendable {
    public var rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// The minimal snapshot the scheduler/analytics layer needs — no UI concerns.
public struct UsageQuotaSnapshot: Equatable, Sendable {
    public var used: Double?
    public var limit: Double?
    public var capturedAtUnixSeconds: TimeInterval

    public init(used: Double?, limit: Double?, capturedAtUnixSeconds: TimeInterval) {
        self.used = used
        self.limit = limit
        self.capturedAtUnixSeconds = capturedAtUnixSeconds
    }
}

/// The slim fetching contract the Application layer depends on. The executable
/// bridges its richer `UsageProvider` to this via an adapter.
public protocol UsageProviderFetching: Sendable {
    var providerID: UsageProviderIdentity { get }
    func fetchUsageSnapshot(forceRefresh: Bool) async throws -> UsageQuotaSnapshot
}
