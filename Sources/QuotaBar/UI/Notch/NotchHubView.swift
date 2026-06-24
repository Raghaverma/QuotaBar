import SwiftUI
import QuotaBarDomain
import QuotaBarPresentation

/// The Dynamic-Island-style hub. Collapsed it straddles the notch with a compact
/// readout on each ear; on hover it expands downward into a live usage panel.
struct NotchHubView: View {
    @Bindable var viewModel: AppViewModel
    let geometry: NotchGeometry
    var onOpenSettings: () -> Void
    var layout: NotchLayoutBridge

    @State private var isExpanded = false
    @State private var openIntentTask: Task<Void, Never>?
    @State private var stickyCloseTask: Task<Void, Never>?

    // Spring parameters matched to boring.notch's feel: springy open, critically
    // damped close so it snaps shut without bouncing.
    private var openAnimation: Animation {
        .spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0)
    }
    private var closeAnimation: Animation {
        .spring(response: 0.35, dampingFraction: 1.0, blendDuration: 0)
    }

    // A mouse just passing over the island (moving across the menu bar, say)
    // shouldn't trigger it — only a deliberate, held hover should. Closing is the
    // opposite: stay open through brief exits (a finger slipping off the trackpad,
    // the cursor clipping the edge) so the panel doesn't flicker shut and reopen.
    private let openIntentDelay: Duration = .milliseconds(350)
    private let stickyCloseDelay: Duration = .milliseconds(1000)

    /// Bottom-corner radius of the physical notch; the collapsed island matches it so
    /// the painted ears read as a seamless continuation of the bezel.
    private var collapsedRadius: CGFloat { 11 }
    private var expandedRadius: CGFloat { 20 }

    private var earWidth: CGFloat { 70 }
    private var collapsedWidth: CGFloat { geometry.notchWidth + earWidth * 2 }
    private var expandedWidth: CGFloat { max(collapsedWidth, 380) }
    private var collapsedHeight: CGFloat { geometry.notchHeight }
    private var expandedHeight: CGFloat {
        Self.estimatedExpandedBodyHeight(enabledProviderCount: enabledProviders.count)
    }

    /// A deliberately generous estimate of `expandedBody`'s height, deterministic
    /// from the enabled-provider count alone. `NotchHubController` calls this same
    /// function (with the same provider count, read from config) to size the panel —
    /// keeping one formula as the shared source of truth for both. Errs toward
    /// slightly too tall rather than too short: a sliver of empty space at the bottom
    /// is far less noticeable than clipped content.
    static func estimatedExpandedBodyHeight(enabledProviderCount: Int) -> CGFloat {
        let header: CGFloat = 40        // "USAGE" row + divider + top padding
        let perRow: CGFloat = 62        // name + up to 2 countdown lines + trend line
        let emptyState: CGFloat = 36    // "No providers enabled" placeholder
        let footer: CGFloat = 40        // refresh/settings row + bottom padding
        let rows = enabledProviderCount > 0 ? CGFloat(enabledProviderCount) * perRow : emptyState
        return header + rows + footer
    }

    var body: some View {
        island
            .onAppear { layout.hoverHandler = { hovering in handleHover(hovering) } }
    }

    @ViewBuilder
    private var island: some View {
        if viewModel.config.notchCompactWidth {
            compactIsland.onTapGesture { onOpenSettings() }
        } else {
            standardIsland.onTapGesture { onOpenSettings() }
        }
    }

    /// Hover detection is driven from `NotchHubController` (which polls
    /// `NSEvent.mouseLocation` against the panel's actual AppKit frame), not from
    /// SwiftUI's `.onHover`. Empirically confirmed (via a one-shot debug log, not
    /// guessed): resizing the NSPanel — which `applyExpandedFrame`/`applyCollapsedFrame`
    /// do exactly twice per hover cycle, by design — silently breaks `.onHover`'s
    /// underlying NSTrackingArea for the rest of that window's lifetime. The very
    /// first hover after launch fires once; every hover after that first
    /// resize never fires again, leaving the panel stuck in whatever state it was in.
    /// Polling actual screen-space mouse coordinates at the AppKit level has no
    /// dependency on tracking areas at all, so it can't be broken by resizing.
    private func handleHover(_ hovering: Bool) {
        guard viewModel.config.notchExpandOnHover else { return }
        if hovering {
            // The cursor entered — a pending sticky-close (if any) is moot.
            stickyCloseTask?.cancel()
            stickyCloseTask = nil
            guard !isExpanded else { return }
            // Require a deliberate, held hover before expanding so the cursor
            // merely crossing the menu bar on its way elsewhere doesn't trigger it.
            openIntentTask?.cancel()
            openIntentTask = Task { @MainActor in
                try? await Task.sleep(for: openIntentDelay)
                guard !Task.isCancelled else { return }
                // Resize the panel to its final expanded frame *before* the SwiftUI
                // spring starts, so the window never has to chase the animation.
                layout.willExpand()
                withAnimation(openAnimation) { isExpanded = true }
            }
        } else {
            // The cursor left before the hover-intent delay elapsed — cancel the
            // pending expand outright rather than expanding-then-immediately-closing.
            openIntentTask?.cancel()
            openIntentTask = nil
            guard isExpanded else { return }
            // Sticky close: stay open through brief exits (edge clipping, a
            // trackpad finger slip) so the panel doesn't flicker shut and reopen.
            stickyCloseTask?.cancel()
            stickyCloseTask = Task { @MainActor in
                try? await Task.sleep(for: stickyCloseDelay)
                guard !Task.isCancelled else { return }
                withAnimation(closeAnimation, completionCriteria: .logicallyComplete) {
                    isExpanded = false
                } completion: {
                    // Only shrink the panel back down once the close animation has
                    // actually finished, so it's never smaller than the
                    // still-visibly-animating-out content.
                    layout.didCollapse()
                }
            }
        }
    }

    /// Default look: the whole island (ears + dropdown) shares one width and widens
    /// together on expand — boring.notch's and Apple's Dynamic Island's behavior.
    /// Always present (never structurally inserted/removed) so the height change
    /// between collapsed and expanded is a genuine animatable `.frame` value change,
    /// not a structural insertion that only animates its own opacity/scale — that's
    /// what made the surrounding shape look like it "snapped" rather than grew.
    /// `expandedHeight` is a deterministic estimate (see below), not a
    /// SwiftUI-measured value: in-tree measurement (GeometryReader/.fixedSize) turned
    /// out to be unreliable here, because the root SwiftUI view can never report a
    /// size larger than the actual NSPanel's *current* frame, which is the small
    /// collapsed footprint — there is no escaping that from inside the view tree
    /// while collapsed.
    private var standardIsland: some View {
        let radius = isExpanded ? expandedRadius : collapsedRadius
        return VStack(spacing: 0) {
            collapsedBar
            expandedBody(rowsActive: isExpanded)
                .frame(height: isExpanded ? expandedHeight : 0, alignment: .top)
                .clipped()
                .opacity(isExpanded ? 1 : 0)
                .scaleEffect(isExpanded ? 1 : 0.97, anchor: .top)
        }
        .frame(width: isExpanded ? expandedWidth : collapsedWidth)
        .background(NotchShape(bottomRadius: radius).fill(Color.black))
        .contentShape(NotchShape(bottomRadius: radius))
    }

    /// Alternate look: the ears stay exactly `collapsedWidth` at all times — never
    /// wider, never touching menu-bar space beyond what they already occupy — and
    /// only the dropdown panel beneath widens, into the empty wallpaper area below
    /// the menu bar rather than across it. Trades the continuous Dynamic-Island shape
    /// for a smaller permanent footprint.
    private var compactIsland: some View {
        VStack(spacing: 0) {
            collapsedBar
                .frame(width: collapsedWidth)
                .background(NotchShape(bottomRadius: collapsedRadius).fill(Color.black))
            expandedBody(rowsActive: isExpanded)
                .frame(width: expandedWidth, height: isExpanded ? expandedHeight : 0, alignment: .top)
                .clipped()
                .background(RoundedRectangle(cornerRadius: expandedRadius, style: .continuous).fill(Color.black))
                .opacity(isExpanded ? 1 : 0)
                .scaleEffect(isExpanded ? 1 : 0.97, anchor: .top)
        }
        .frame(width: isExpanded ? expandedWidth : collapsedWidth)
        // The only hit-testing shape in this tree — children above intentionally have
        // none of their own (just `.background()` for looks).
        .contentShape(Rectangle())
    }

    // MARK: Collapsed

    private var collapsedBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: geometry.notchWidth)   // reserve the camera gap
        }
        .frame(height: collapsedHeight)
    }

    private func ear<Content: View>(alignment: Alignment, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: earWidth - 10, alignment: alignment)
    }

    // MARK: Expanded

    /// `rowsActive` controls whether the per-second countdown ticks — pass `false`
    /// for the invisible measuring copy in `island` (see there for why a second copy
    /// exists at all) so it doesn't double the ticking cost for no visible benefit.
    private func expandedBody(rowsActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text("USAGE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            }
            .padding(.top, 2)
            Divider().overlay(Color.white.opacity(0.12))
            // Show every enabled provider — even ones still waiting on data (e.g. a
            // scaffolded provider) — so none silently disappear from the panel.
            ForEach(enabledProviders) { provider in
                NotchProviderRow(
                    name: provider.name,
                    snapshot: viewModel.snapshots[provider.id],
                    maskValues: viewModel.config.hideUsageValuesEnabled,
                    trend: viewModel.trendDescription(for: provider.id),
                    isActive: rowsActive
                )
            }
            if enabledProviders.isEmpty {
                Text("No providers enabled")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            }
            HStack {
                Button(action: { viewModel.refreshNow() }) {
                    Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                }
                Spacer()
                Button("Settings", action: onOpenSettings)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 6)
    }

    // MARK: Data helpers

    private var enabledProviders: [ProviderDescriptor] {
        viewModel.config.providers.filter { $0.enabled }
    }

    private var rows: [UsageSnapshot] {
        enabledProviders.compactMap { viewModel.snapshots[$0.id] }
    }

    private var primarySnapshot: UsageSnapshot? {
        if let id = viewModel.config.notchProviderID, let snap = viewModel.snapshots[id] { return snap }
        return rows.first
    }

    private var primaryWindow: UsageQuotaWindow? {
        primarySnapshot?.quotaWindows.first
    }

    private var primaryCountdown: String? {
        guard let window = primaryWindow else { return nil }
        return MenuQuotaPresenter.resetCountdown(window)
    }

    private func percentText(_ snap: UsageSnapshot) -> String {
        if viewModel.config.hideUsageValuesEnabled { return StatusBarDisplayPresenter.maskedValueText }
        if let pct = snap.remainingPercent ?? snap.quotaWindows.first?.remainingPercent {
            return "\(Int(pct.rounded()))%"
        }
        return "—"
    }

    private func name(for id: String) -> String {
        viewModel.config.providers.first(where: { $0.id == id })?.name ?? id
    }

    private func color(for snap: UsageSnapshot) -> Color {
        let pct = viewModel.config.hideUsageValuesEnabled
            ? nil
            : (snap.remainingPercent ?? snap.quotaWindows.first?.remainingPercent)
        guard snap.status == .ok, let pct else {
            return Color(nsColor: NSColor(red: 0.55, green: 0.55, blue: 0.57, alpha: 1.0))
        }
        switch pct {
        case ..<20:
            return Color(nsColor: NSColor(red: 1.0, green: 0.18, blue: 0.33, alpha: 1.0))
        case ..<50:
            return Color(nsColor: NSColor(red: 1.0, green: 0.63, blue: 0.0, alpha: 1.0))
        default:
            return Color(nsColor: NSColor(red: 0.0, green: 0.90, blue: 0.46, alpha: 1.0))
        }
    }
}


/// One provider row in the expanded hub: dot, name, ring, percent, countdown.
/// `snapshot` is optional so providers still waiting on data remain listed.
private struct NotchProviderRow: View {
    let name: String
    let snapshot: UsageSnapshot?
    let maskValues: Bool
    let trend: String?
    /// Whether the hub is actually expanded right now. `expandedBody` (and this row
    /// with it) is always present in the view tree so its height can be measured even
    /// while collapsed — but with the row invisible, there's no reason to keep its
    /// countdown ticking every second. Only the active (visible) row does that.
    let isActive: Bool

    @State private var animatedPercent: Double = 0

    private var percent: Double? {
        guard !maskValues else { return nil }
        return snapshot?.remainingPercent ?? snapshot?.quotaWindows.first?.remainingPercent
    }

    var body: some View {
        HStack(spacing: 10) {
            ring

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                if !resetWindows.isEmpty {
                    if isActive {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            countdownStack(now: context.date)
                        }
                    } else {
                        countdownStack(now: Date())
                    }
                } else if let subtitle = subtitleText {
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                // Depletion pace — more actionable than the bare percent: "how much
                // longer is this safe for" rather than just "where am I right now".
                if let trend, !maskValues {
                    Text(trend)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
            Text(maskValues ? StatusBarDisplayPresenter.maskedValueText : (percent.map { "\(Int($0.rounded()))%" } ?? "—"))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(percent == nil ? .white.opacity(0.4) : .white)
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(animatedPercent / 100))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 22, height: 22)
        .onAppear {
            withAnimation(.smooth(duration: 0.5).delay(0.05)) {
                animatedPercent = percent ?? 0
            }
        }
        .onChange(of: percent) { _, newValue in
            withAnimation(.smooth(duration: 0.5)) {
                animatedPercent = newValue ?? 0
            }
        }
    }

    /// Shared between the ticking (active) and static (inactive) render paths, so
    /// gating the tick can never change this row's measured height.
    private func countdownStack(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(resetWindows.prefix(2)) { window in
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(windowLabel(window))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(MenuQuotaPresenter.liveResetCountdown(window, now: now) ?? "")
                        .foregroundStyle(.white.opacity(0.7))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
            }
        }
    }

    /// Subtitle when there are no reset windows: the snapshot's note, or a waiting hint.
    private var subtitleText: String? {
        guard let snapshot else { return "Waiting for data…" }
        return snapshot.note.isEmpty ? nil : snapshot.note
    }

    /// Windows that carry a real reset clock, in display order.
    private var resetWindows: [UsageQuotaWindow] {
        snapshot?.quotaWindows.filter { $0.resetAt != nil } ?? []
    }

    private func windowLabel(_ window: UsageQuotaWindow) -> String {
        window.title.isEmpty ? "resets" : window.title
    }

    private var ringColor: Color {
        guard let snapshot, snapshot.status == .ok, let pct = percent else {
            return Color(nsColor: NSColor(red: 0.55, green: 0.55, blue: 0.57, alpha: 1.0))
        }
        switch pct {
        case ..<20:
            return Color(nsColor: NSColor(red: 1.0, green: 0.18, blue: 0.33, alpha: 1.0))
        case ..<50:
            return Color(nsColor: NSColor(red: 1.0, green: 0.63, blue: 0.0, alpha: 1.0))
        default:
            return Color(nsColor: NSColor(red: 0.0, green: 0.90, blue: 0.46, alpha: 1.0))
        }
    }
}
