import SwiftUI
import QuotaBarDomain

/// The Dynamic-Island-style hub. Collapsed, it sits over the physical notch at its exact
/// hardware size; on a deliberate hover it springs open, downward, into a live usage
/// panel. All motion lives here — the AppKit layer only feeds it a `pointerInside` signal
/// through `link` and never resizes anything, so the spring never fights a window frame.
struct NotchView: View {
    @Bindable var viewModel: AppViewModel
    @Bindable var link: NotchLink
    let metrics: NotchMetrics
    var onOpenSettings: () -> Void

    @State private var isExpanded = false
    @State private var isHoverIntending = false
    @State private var openIntentTask: Task<Void, Never>?
    @State private var stickyCloseTask: Task<Void, Never>?

    // Springy on the way open, critically damped on the way closed so it settles without
    // bouncing. (Matched to boring.notch's feel.)
    private var openAnimation: Animation { .spring(response: 0.42, dampingFraction: 0.82) }
    private var closeAnimation: Animation { .spring(response: 0.34, dampingFraction: 1.0) }

    // A cursor merely crossing the notch shouldn't open it — only a held hover past this
    // delay should. Closing is the opposite: forgive brief exits so a fingertip slipping
    // off the edge doesn't flicker the panel shut.
    private let openIntentDelay: Duration = .milliseconds(350)
    private let stickyCloseDelay: Duration = .milliseconds(220)

    private var bottomRadius: CGFloat {
        isExpanded ? NotchTheme.expandedBottomRadius : NotchTheme.collapsedBottomRadius
    }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.all)
        .onChange(of: link.pointerInside) { _, inside in handleHover(inside) }
    }

    @ViewBuilder
    private var island: some View {
        if viewModel.config.notchCompactWidth {
            compactIsland
        } else {
            standardIsland
        }
    }

    // MARK: Standard island — one continuous shape that widens as it opens.

    private var standardIsland: some View {
        VStack(spacing: 0) {
            collapsedBar
            expandedPanel
                .frame(height: isExpanded ? metrics.panelHeight : 0, alignment: .top)
                .opacity(isExpanded ? 1 : 0)
                .scaleEffect(isExpanded ? 1 : 0.96, anchor: .top)
        }
        .frame(width: isExpanded ? metrics.expandedWidth : metrics.notchWidth)
        .background(NotchShape(topCornerRadius: NotchTheme.topRadius, bottomCornerRadius: bottomRadius)
            .fill(NotchTheme.surface))
        .overlay(intentWash)
        .overlay(alignment: .bottom) { peekIndicator }
        .clipShape(NotchShape(topCornerRadius: NotchTheme.topRadius, bottomCornerRadius: bottomRadius))
        .overlay(alignment: .top) { bezelSeam }   // hide the AA seam against the hardware bezel
        .contentShape(NotchShape(topCornerRadius: NotchTheme.topRadius, bottomCornerRadius: bottomRadius))
    }

    // MARK: Compact island — narrow "ears" stay put; only the dropdown card widens.

    private var compactIsland: some View {
        VStack(spacing: 0) {
            collapsedBar
                .frame(width: metrics.notchWidth)
                .background(NotchShape(topCornerRadius: NotchTheme.topRadius,
                                       bottomCornerRadius: NotchTheme.collapsedBottomRadius)
                    .fill(NotchTheme.surface))
                .overlay(alignment: .bottom) { peekIndicator }
                .clipShape(NotchShape(topCornerRadius: NotchTheme.topRadius,
                                      bottomCornerRadius: NotchTheme.collapsedBottomRadius))
                .overlay(alignment: .top) { bezelSeam }
            expandedPanel
                .frame(width: metrics.expandedWidth,
                       height: isExpanded ? metrics.panelHeight : 0, alignment: .top)
                .background(RoundedRectangle(cornerRadius: NotchTheme.expandedBottomRadius, style: .continuous)
                    .fill(NotchTheme.surface))
                .clipShape(RoundedRectangle(cornerRadius: NotchTheme.expandedBottomRadius, style: .continuous))
                .opacity(isExpanded ? 1 : 0)
                .scaleEffect(isExpanded ? 1 : 0.96, anchor: .top)
                .padding(.top, isExpanded ? 6 : 0)
        }
        .frame(width: isExpanded ? metrics.expandedWidth : metrics.notchWidth)
    }

    // MARK: Collapsed bar — a plain black strip covering the camera housing. Tapping it
    // opens Settings (the notch is a secondary way in, since there's no Dock icon).

    private var collapsedBar: some View {
        Color.clear
            .frame(height: metrics.notchHeight)
            .contentShape(Rectangle())
            .onTapGesture { onOpenSettings() }
    }

    // A 1px pure-black cap flush with the physical bezel, so no sub-pixel antialiasing
    // halo ever shows between the software shape and the hardware notch.
    private var bezelSeam: some View {
        NotchTheme.surface.frame(height: 1).allowsHitTesting(false)
    }

    // Faint wash while the open-intent timer charges — acknowledges a deliberate hover
    // before the panel actually springs.
    private var intentWash: some View {
        NotchShape(topCornerRadius: NotchTheme.topRadius, bottomCornerRadius: bottomRadius)
            .fill(isHoverIntending ? NotchTheme.intentWash : .clear)
            .allowsHitTesting(false)
    }

    // A slim status accent at the bottom of the collapsed notch — a glanceable "something
    // needs attention" cue that never appears while expanded or while values are masked.
    @ViewBuilder
    private var peekIndicator: some View {
        let status = worstStatus
        let show = !isExpanded && !viewModel.config.hideUsageValuesEnabled
            && (status == .warning || status == .critical)
        Capsule()
            .fill(status.color)
            .frame(width: metrics.notchWidth * 0.32, height: 2.5)
            .padding(.bottom, 2)
            .opacity(show ? 0.95 : 0)
            .animation(.easeInOut(duration: 0.3), value: show)
            .allowsHitTesting(false)
    }

    // MARK: Expanded panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: NotchMetrics.headerHeight)
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
                .padding(.top, 6)
                .padding(.bottom, NotchMetrics.headerGap - 6)

            if enabledProviders.isEmpty {
                Text("No providers enabled")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: NotchMetrics.emptyStateHeight)
            } else {
                ForEach(enabledProviders) { provider in
                    NotchProviderRow(
                        name: provider.name,
                        snapshot: viewModel.snapshots[provider.id],
                        maskValues: viewModel.config.hideUsageValuesEnabled,
                        trend: viewModel.trendDescription(for: provider.id),
                        isActive: isExpanded
                    )
                }
            }

            Spacer(minLength: NotchMetrics.footerGap)
            footer.frame(height: NotchMetrics.footerHeight)
        }
        .padding(.horizontal, 16)
        .padding(.top, NotchMetrics.topPadding)
        .padding(.bottom, NotchMetrics.bottomPadding)
        .frame(width: metrics.expandedWidth, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.secondaryText)
            Text("QuotaBar")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(NotchTheme.secondaryText)
            Spacer(minLength: 6)
            if let summary = overallSummary {
                HStack(spacing: 4) {
                    Circle().fill(worstStatus.color).frame(width: 5, height: 5)
                    Text(summary)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.tertiaryText)
                        .lineLimit(1)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button { viewModel.refreshNow() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
            .help("Refresh now")

            if !viewModel.refreshingProviderIDs.isEmpty {
                ProgressView().controlSize(.mini)
            }

            Spacer()

            Button(action: onOpenSettings) {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape.fill").font(.system(size: 11, weight: .semibold))
                    Text("Settings").font(.system(size: 11, weight: .semibold))
                }
            }
            .help("Open Settings")
        }
        .buttonStyle(.plain)
        .foregroundStyle(NotchTheme.secondaryText)
    }

    // MARK: Hover state machine

    private func handleHover(_ hovering: Bool) {
        guard viewModel.config.notchExpandOnHover else { return }
        if hovering {
            stickyCloseTask?.cancel()
            stickyCloseTask = nil
            guard !isExpanded else { return }
            openIntentTask?.cancel()
            openIntentTask = Task { @MainActor in
                withAnimation(.easeIn(duration: 0.12)) { isHoverIntending = true }
                try? await Task.sleep(for: openIntentDelay)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.1)) { isHoverIntending = false }
                expand()
            }
        } else {
            openIntentTask?.cancel()
            openIntentTask = nil
            withAnimation(.easeOut(duration: 0.1)) { isHoverIntending = false }
            guard isExpanded else { return }
            stickyCloseTask?.cancel()
            stickyCloseTask = Task { @MainActor in
                try? await Task.sleep(for: stickyCloseDelay)
                guard !Task.isCancelled else { return }
                collapse()
            }
        }
    }

    private func expand() {
        // Widen the controller's hit-region *before* animating so the cursor stays
        // "inside" across the whole panel the instant it opens.
        link.isExpanded = true
        withAnimation(openAnimation) { isExpanded = true }
    }

    private func collapse() {
        // Shrink the hit-region back to the notch only once we've committed to closing
        // (the sticky-close grace period has already elapsed).
        link.isExpanded = false
        withAnimation(closeAnimation) { isExpanded = false }
    }

    // MARK: Derived data

    private var enabledProviders: [ProviderDescriptor] {
        let enabled = viewModel.config.providers.filter(\.enabled)
        guard let primaryID = viewModel.config.notchProviderID,
              let primaryIndex = enabled.firstIndex(where: { $0.id == primaryID }) else {
            return enabled
        }
        var ordered = enabled
        ordered.insert(ordered.remove(at: primaryIndex), at: 0)
        return ordered
    }

    private func percent(for provider: ProviderDescriptor) -> Double? {
        let snap = viewModel.snapshots[provider.id]
        return snap?.remainingPercent ?? snap?.quotaWindows.first?.remainingPercent
    }

    private func status(for provider: ProviderDescriptor) -> NotchStatus {
        .from(remainingPercent: percent(for: provider),
              isHealthy: viewModel.snapshots[provider.id]?.status == .ok)
    }

    /// The most-alarming status across all enabled providers, for the peek indicator and
    /// the header dot.
    private var worstStatus: NotchStatus {
        enabledProviders.reduce(NotchStatus.unknown) { $0.worse(than: status(for: $1)) }
    }

    /// Compact header summary, e.g. "Claude 8%" for the lowest provider, or a plain count
    /// when nothing has data yet. Suppressed while values are masked.
    private var overallSummary: String? {
        guard !viewModel.config.hideUsageValuesEnabled else { return nil }
        let withData = enabledProviders.compactMap { p -> (String, Double)? in
            guard let pct = percent(for: p) else { return nil }
            return (p.name, pct)
        }
        if let lowest = withData.min(by: { $0.1 < $1.1 }) {
            return "\(lowest.0) \(Int(lowest.1.rounded()))%"
        }
        let count = enabledProviders.count
        return count == 0 ? nil : "\(count) provider\(count == 1 ? "" : "s")"
    }
}
