import AppKit

/// A borderless panel that floats above everything (including the menu bar) on all
/// Spaces — the host for the notch hub. It is sized to exactly fit the island, so the
/// window only ever covers the visible hub and never blocks clicks elsewhere. Uses
/// public AppKit APIs only (no private SkyLight/CGSSpace), so it stays App Store-safe.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        // The panel is sized to the island, so it never covers anything else — clicks
        // outside it reach the apps beneath naturally, no passthrough tricks needed.
        ignoresMouseEvents = false
    }

    // Borderless windows are non-key by default; opt in so the SwiftUI buttons and tap
    // gesture inside the hub receive clicks and fire.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Layout-pass re-entrancy guard
    //
    // During NSWindow.layoutIfNeeded, AppKit posts NSWindowDidLayoutNotification.
    // SwiftUI's NSHostingView observes this and calls updateAnimatedWindowSize, which
    // calls panel.setFrame(...) to chase the content's animated size. But calling
    // setFrame from inside layoutIfNeeded triggers setFrameSize on NSNextStepFrame,
    // which fires KVO, which calls invalidateSafeAreaInsets → setNeedsUpdateConstraints
    // while a constraint pass is already running — AppKit throws NSGenericException.
    // Fix: suppress setFrame calls that arrive while layoutIfNeeded is on the call stack.
    // NotchHubController already sets the frame to the correct target size (expanded or
    // collapsed) at the two instants around the animation; SwiftUI's mid-animation
    // resize attempts are redundant and safe to drop.

    private var isInLayout = false

    override func layoutIfNeeded() {
        isInLayout = true
        defer { isInLayout = false }
        super.layoutIfNeeded()
    }

    override func setFrame(_ frameRect: NSRect, display: Bool) {
        guard !isInLayout else { return }
        super.setFrame(frameRect, display: display)
    }

    override func setFrame(_ frameRect: NSRect, display: Bool, animate: Bool) {
        guard !isInLayout else { return }
        super.setFrame(frameRect, display: display, animate: animate)
    }
}
