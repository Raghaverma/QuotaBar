import Foundation
import StatsUsageDomain

/// A safe stand-in for provider types not yet given a bespoke implementation. It
/// keeps the factory's "every ProviderType is registered" precondition satisfiable
/// while honestly reporting the provider as unavailable.
final class PlaceholderProvider: UsageProvider, @unchecked Sendable {
    let descriptor: ProviderDescriptor

    init(descriptor: ProviderDescriptor) {
        self.descriptor = descriptor
    }

    func fetch() async throws -> UsageSnapshot {
        UsageSnapshot(
            source: descriptor.id,
            status: .disabled,
            fetchHealth: .ok,
            valueFreshness: .empty,
            unit: "quota",
            note: "Provider not yet implemented",
            sourceLabel: "",
            diagnosticCode: "not_implemented"
        )
    }
}
