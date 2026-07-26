import Foundation
import QuotaBarDomain

/// The contract every concrete provider implements — the seam the factory and
/// scheduler talk to.
protocol UsageProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func fetch() async throws -> UsageSnapshot
    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot
}

extension UsageProvider {
    /// Default: ignore `forceRefresh` unless the provider overrides it.
    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot { try await fetch() }
}

/// Normalized provider errors → consistent, user-readable diagnostics.
enum ProviderError: Error, LocalizedError {
    case missingCredential(String)
    case unauthorized
    case unauthorizedDetail(String)
    case rateLimited
    case invalidResponse(String)
    case commandFailed(String)
    case timeout(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingCredential(let what): return "Missing credential: \(what)."
        case .unauthorized: return "Authentication failed — please re-authorize."
        case .unauthorizedDetail(let detail): return "Authentication failed: \(detail)."
        case .rateLimited: return "Rate limited — try again later."
        case .invalidResponse(let detail): return "Unexpected response: \(detail)."
        case .commandFailed(let detail): return "Command failed: \(detail)."
        case .timeout(let detail): return "Timed out: \(detail)."
        case .unavailable(let detail): return "Unavailable: \(detail)."
        }
    }

    /// Map this error to a `FetchHealth` so snapshots stay diagnostic-friendly.
    var fetchHealth: FetchHealth {
        switch self {
        case .unauthorized, .unauthorizedDetail, .missingCredential: return .authExpired
        case .rateLimited: return .rateLimited
        case .invalidResponse: return .endpointMisconfigured
        case .commandFailed, .timeout, .unavailable: return .unreachable
        }
    }
}
