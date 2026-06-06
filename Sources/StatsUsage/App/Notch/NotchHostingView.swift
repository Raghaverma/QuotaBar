import AppKit
import SwiftUI

/// Bridges the SwiftUI hub's measured size up to the controller, which resizes the
/// panel to fit exactly. Sizing the window to the island (rather than a large fixed
/// footprint) means there is never a transparent dead zone over other apps — clicks
/// outside the island land on whatever is beneath, with no mouse-passthrough tricks.
/// A `@MainActor` class is implicitly `Sendable`, so it is safe to capture from
/// SwiftUI's `@Sendable` preference-change closure.
@MainActor
final class NotchLayoutBridge {
    var onSizeChange: ((CGSize) -> Void)?

    func report(_ size: CGSize) {
        onSizeChange?(size)
    }
}

/// Hosting view for the notch hub. `acceptsFirstMouse` lets a click register on the
/// very first press even when the panel was not yet key, so the SwiftUI buttons and
/// tap gesture inside the hub fire immediately instead of just focusing the window.
///
/// `layout()` measures the unconstrained SwiftUI content size via `sizeThatFits` and
/// fires `onLayout` so the panel can expand before the first animation frame commits.
/// This prevents the `.move(edge: .top)` insertion transition from sliding the
/// expanded body out the bottom of a still-collapsed panel window.
final class NotchHostingView: NSHostingView<NotchHubView> {
    var onLayout: ((CGSize) -> Void)?

    private var measuringSize = false

    required init(rootView: NotchHubView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        guard !measuringSize else { return }
        measuringSize = true
        let ideal = sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude,
                                        height: CGFloat.greatestFiniteMagnitude))
        measuringSize = false
        guard ideal.width > 1, ideal.height > 1 else { return }
        onLayout?(ideal)
    }
}
