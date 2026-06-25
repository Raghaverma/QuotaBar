import AppKit
import SwiftUI
import Observation

/// Owns the notch panel: builds it, hosts the SwiftUI hub, pins it to the notch, and
/// resizes it to fit the island so the window never covers anything but the hub.
///
/// Resizing strategy: the panel is resized exactly twice per hover cycle — to the
/// expanded frame right before the open animation starts (`applyExpandedFrame`), and
/// back to the collapsed frame right after the close animation finishes
/// (`applyCollapsedFrame`) — never continuously while SwiftUI is mid-animation. A
/// `NotchHubController` that called `setFrame` on every layout pass (as this used to)
/// fights the SwiftUI spring frame-by-frame, which is the actual mechanism behind
/// "fidgety" notch jitter. boring.notch avoids this differently — it allocates one
/// fixed maximal-size window up front and never resizes at all — but QuotaBar's
/// content height is variable (it depends on how many providers are enabled), so a
/// fixed window would either clip a long provider list or, sized generously enough to
/// never clip, sit as a large invisible click-blocking dead zone over apps beneath
/// while collapsed (the exact tradeoff this codebase's original design avoided by
/// sizing the window to the content). Resizing only at the two animation boundaries
/// gets both properties: no mid-animation resize jitter, and a small, click-through
/// footprint whenever the hub isn't actively expanding or collapsing.
@MainActor
final class NotchHubController {
    private let viewModel: AppViewModel
    private let onOpenSettings: () -> Void
    private var panel: NotchPanel?
    private let layout = NotchLayoutBridge()
    private var screen: NSScreen?
    private var geometry: NotchGeometry?
    private var screenObserver: NSObjectProtocol?
    private var hoverPollTask: Task<Void, Never>?

    // Mirrors NotchHubView's own layout constants so the panel's deterministic
    // collapsed/expanded frames match what SwiftUI will actually lay out.
    // Keep these in sync if either file's values change.
    private let minExpandedWidth: CGFloat = 380

    init(viewModel: AppViewModel, onOpenSettings: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings

        layout.onWillExpand = { [weak self] in self?.applyExpandedFrame() }
        layout.onDidCollapse = { [weak self] in self?.applyCollapsedFrame() }

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
        self.geometry = geometry

        // The collapsed footprint is fully deterministic (geometry-derived), so the
        // panel starts at its exact final collapsed size — no measure-then-snap step.
        let frame = panelFrame(on: screen, size: collapsedSize(for: geometry))

        let panel = NotchPanel(contentRect: frame)
        let hosting = NotchHostingView(
            rootView: NotchHubView(
                viewModel: viewModel,
                geometry: geometry,
                onOpenSettings: onOpenSettings,
                layout: layout
            )
        )
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        startHoverPolling()
    }

    private func teardown() {
        hoverPollTask?.cancel()
        hoverPollTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Polls `NSEvent.mouseLocation` against the panel's AppKit frame every 50ms and
    /// fires `layout.hoverHandler` on state changes. This completely replaces SwiftUI's
    /// `.onHover`, which breaks permanently after any `panel.setFrame()` call because
    /// the underlying NSTrackingArea is invalidated and never recreated.
    private func startHoverPolling() {
        hoverPollTask?.cancel()
        hoverPollTask = Task { @MainActor [weak self] in
            var lastHovering = false
            while !Task.isCancelled {
                if let self, let panel = self.panel {
                    let mouse = NSEvent.mouseLocation
                    let isInside = panel.frame.contains(mouse)
                    if isInside != lastHovering {
                        lastHovering = isInside
                        self.layout.hoverHandler?(isInside)
                    }
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Resize to the expanded frame *before* the SwiftUI open animation starts, so the
    /// panel is already the right size when the spring begins — one resize, ahead of
    /// the animation, instead of one per layout pass during it. The height is the same
    /// deterministic estimate `NotchHubView` uses for its own `.frame(height:)`
    /// animation target, so the window and the SwiftUI content always agree.
    private func applyExpandedFrame() {
        guard let panel, let geometry else { return }
        let providerCount = viewModel.config.providers.filter(\.enabled).count
        let height = collapsedHeight(for: geometry)
            + NotchHubView.estimatedExpandedBodyHeight(enabledProviderCount: providerCount)
        let size = CGSize(width: expandedWidth(for: geometry), height: height)
        panel.setFrame(panelFrame(on: screen, size: size), display: true)
    }

    /// Mirror of `applyExpandedFrame`, fired once the close animation has actually
    /// finished — not when it starts — so the panel only shrinks back to its small,
    /// click-passthrough footprint once nothing is still visually animating inside it.
    private func applyCollapsedFrame() {
        guard let panel, let geometry else { return }
        panel.setFrame(panelFrame(on: screen, size: collapsedSize(for: geometry)), display: true)
    }

    private func collapsedWidth(for geometry: NotchGeometry) -> CGFloat {
        geometry.notchWidth
    }

    private func collapsedHeight(for geometry: NotchGeometry) -> CGFloat {
        geometry.notchHeight
    }

    private func expandedWidth(for geometry: NotchGeometry) -> CGFloat {
        max(geometry.notchWidth, minExpandedWidth)
    }

    private func collapsedSize(for geometry: NotchGeometry) -> CGSize {
        CGSize(width: collapsedWidth(for: geometry), height: collapsedHeight(for: geometry))
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
