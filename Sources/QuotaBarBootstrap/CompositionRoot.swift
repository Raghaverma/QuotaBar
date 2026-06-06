import Foundation
import StatsUsageDomain
import StatsUsageApplication
import StatsUsageFeatures
import StatsUsagePresentation

/// The composition root — a small façade wiring Features/Application/Presentation
/// together. The executable target owns the AppKit/SwiftUI side and talks to this.
public struct CompositionRoot {
    public let features: [UsageFeatureDescriptor]

    public init(features: [UsageFeatureDescriptor]) {
        self.features = features
    }

    /// Map a feature + its latest snapshot into a menu-bar entry.
    public func statusBarEntries(snapshots: [String: UsageSnapshot]) -> [StatusBarDisplayEntry] {
        features.compactMap { feature in
            guard let snapshot = snapshots[feature.providerID] else { return nil }
            return feature.makeStatusBarEntry(snapshot: snapshot)
        }
    }
}
