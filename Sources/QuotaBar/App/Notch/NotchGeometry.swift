import AppKit

/// Resolves the physical notch size for a screen, with sensible fallbacks on Macs
/// (or external displays) that have no notch — there it behaves as a floating island.
struct NotchGeometry: Equatable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool
    var screenFrame: CGRect

    /// Fallback dimensions when the display has no notch.
    static let fallbackWidth: CGFloat = 180
    static let fallbackHeight: CGFloat = 32

    static func resolve(for screen: NSScreen?) -> NotchGeometry {
        guard let screen else {
            return NotchGeometry(
                notchWidth: fallbackWidth, notchHeight: fallbackHeight,
                hasNotch: false, screenFrame: .zero
            )
        }
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top

        // The notch height equals the top safe-area inset on notched Macs.
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            return NotchGeometry(
                notchWidth: max(width, fallbackWidth),
                notchHeight: topInset,
                hasNotch: true,
                screenFrame: frame
            )
        }
        
        // Dynamic fallback to match the actual menu bar height on non-notched screens
        let menuBarHeight = frame.maxY - screen.visibleFrame.maxY
        let resolvedHeight = menuBarHeight > 0 ? menuBarHeight : fallbackHeight
        
        return NotchGeometry(
            notchWidth: fallbackWidth,
            notchHeight: resolvedHeight,
            hasNotch: false,
            screenFrame: frame
        )
    }
}
