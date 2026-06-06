import Foundation
import StatsUsageDomain

/// Source mode for an official provider.
enum OfficialSourceMode: String, Codable, CaseIterable, Sendable {
    case api, cli, web, auto

    var title: String {
        switch self {
        case .api: return "Official API"
        case .cli: return "Local CLI"
        case .web: return "Web"
        case .auto: return "Automatic"
        }
    }
}

/// Config for an official (first-party) provider.
struct OfficialProviderConfig: Codable, Equatable, Sendable {
    var sourceMode: OfficialSourceMode
    var accountEmail: String?
    var allowCredentialFileUpdates: Bool

    init(
        sourceMode: OfficialSourceMode = .auto,
        accountEmail: String? = nil,
        allowCredentialFileUpdates: Bool = false
    ) {
        self.sourceMode = sourceMode
        self.accountEmail = accountEmail
        self.allowCredentialFileUpdates = allowCredentialFileUpdates
    }

    static func `default`(type: ProviderType) -> OfficialProviderConfig {
        OfficialProviderConfig(sourceMode: .auto)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceMode = try c.decodeIfPresent(OfficialSourceMode.self, forKey: .sourceMode) ?? .auto
        accountEmail = try c.decodeIfPresent(String.self, forKey: .accountEmail)
        allowCredentialFileUpdates = try c.decodeIfPresent(Bool.self, forKey: .allowCredentialFileUpdates) ?? false
    }
}

/// Credential acquisition strategy preference for relay providers.
enum CredentialStrategyPreference: String, Codable, Sendable {
    case manualPreferred, browserPreferred, browserOnly
}

/// Config for a relay (third-party NewAPI-style) provider.
struct RelayProviderConfig: Codable, Equatable, Sendable {
    var adapterID: String           // which manifest drives this site
    var baseURL: String
    var userID: String?
    var groupID: String?
    var strategy: CredentialStrategyPreference

    init(
        adapterID: String = "generic-newapi",
        baseURL: String = "",
        userID: String? = nil,
        groupID: String? = nil,
        strategy: CredentialStrategyPreference = .manualPreferred
    ) {
        self.adapterID = adapterID
        self.baseURL = baseURL
        self.userID = userID
        self.groupID = groupID
        self.strategy = strategy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        adapterID = try c.decodeIfPresent(String.self, forKey: .adapterID) ?? "generic-newapi"
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        userID = try c.decodeIfPresent(String.self, forKey: .userID)
        groupID = try c.decodeIfPresent(String.self, forKey: .groupID)
        strategy = try c.decodeIfPresent(CredentialStrategyPreference.self, forKey: .strategy) ?? .manualPreferred
    }
}

/// Config for the Kimi provider (kept as a distinct sub-config example).
struct KimiProviderConfig: Codable, Equatable, Sendable {
    var endpoint: String?
    init(endpoint: String? = nil) { self.endpoint = endpoint }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint)
    }
}

/// The full configured-provider record in the executable target.
struct ProviderDescriptor: Codable, Equatable, Identifiable, Sendable {
    enum ImplementationStatus: String {
        case implemented = "Implemented"
        case experimental = "Experimental"
        case unavailable = "Unavailable"
    }
    var id: String
    var name: String
    var family: ProviderFamily
    var type: ProviderType
    var enabled: Bool
    var pollIntervalSec: Int
    var threshold: AlertRule
    var auth: AuthConfig
    var showInMenuBar: Bool?
    var baseURL: String?
    var officialConfig: OfficialProviderConfig?
    var relayConfig: RelayProviderConfig?
    var kimiConfig: KimiProviderConfig?

    init(
        id: String,
        name: String,
        family: ProviderFamily,
        type: ProviderType,
        enabled: Bool = true,
        pollIntervalSec: Int = 300,
        threshold: AlertRule = .default,
        auth: AuthConfig = .none,
        showInMenuBar: Bool? = nil,
        baseURL: String? = nil,
        officialConfig: OfficialProviderConfig? = nil,
        relayConfig: RelayProviderConfig? = nil,
        kimiConfig: KimiProviderConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.type = type
        self.enabled = enabled
        self.pollIntervalSec = pollIntervalSec
        self.threshold = threshold
        self.auth = auth
        self.showInMenuBar = showInMenuBar
        self.baseURL = baseURL
        self.officialConfig = officialConfig
        self.relayConfig = relayConfig
        self.kimiConfig = kimiConfig
    }

    var showsInMenuBar: Bool { showInMenuBar ?? true }
    var isRelay: Bool { type == .relay || type == .open || type == .dragon }
    var implementationStatus: ImplementationStatus {
        switch type {
        case .codex, .claude, .gemini: return .experimental
        case .relay, .open, .dragon: return .implemented
        default: return .unavailable
        }
    }
    var supportedOfficialSourceModes: [OfficialSourceMode] {
        switch type {
        case .claude: return [.auto, .api, .cli]
        case .codex, .gemini: return [.auto, .api]
        default: return []
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        family = try c.decodeIfPresent(ProviderFamily.self, forKey: .family) ?? .official
        type = try c.decode(ProviderType.self, forKey: .type)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        pollIntervalSec = try c.decodeIfPresent(Int.self, forKey: .pollIntervalSec) ?? 300
        threshold = try c.decodeIfPresent(AlertRule.self, forKey: .threshold) ?? .default
        auth = try c.decodeIfPresent(AuthConfig.self, forKey: .auth) ?? .none
        showInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showInMenuBar)
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL)
        officialConfig = try c.decodeIfPresent(OfficialProviderConfig.self, forKey: .officialConfig)
        relayConfig = try c.decodeIfPresent(RelayProviderConfig.self, forKey: .relayConfig)
        kimiConfig = try c.decodeIfPresent(KimiProviderConfig.self, forKey: .kimiConfig)
    }
}
