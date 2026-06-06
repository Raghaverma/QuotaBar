import Foundation
import StatsUsageDomain

/// Seeds the default set of providers for a fresh install. Kept additive so new
/// app versions can introduce providers without disturbing existing configs.
enum ProviderDefaultCatalog {
    static func seedProviders() -> [ProviderDescriptor] {
        [
            ProviderDescriptor(
                id: "codex",
                name: "Codex",
                family: .official,
                type: .codex,
                enabled: true,
                pollIntervalSec: 300,
                auth: AuthConfig(kind: .localCodex),
                officialConfig: OfficialProviderConfig(sourceMode: .auto)
            ),
            ProviderDescriptor(
                id: "claude",
                name: "Claude",
                family: .official,
                type: .claude,
                enabled: true,
                pollIntervalSec: 300,
                auth: AuthConfig(kind: .localCodex),
                officialConfig: OfficialProviderConfig(sourceMode: .auto)
            ),
            ProviderDescriptor(
                id: "gemini",
                name: "Gemini",
                family: .official,
                type: .gemini,
                enabled: false,
                pollIntervalSec: 300,
                officialConfig: OfficialProviderConfig(sourceMode: .api)
            )
        ]
    }
}
