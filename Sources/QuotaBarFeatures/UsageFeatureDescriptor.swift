import Foundation
import StatsUsageDomain
import StatsUsagePresentation

/// Assembles a provider id + title into a feature descriptor, and builds the
/// summary view-state the UI consumes.
public struct UsageFeatureDescriptor: Equatable, Sendable {
    public var providerID: String
    public var title: String
    public var family: ProviderFamily

    public init(providerID: String, title: String, family: ProviderFamily) {
        self.providerID = providerID
        self.title = title
        self.family = family
    }

    /// Build the compact menu-bar entry for this feature from its snapshot.
    public func makeStatusBarEntry(snapshot: UsageSnapshot) -> StatusBarDisplayEntry {
        StatusBarDisplayPresenter.makeEntry(name: title, snapshot: snapshot)
    }
}
