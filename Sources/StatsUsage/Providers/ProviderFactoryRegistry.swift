import Foundation
import StatsUsageDomain

/// Maps each `ProviderType` to a closure that builds the concrete provider,
/// injecting shared dependencies. A `precondition` asserts every case is registered
/// so adding an enum case without wiring it is a loud crash in tests, not a silent gap.
struct ProviderFactoryRegistry {
    struct Dependencies {
        let keychain: KeychainService
        let relayRegistry: RelayAdapterRegistry
    }

    typealias Maker = @Sendable (ProviderDescriptor, Dependencies) -> UsageProvider
    private let makers: [ProviderType: Maker]

    init(makers: [ProviderType: Maker] = Self.makeDefaultMakers()) {
        self.makers = makers
        precondition(
            Set(makers.keys) == Set(ProviderType.allCases),
            "Every ProviderType must be registered in the factory"
        )
    }

    func makeProvider(for descriptor: ProviderDescriptor, dependencies: Dependencies) -> UsageProvider {
        makers[descriptor.type]!(descriptor, dependencies)
    }

    static func makeDefaultMakers() -> [ProviderType: Maker] {
        let relay: Maker = { d, deps in
            RelayProvider(descriptor: d, registry: deps.relayRegistry, keychain: deps.keychain)
        }
        let placeholder: Maker = { d, _ in PlaceholderProvider(descriptor: d) }

        var makers: [ProviderType: Maker] = [
            .codex: { d, deps in CodexProvider(descriptor: d, keychain: deps.keychain) },
            .claude: { d, _ in ClaudeProvider(descriptor: d) },
            .gemini: { d, _ in GeminiProvider(descriptor: d) },
            .relay: relay,
            .open: relay,
            .dragon: relay
        ]
        // Register the remaining types against the honest placeholder so the
        // precondition holds; bespoke implementations replace these over time.
        for type in ProviderType.allCases where makers[type] == nil {
            makers[type] = placeholder
        }
        return makers
    }
}
