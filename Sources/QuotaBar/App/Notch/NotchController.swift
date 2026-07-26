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
    private var lastLayoutSignature: String?

    // NSObjectProtocol observer tokens are safe to pass to `removeObserver` from any
    // thread; `nonisolated(unsafe)` lets a nonisolated `deinit` release it without an
    // async hop back to the main actor.
    private nonisolated(unsafe) var screenObserver: NSObjectProtocol?

    /// Cursor sampling keeps hover alive while the window is click-through. 30 Hz is
    /// imperceptible to the user and costs one rect test per tick.
    private static let hoverSampleInterval: TimeInterval = 1.0 / 30.0
    // `nonisolated(unsafe)` mirrors `screenObserver`: it lets the nonisolated deinit
    // invalidate the timer without hopping back to the main actor.
    private nonisolated(unsafe) var hoverTimer: Timer?

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
        rebuildIfNeeded(force: true)
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        hoverTimer?.invalidate()
    }

    // MARK: Observation

    /// Re-arm on every relevant config change. Only the fields that change the *window's
    /// geometry* trigger a rebuild; the SwiftUI view observes everything else itself.
    ///
    /// Re-arming must not itself rebuild: this runs after *every* config mutation, so a
    /// forced rebuild here would tear down and recreate the panel (and its hosting view
    /// and tracking areas) on every unrelated settings toggle, making `lastLayoutSignature`
    /// pointless and destroying the island mid-interaction. The initial build is the
    /// initializer's job.
    private func observeConfig() {
        withObservationTracking {
            _ = viewModel.config.notchEnabled
            _ = viewModel.config.notchCompactWidth
            _ = viewModel.config.providers.filter(\.enabled).count
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeConfig()
                self?.rebuildIfNeeded(force: false)
            }
        }
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

        // Second line of defence behind `ignoresMouseEvents`: even while the window is
        // accepting events, only the visible island is "solid".
        container.islandRect = { [weak self] in self?.currentIslandRectLocal() ?? .zero }
        container.onPointerMove = { [weak self] in self?.evaluateHover() }

        let frame = windowFrame(geometry: geometry, size: CGSize(width: windowWidth, height: windowHeight))
        let window = NotchWindow(contentRect: frame, container: container)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()

        self.container = container
        self.window = window

        startCursorTracking()
        evaluateHover()
    }

    private func teardown() {
        stopCursorTracking()
        window?.orderOut(nil)
        window = nil
        container = nil
        geometry = nil
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
        return Self.islandRect(
            windowFrame: window.frame,
            notchWidth: geometry.notchWidth,
            notchHeight: geometry.notchHeight,
            isExpanded: link.isExpanded
        )
    }

    /// Where the island is *actually visible* within its (much larger) window.
    ///
    /// Collapsed this is just the physical notch at top-centre — a small fraction of the
    /// window, which is sized for the fully expanded panel. Everything outside it is
    /// empty space that must not intercept the cursor. Pure and static so the
    /// pass-through decision can be tested without an AppKit window.
    nonisolated static func islandRect(
        windowFrame: CGRect,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        isExpanded: Bool
    ) -> CGRect {
        if isExpanded { return windowFrame }
        return CGRect(
            x: windowFrame.midX - notchWidth / 2,
            y: windowFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
    }

    /// Called on every tracked mouse movement. Pure hit-test: is the cursor within the
    /// current island rect? The SwiftUI view turns this into open/close with its own
    /// intent + sticky-close debounce, so a mouse merely crossing the notch never opens
    /// it and a fingertip slipping off the edge never flickers it shut.
    private func evaluateHover() {
        let inside = currentIslandRectScreen().contains(NSEvent.mouseLocation)
        if link.pointerInside != inside { link.pointerInside = inside }
        // The window is far larger than the visible island (it is sized for the fully
        // expanded panel and never resized). Everything outside the island must be
        // click-through, and only `ignoresMouseEvents` achieves that across processes —
        // view hit-testing runs after the window server has already claimed the event.
        if let window, window.ignoresMouseEvents == inside {
            window.ignoresMouseEvents = !inside
        }
    }

    // MARK: Cursor tracking

    /// Cursor tracking cannot rely on the container's `NSTrackingArea`: the moment the
    /// window turns click-through — which is most of the time, so the margins stay
    /// usable — it stops receiving mouse events entirely, and the hover state would
    /// latch, leaving the window stuck in whichever mode it was last in.
    ///
    /// Event monitors are not a dependable substitute either. macOS coalesces
    /// `.mouseMoved` aggressively: measured against this window, a global monitor
    /// observed only one of twelve cursor movements. Missing a movement means missing
    /// the transition out of the island, which strands the window opaque and swallows
    /// every click underneath it — exactly the bug this is meant to fix.
    ///
    /// Sampling `NSEvent.mouseLocation` on a timer has neither problem: it needs no
    /// permissions, cannot be coalesced away, and reads the true cursor position no
    /// matter which app owns it. The work per tick is one rect containment test.
    private func startCursorTracking() {
        stopCursorTracking()
        let timer = Timer(timeInterval: Self.hoverSampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluateHover() }
        }
        // `.common` so sampling continues during menu tracking and window drags.
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func stopCursorTracking() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }
}
