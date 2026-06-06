import Foundation
import StatsUsageDomain

/// A single renderable unit in the menu bar (one provider's compact readout).
public struct StatusBarDisplayEntry: Equatable, Sendable {
    public var providerID: String
    public var name: String
    public var percentText: String
    public var remainingPercent: Double?    // numeric form for bar/ring/sparkline widgets
    public var iconName: String?
    public var isHealthy: Bool

    public init(
        providerID: String,
        name: String,
        percentText: String,
        remainingPercent: Double? = nil,
        iconName: String? = nil,
        isHealthy: Bool = true
    ) {
        self.providerID = providerID
        self.name = name
        self.percentText = percentText
        self.remainingPercent = remainingPercent
        self.iconName = iconName
        self.isHealthy = isHealthy
    }
}

/// Pure mapping from a snapshot to a menu-bar entry. Lives in Presentation so it
/// is testable without any AppKit dependency.
public enum StatusBarDisplayPresenter {
    public static func makeEntry(name: String, snapshot: UsageSnapshot) -> StatusBarDisplayEntry {
        let pct: Double? = snapshot.remainingPercent ?? snapshot.quotaWindows.first?.remainingPercent
        let pctText = pct.map { "\(Int($0.rounded()))%" } ?? "—"
        return StatusBarDisplayEntry(
            providerID: snapshot.source,
            name: name,
            percentText: pctText,
            remainingPercent: pct,
            iconName: snapshot.source,
            isHealthy: snapshot.status == .ok
        )
    }
}
