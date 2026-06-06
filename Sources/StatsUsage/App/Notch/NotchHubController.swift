import AppKit
import SwiftUI
import Observation

/// Owns the notch panel: builds it, hosts the SwiftUI hub, pins it to the notch, and
/// resizes it to fit the island so the window never covers anything but the hub.
@MainActor
final class NotchHubController {
    private let viewModel: AppViewModel
    private let onOpenSettings: () -> Void
    private var panel: NotchPanel?
    private let layout = NotchLayoutBridge()
    private var screen: NSScreen?
    private var screenObserver: NSObjectProtocol?

    init(viewModel: AppViewModel, onOpenSettings: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings

        layout.onSizeChange = { [weak self] size in self?.resizePanel(to: size) }

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
        self.screen = screen
        let geometry = NotchGeometry.resolve(for: screen)

        // Start at a reasonable collapsed estimate; the SwiftUI hub reports its real
        // size on first layout and `resizePanel(to:)` snaps the panel to fit.
        let initialSize = CGSize(width: geometry.notchWidth + 140, height: max(geometry.notchHeight, 32))
        let frame = panelFrame(on: screen, size: initialSize)

        let panel = NotchPanel(contentRect: frame)
        let hosting = NotchHostingView(
            rootView: NotchHubView(
                viewModel: viewModel,
                geometry: geometry,
                onOpenSettings: onOpenSettings,
                layout: layout
            )
        )
        hosting.onLayout = { [weak self] size in self?.resizePanel(to: size) }
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func teardown() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Snap the panel to the island's measured size, keeping it pinned top-centre.
    /// Driven every layout pass (including mid-animation) so expand/collapse stays in
    /// lockstep with the SwiftUI content and the window is only ever as big as the hub.
    private func resizePanel(to size: CGSize) {
        guard let panel, size.width > 1, size.height > 1 else { return }
        let frame = panelFrame(on: screen, size: size)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    private func preferredScreen() -> NSScreen? {
        // Prefer the screen that actually has a notch; else the main screen.
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private func panelFrame(on screen: NSScreen?, size: CGSize) -> NSRect {
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height   // top edge flush with screen top
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
