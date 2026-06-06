import Foundation

/// The JSON manifest describing a NewAPI-style relay site. One generic
/// `RelayProvider` interprets any manifest, so onboarding a site is data, not code.
struct RelayAdapterManifest: Codable, Equatable, Sendable {
    struct Match: Codable, Equatable, Sendable {
        var hostPatterns: [String]
        var defaultBalanceChannelEnabled: Bool?
    }
    struct Setup: Codable, Equatable, Sendable {
        var requiredInputs: [String]
    }
    struct AuthStrategy: Codable, Equatable, Sendable {
        var kind: String   // savedBearer, browserBearer, savedCookieHeader, browserCookieHeader
    }
    struct BalanceRequest: Codable, Equatable, Sendable {
        var method: String
        var path: String
        var authHeader: String?
        var authScheme: String?
        var userIDHeader: String?
    }
    struct TokenRequest: Codable, Equatable, Sendable {
        var usagePath: String?
        var subscriptionPath: String?
        var billingUsagePath: String?
    }
    struct Extract: Codable, Equatable, Sendable {
        var success: String?
        var remaining: String?
        var used: String?
        var limit: String?
        var unit: String?
        var accountLabel: String?
    }

    var id: String
    var displayName: String
    var match: Match
    var setup: Setup
    var authStrategies: [AuthStrategy]
    var balanceRequest: BalanceRequest
    var tokenRequest: TokenRequest?
    var extract: Extract
    var postprocessID: String?
}
