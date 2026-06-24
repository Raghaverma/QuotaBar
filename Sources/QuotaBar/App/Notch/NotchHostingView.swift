import AppKit
import SwiftUI

/// Bridges the SwiftUI hub's expanded-content height and animation lifecycle up to
/// the controller, which resizes the panel exactly twice per hover cycle — once right
/// before the open animation starts, once right after the close animation finishes —
/// rather than continuously while SwiftUI measures content mid-animation. See
/// `NotchHubController` for why: resizing the real NSPanel on every layout pass during
/// a spring animation is what produced the jitter this replaces (boring.notch avoids
/// the problem differently, by never resizing at all; QuotaBar's content is
/// variable-height per provider count, so it resizes, just only at the two instants
/// nothing is actively animating).
/// A `@MainActor` class is implicitly `Sendable`, so it is safe to capture from
/// SwiftUI's `@Sendable` preference-change closure.
@MainActor
final class NotchLayoutBridge {
    var onMeasuredExpandedHeight: ((CGFloat) -> Void)?
    var onWillExpand: (() -> Void)?
    var onDidCollapse: (() -> Void)?

    func reportExpandedHeight(_ height: CGFloat) { onMeasuredExpandedHeight?(height) }
    func willExpand() { onWillExpand?() }
    func didCollapse() { onDidCollapse?() }
}

/// Hosting view for the notch hub. `acceptsFirstMouse` lets a click register on the
/// very first press even when the panel was not yet key, so the SwiftUI buttons and
/// tap gesture inside the hub fire immediately instead of just focusing the window.
final class NotchHostingView: NSHostingView<NotchHubView> {
    required init(rootView: NotchHubView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
