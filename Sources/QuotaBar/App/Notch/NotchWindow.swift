import AppKit

/// A borderless, transparent, always-on-top panel that hosts the notch island.
///
/// Unlike the previous design, this window is created once at a **fixed size** (large
/// enough for the fully-expanded panel) and is *never resized*. All growth/shrink is a
/// pure-SwiftUI animation inside a canvas that is already big enough, so:
///   • there is no `setFrame`-during-animation jitter,
///   • there is no AppKit layout re-entrancy to guard against, and
///   • `NSTrackingArea`s stay valid for the window's whole lifetime.
///
/// A big fixed window would otherwise sit as an invisible click-blocking slab over
/// whatever is beneath it. `NotchContainerView.hitTest` is *not* enough to prevent that:
/// hit-testing only decides which view inside this window handles an event, and by then
/// the window server has already routed the click here because the frame contains the
/// point. Returning `nil` makes the click vanish — it is never re-routed to the app
/// underneath. Only `ignoresMouseEvents` makes a region genuinely transparent across
/// process boundaries, so `NotchController` toggles it as the cursor enters and leaves
/// the visible island. The window therefore starts in the pass-through state.
/// Public AppKit only; App Store-safe.
final class NotchWindow: NSPanel {
    init(contentRect: NSRect, container: NotchContainerView) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
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
        isMovableByWindowBackground = false
        isMovable = false
        // We want mouse-moved/entered/exited from our tracking area even while another
        // app is active and the panel is not key.
        acceptsMouseMovedEvents = true
        // Start transparent to clicks; the controller turns this off only while the
        // cursor is actually over the visible island.
        ignoresMouseEvents = true
        contentView = container
    }

    // Borderless panels are non-key by default. Opt in so the SwiftUI buttons and the
    // tap-to-open-settings gesture inside the visible island receive their clicks — but
    // never become *main*, so focusing the island doesn't steal the user's active app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Content view for `NotchWindow`. Hosts the SwiftUI island and implements the two
/// behaviours that make a fixed-size transparent window behave like a small island:
///
///  1. **Click passthrough** (`hitTest`): only points inside the current island rect are
///     "ours"; everything else returns `nil` so the click reaches the window below.
///  2. **Event-driven hover** (`NSTrackingArea`): a single `.activeAlways` tracking area
///     covering the whole window feeds mouse movement to `onPointerMove`, which the
///     controller uses to test the cursor against the island rect. Tracking areas are
///     independent of `hitTest`, so we still see movement over the passthrough margins.
final class NotchContainerView: NSView {
    /// Current interactive island rect, in this view's coordinate space. Supplied by the
    /// controller; recomputed as the island expands/collapses.
    var islandRect: () -> CGRect = { .zero }
    /// Called on every mouse move/enter over the window, and on exit (with the last
    /// known location). The controller decides hover state from the cursor position.
    var onPointerMove: (() -> Void)?

    private var trackingAreaRef: NSTrackingArea?

    override var isFlipped: Bool { false }   // AppKit-native: origin bottom-left.

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in our *superview* coordinate space; convert to ours.
        let local = convert(point, from: superview)
        guard islandRect().contains(local) else { return nil }   // passthrough
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) { onPointerMove?() }
    override func mouseMoved(with event: NSEvent) { onPointerMove?() }
    override func mouseExited(with event: NSEvent) { onPointerMove?() }

    // A click that lands on the visible island should register on the very first press
    // even though the panel wasn't key, so the SwiftUI controls fire immediately instead
    // of merely focusing the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
