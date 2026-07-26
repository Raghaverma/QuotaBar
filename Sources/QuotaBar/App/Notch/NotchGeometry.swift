import AppKit

/// Physical dimensions of a screen's notch (or a sensible faux-notch on displays that
/// have none), resolved from public `NSScreen` APIs only — App Store-safe, no private
/// SkyLight/CGS calls.
///
/// The design contract for the rest of the notch stack: `NotchGeometry` is the *single*
/// source of truth for "where is the island, and how big is it collapsed." Everything
/// downstream (the window frame, the hover hit-rect, the SwiftUI island size) derives
/// from these numbers, so there is exactly one place to change if Apple ever alters the
/// notch metrics.
struct NotchGeometry: Equatable {
    /// Width of the physical notch cut-out (or the faux-island width on notch-less Macs).
    var notchWidth: CGFloat
    /// Height of the notch — equal to the menu-bar/safe-area height at the top.
    var notchHeight: CGFloat
    /// True only on Macs whose display actually has a hardware notch.
    var hasNotch: Bool
    /// Full frame of the screen the island lives on (global/AppKit coordinates).
    var screenFrame: CGRect
    /// Stable identifier for the screen, so we re-bind to the *same* physical display
    /// across monitor reordering / sleep / reconnect rather than a volatile array index.
    var displayID: CGDirectDisplayID

    /// Faux-island dimensions on a display with no hardware notch.
    static let fallbackWidth: CGFloat = 190
    static let fallbackHeight: CGFloat = 32

    /// The screen the island should live on: the first one with a real notch, else the
    /// screen currently hosting the menu bar (`NSScreen.main`), else any screen.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    static func resolve(for screen: NSScreen?) -> NotchGeometry {
        guard let screen else {
            return NotchGeometry(
                notchWidth: fallbackWidth,
                notchHeight: fallbackHeight,
                hasNotch: false,
                screenFrame: .zero,
                displayID: 0
            )
        }

        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top

        // On a notched Mac the notch height equals the top safe-area inset, and the
        // notch width is the gap between the two "ears" (the usable menu-bar strips to
        // the left and right of the camera housing).
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            return NotchGeometry(
                notchWidth: max(width, fallbackWidth),
                notchHeight: topInset,
                hasNotch: true,
                screenFrame: frame,
                displayID: screen.displayID
            )
        }

        // No hardware notch: behave as a floating island sized to the real menu-bar
        // height so it still lines up flush with the top of the screen.
        let menuBarHeight = frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(
            notchWidth: fallbackWidth,
            notchHeight: menuBarHeight > 0 ? menuBarHeight : fallbackHeight,
            hasNotch: false,
            screenFrame: frame,
            displayID: screen.displayID
        )
    }
}

extension NSScreen {
    /// The `CGDirectDisplayID` backing this screen, or `0` if unavailable.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value ?? 0
    }
}
