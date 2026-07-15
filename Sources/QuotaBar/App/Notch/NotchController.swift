import AppKit
import SwiftUI
import Observation

/// Owns the notch island's window and lifecycle. Its whole job is *setup and hit-testing*
/// — it builds one fixed-size window pinned to the notch, keeps it bound to the right
/// physical display, and translates raw cursor movement into a single `pointerInside`
/// signal. It never animates and never resizes: the SwiftUI `NotchView` owns all motion.
///
/// Compared with the previous controller this is dramatically smaller because the entire
/// "resize the panel to chase the content" problem — and every guard, callback, and
/// height-estimate it required — no longer exists.
@MainActor
final class NotchController {
    // Fixed island metrics. The window is built once per (screen, provider-count,
    // compact) configuration and never resized while the user interacts with it.
    private static let expandedWidth: CGFloat = 420

    private let viewModel: AppViewModel
    private let onOpenSettings: () -> Void
    private let link = NotchLink()

    private var window: NotchWindow?
    private var container: NotchContainerView?
    private var geometry: NotchGeometry?
    private var boundDisplayID: CGDirectDisplayID?
    private var lastLayoutSignature: String?

    // NSObjectProtocol observer tokens are safe to pass to `removeObserver` from any
    // thread; `nonisolated(unsafe)` lets a nonisolated `deinit` release it without an
    // async hop back to the main actor.
    private nonisolated(unsafe) var screenObserver: NSObjectProtocol?

    init(viewModel: AppViewModel, onOpenSettings: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildIfNeeded(force: true) }
        }

        observeConfig()
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    // MARK: Observation

    /// Re-arm on every relevant config change. Only the fields that change the *window's
    /// geometry* trigger a rebuild; the SwiftUI view observes everything else itself.
    private func observeConfig() {
        withObservationTracking {
            _ = viewModel.config.notchEnabled
            _ = viewModel.config.notchCompactWidth
            _ = viewModel.config.providers.filter(\.enabled).count
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.rebuildIfNeeded(force: false)
                self?.observeConfig()
            }
        }
        rebuildIfNeeded(force: true)
    }

    // MARK: Build / teardown

    /// A compact key of everything the window's size/position depends on. When it is
    /// unchanged, we keep the existing window (and its tracking areas) rather than
    /// tearing down and rebuilding on every unrelated config edit.
    private func layoutSignature(geometry: NotchGeometry, providerCount: Int, compact: Bool) -> String {
        "\(geometry.displayID)|\(Int(geometry.notchWidth))x\(Int(geometry.notchHeight))|\(providerCount)|\(compact)"
    }

    private func rebuildIfNeeded(force: Bool) {
        guard viewModel.config.notchEnabled else {
            teardown()
            return
        }

        let screen = NotchGeometry.preferredScreen()
        let geometry = NotchGeometry.resolve(for: screen)
        let providerCount = viewModel.config.providers.filter(\.enabled).count
        let compact = viewModel.config.notchCompactWidth
        let signature = layoutSignature(geometry: geometry, providerCount: providerCount, compact: compact)

        if !force, signature == lastLayoutSignature, window != nil { return }
        lastLayoutSignature = signature

        build(geometry: geometry, providerCount: providerCount)
    }

    private func build(geometry: NotchGeometry, providerCount: Int) {
        teardown()
        self.geometry = geometry
        self.boundDisplayID = geometry.displayID

        let windowWidth = max(geometry.notchWidth, Self.expandedWidth)
        let panelHeight = NotchMetrics.panelHeight(providerCount: providerCount)
        let windowHeight = geometry.notchHeight + panelHeight

        let container = NotchContainerView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        let hosting = NSHostingView(
            rootView: NotchView(
                viewModel: viewModel,
                link: link,
                metrics: NotchMetrics(
                    notchWidth: geometry.notchWidth,
                    notchHeight: geometry.notchHeight,
                    expandedWidth: Self.expandedWidth,
                    panelHeight: panelHeight
                ),
                onOpenSettings: onOpenSettings
            )
        )
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        // The window sits over the menu-bar/notch area; without this the hosting view
        // would inset SwiftUI content by the safe area and the island would float below
        // the physical notch instead of hugging it.
        if #available(macOS 13.3, *) { hosting.sizingOptions = [] }
        container.addSubview(hosting)

        // hitTest passthrough: only the currently-visible island is "solid".
        container.islandRect = { [weak self] in self?.currentIslandRectLocal() ?? .zero }
        container.onPointerMove = { [weak self] in self?.evaluateHover() }

        let frame = windowFrame(geometry: geometry, size: CGSize(width: windowWidth, height: windowHeight))
        let window = NotchWindow(contentRect: frame, container: container)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()

        self.container = container
        self.window = window
    }

    private func teardown() {
        window?.orderOut(nil)
        window = nil
        container = nil
        geometry = nil
        boundDisplayID = nil
        link.pointerInside = false
        link.isExpanded = false
    }

    // MARK: Geometry helpers

    private func windowFrame(geometry: NotchGeometry, size: CGSize) -> NSRect {
        let screenFrame = geometry.screenFrame == .zero
            ? (NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900))
            : geometry.screenFrame
        return NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,   // top edge flush with the screen top
            width: size.width,
            height: size.height
        )
    }

    /// The interactive island rect in the container's (bottom-left origin) coordinates.
    /// Collapsed → just the physical notch at top-center; expanded → the whole window.
    private func currentIslandRectLocal() -> CGRect {
        guard let container, let geometry else { return .zero }
        let b = container.bounds
        if link.isExpanded { return b }
        let w = geometry.notchWidth
        let h = geometry.notchHeight
        return CGRect(x: (b.width - w) / 2, y: b.height - h, width: w, height: h)
    }

    /// The interactive island rect in global/screen coordinates, for cursor hit-testing.
    private func currentIslandRectScreen() -> CGRect {
        guard let window, let geometry else { return .zero }
        if link.isExpanded { return window.frame }
        let f = window.frame
        let w = geometry.notchWidth
        let h = geometry.notchHeight
        return CGRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h)
    }

    /// Called on every tracked mouse movement. Pure hit-test: is the cursor within the
    /// current island rect? The SwiftUI view turns this into open/close with its own
    /// intent + sticky-close debounce, so a mouse merely crossing the notch never opens
    /// it and a fingertip slipping off the edge never flickers it shut.
    private func evaluateHover() {
        let inside = currentIslandRectScreen().contains(NSEvent.mouseLocation)
        if link.pointerInside != inside { link.pointerInside = inside }
    }
}
