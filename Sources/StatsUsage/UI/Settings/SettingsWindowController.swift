import AppKit
import SwiftUI

/// Hosts the SwiftUI settings tree in a standard `NSWindow`.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(viewModel: AppViewModel) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "StatsUsage Settings"
        window.titlebarAppearsTransparent = false
        window.contentMinSize = NSSize(width: 640, height: 460)
        // Hide the toolbar area entirely — no sidebar toggle, no extra chrome.
        window.toolbar = nil
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsRootView(viewModel: viewModel))
    }

    func show() {
        // Accessory (menu-bar) apps can't rely on `activate(ignoringOtherApps:)` to
        // raise a window on recent macOS — it's deprecated and often leaves the window
        // behind other apps. `orderFrontRegardless()` forces it to the front even while
        // the app is inactive; centering when hidden keeps it discoverable.
        if window.isMiniaturized { window.deminiaturize(nil) }
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
