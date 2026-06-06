import Foundation

/// The closed set of provider kinds the app knows how to build.
public enum ProviderType: String, Codable, CaseIterable, Sendable {
    case codex, claude, gemini, copilot, microsoftCopilot, zai, amp, cursor,
         jetbrains, kiro, windsurf, trae, openrouterCredits, openrouterAPI,
         ollamaCloud, opencodeGo, relay, open, dragon, kimi
}

public enum ProviderFamily: String, Codable, CaseIterable, Sendable {
    case official, thirdParty
}

public enum AuthKind: String, Codable, Sendable {
    case none, bearer, localCodex
}

/// Holds *coordinates* to a secret, never the secret itself.
public struct AuthConfig: Codable, Equatable, Sendable {
    public var kind: AuthKind
    public var keychainService: String?
    public var keychainAccount: String?

    public init(kind: AuthKind, keychainService: String? = nil, keychainAccount: String? = nil) {
        self.kind = kind
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
    }

    public static let none = AuthConfig(kind: .none)

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(AuthKind.self, forKey: .kind) ?? .none
        keychainService = try c.decodeIfPresent(String.self, forKey: .keychainService)
        keychainAccount = try c.decodeIfPresent(String.self, forKey: .keychainAccount)
    }
}

/// When/how the app should notify the user about a provider's state.
public struct AlertRule: Codable, Equatable, Sendable {
    public var lowRemaining: Double         // notify below this %
    public var maxConsecutiveFailures: Int  // notify after N failed refreshes
    public var notifyOnAuthError: Bool

    public init(lowRemaining: Double = 10, maxConsecutiveFailures: Int = 3, notifyOnAuthError: Bool = true) {
        self.lowRemaining = lowRemaining
        self.maxConsecutiveFailures = maxConsecutiveFailures
        self.notifyOnAuthError = notifyOnAuthError
    }

    public static let `default` = AlertRule()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lowRemaining = try c.decodeIfPresent(Double.self, forKey: .lowRemaining) ?? 10
        maxConsecutiveFailures = try c.decodeIfPresent(Int.self, forKey: .maxConsecutiveFailures) ?? 3
        notifyOnAuthError = try c.decodeIfPresent(Bool.self, forKey: .notifyOnAuthError) ?? true
    }
}
