import AppKit
import SwiftUI

/// Bridges the SwiftUI hub's open/close animation lifecycle up to the controller,
/// which resizes the panel exactly twice per hover cycle — once right before the open
/// animation starts, once right after the close animation finishes — rather than
/// continuously while SwiftUI animates. See `NotchHubController` for why: resizing the
/// real NSPanel on every layout pass during a spring animation is what produced the
/// jitter this replaces (boring.notch avoids the problem differently, by never
/// resizing at all; QuotaBar's content is variable-height per provider count, so it
/// resizes, just only at the two instants nothing is actively animating).
/// A `@MainActor` class is implicitly `Sendable`, so it is safe to capture from
/// SwiftUI's `@Sendable` preference-change closure.
@MainActor
final class NotchLayoutBridge {
    var onWillExpand: (() -> Void)?
    var onDidCollapse: (() -> Void)?
    /// Set by the SwiftUI view in `.onAppear`; called by the controller's AppKit
    /// mouse-location polling loop so hover detection survives NSPanel resizes.
    var hoverHandler: ((Bool) -> Void)?

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

    // MARK: - Layout-pass re-entrancy guard
    //
    // View-level counterpart to NotchPanel's window-level guard. AppKit has been seen
    // logging "It's not legal to call -layoutSubtreeIfNeeded on a view which is already
    // being laid out" from this view during the open/close animation — the same
    // SwiftUI-animation-driven re-entrancy that caused the original NSGenericException
    // crash, just caught by a (currently non-fatal) assertion instead. AppKit's own
    // message warns "this may break in the future," so guard it the same way: drop
    // re-entrant calls that arrive while a layout pass for this view is already running.

    private var isInLayout = false

    override func layoutSubtreeIfNeeded() {
        guard !isInLayout else { return }
        isInLayout = true
        defer { isInLayout = false }
        super.layoutSubtreeIfNeeded()
    }
}
