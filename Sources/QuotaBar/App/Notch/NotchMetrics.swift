import CoreGraphics

/// The single set of layout numbers shared by the AppKit controller (which sizes the
/// window) and the SwiftUI view (which lays out inside it). Because the window is sized
/// from `panelHeight(providerCount:)` and the view builds its content from the *same*
/// constants, the window is always exactly tall enough — no clipping, no dead gap, and
/// crucially no per-frame height measurement to fight the animation.
struct NotchMetrics: Equatable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var expandedWidth: CGFloat
    /// Height of the expanded panel *below* the notch. Matches `panelHeight(providerCount:)`.
    var panelHeight: CGFloat

    // Expanded-panel layout constants. Kept here (not scattered in the view) so the
    // window-sizing math and the SwiftUI layout are provably in sync.
    static let topPadding: CGFloat = 10
    static let headerHeight: CGFloat = 26
    static let headerGap: CGFloat = 12
    static let rowHeight: CGFloat = 58
    static let emptyStateHeight: CGFloat = 44
    static let footerGap: CGFloat = 12
    static let footerHeight: CGFloat = 30
    static let bottomPadding: CGFloat = 14

    /// Total height of the expanded panel for a given number of enabled providers.
    /// Deliberately errs a hair tall rather than short.
    static func panelHeight(providerCount: Int) -> CGFloat {
        let rows = providerCount > 0
            ? CGFloat(providerCount) * rowHeight
            : emptyStateHeight
        return topPadding + headerHeight + headerGap + rows
            + footerGap + footerHeight + bottomPadding
    }
}
