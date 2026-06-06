import AppKit
import SwiftUI
import Observation

/// Owns the notch panel: builds it, hosts the SwiftUI hub, pins it to the notch,
/// and shows/hides it in response to config + screen changes.
@MainActor
final class NotchHubController {
    private let viewModel: AppViewModel
    private let onOpenSettings: () -> Void
    private var panel: NotchPanel?
    private var hitState: NotchHitState?
    private var screenObserver: NSObjectProtocol?
    private var mouseMonitor: Any?

    /// Generous fixed footprint; the island animates within it, top-anchored.
    private let panelHeight: CGFloat = 320

    init(viewModel: AppViewModel, onOpenSettings: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }

        observeEnabled()
    }

    /// Track the notch-enabled flag and reflect it into panel visibility.
    private func observeEnabled() {
        withObservationTracking {
            _ = viewModel.config.notchEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyEnabledState()
                self?.observeEnabled()
            }
        }
        applyEnabledState()
    }

    private func applyEnabledState() {
        if viewModel.config.notchEnabled {
            if panel == nil { rebuild() }
        } else {
            teardown()
        }
    }

    private func rebuild() {
        guard viewModel.config.notchEnabled else { return }
        teardown()

        let screen = preferredScreen()
        let geometry = NotchGeometry.resolve(for: screen)
        let panelWidth = max(geometry.notchWidth + 84 * 2, 400)

        let frame = panelFrame(on: screen, width: panelWidth)
        let panel = NotchPanel(contentRect: frame)
        let hitState = NotchHitState()
        let hosting = NotchHostingView(
            rootView: NotchHubView(
                viewModel: viewModel,
                geometry: geometry,
                onOpenSettings: onOpenSettings,
                hitState: hitState
            )
        )
        hosting.hitState = hitState
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        self.hitState = hitState

        installMouseMonitor()
    }

    private func teardown() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        hitState = nil
    }

    /// Cross-app click-through requires toggling the *window's* `ignoresMouseEvents`
    /// (a `nil` view hit-test only forwards within the same app). A global mouse
    /// monitor lets us make the panel interactive only while the cursor is over the
    /// island, and transparent to clicks everywhere else.
    private func installMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePassthrough() }
        }
        updatePassthrough()
    }

    /// Enable interaction only when the pointer is within the island's screen rect.
    private func updatePassthrough() {
        guard let panel, let island = hitState?.islandFrame,
              island.width > 0, island.height > 0 else {
            panel?.ignoresMouseEvents = true
            return
        }
        // island frame is top-left origin within the panel's content; convert to the
        // panel's bottom-left AppKit space, then to global screen coordinates.
        let frame = panel.frame
        let screenRect = NSRect(
            x: frame.minX + island.minX,
            y: frame.minY + (frame.height - island.maxY),
            width: island.width,
            height: island.height
        )
        panel.ignoresMouseEvents = !screenRect.contains(NSEvent.mouseLocation)
    }

    private func preferredScreen() -> NSScreen? {
        // Prefer the screen that actually has a notch; else the main screen.
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private func panelFrame(on screen: NSScreen?, width: CGFloat) -> NSRect {
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - panelHeight   // top edge flush with screen top
        return NSRect(x: x, y: y, width: width, height: panelHeight)
    }
}
