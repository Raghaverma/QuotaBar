import Foundation
import Observation

/// The two-way link between the AppKit `NotchController` (which owns the window and does
/// hover hit-testing at the pixel/screen level) and the SwiftUI `NotchView` (which owns
/// all animation and layout).
///
/// This is the whole coordination surface, and it is deliberately tiny:
///
///  - `pointerInside` is written by the controller's `NSTrackingArea` handler and read
///    by the view. The view applies its own open-intent / sticky-close debounce and
///    spring animation on top of it — the controller never animates anything.
///
///  - `isExpanded` is written by the view once its animation logic decides the panel is
///    open (or closed) and read back by the controller for exactly one purpose: to know
///    whether the interactive/hover region is the small collapsed notch rect or the full
///    expanded panel rect. This is what gives the hover a stable hysteresis (open over
///    the small notch, stay open across the whole big panel) with no window resizing.
///
/// Because the window is a *fixed size and is never resized*, there is nothing to
/// resize, no completion callbacks to sequence, and no layout re-entrancy to guard —
/// the entire class of jitter/crash bugs the previous design fought simply cannot occur.
@MainActor
@Observable
final class NotchLink {
    /// Cursor is within the current island hit-rect. Controller writes, view reads.
    var pointerInside = false
    /// Panel is (or is becoming) open. View writes, controller reads.
    var isExpanded = false
}
