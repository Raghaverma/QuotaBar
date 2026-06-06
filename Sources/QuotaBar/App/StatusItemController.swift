import AppKit
import StatsUsagePresentation

/// Wraps an `NSStatusItem` button. The critical optimization: compute a render
/// signature and only redraw when it changes, so a resident app isn't a battery drain.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private var lastRenderSignature: String?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "…"
    }

    var button: NSStatusItem.statusBarButtonType? { statusItem.button }

    /// Render entries with the chosen widget style; returns true if a redraw happened.
    @discardableResult
    func render(
        entries: [StatusBarDisplayEntry],
        style: MenuBarWidgetStyle,
        history: [String: [Double]],
        appearanceDark: Bool
    ) -> Bool {
        let signature = Self.renderSignature(
            entries: entries, style: style, history: history, appearanceDark: appearanceDark
        )
        guard signature != lastRenderSignature else { return false }
        lastRenderSignature = signature

        guard let button = statusItem.button else { return false }
        if entries.isEmpty {
            button.image = nil
            button.title = "StatsUsage"
            return true
        }
        button.title = ""
        button.image = MenuBarWidgetRenderer.image(
            entries: entries, style: style, history: history, appearanceDark: appearanceDark
        )
        button.imagePosition = .imageOnly
        return true
    }

    private static func renderSignature(
        entries: [StatusBarDisplayEntry],
        style: MenuBarWidgetStyle,
        history: [String: [Double]],
        appearanceDark: Bool
    ) -> String {
        let parts = entries.map { entry -> String in
            // Quantize history into the signature so the sparkline redraws when the
            // trend actually moves, not on every poll that returns the same value.
            let hist = (history[entry.providerID] ?? []).suffix(30)
                .map { String(Int($0.rounded())) }.joined(separator: ",")
            return "\(entry.providerID):\(entry.percentText):\(entry.isHealthy):[\(hist)]"
        }
        return parts.joined(separator: "|") + "#\(style.rawValue)#\(appearanceDark)"
    }
}

/// AppKit's button type alias for clarity at the call site.
extension NSStatusItem {
    typealias statusBarButtonType = NSStatusBarButton
}
