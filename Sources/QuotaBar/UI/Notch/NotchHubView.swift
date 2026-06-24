import SwiftUI
import QuotaBarDomain
import QuotaBarPresentation

/// The Dynamic-Island-style hub. Collapsed it sits over the physical notch at its
/// exact hardware dimensions; on hover it expands downward into a live usage panel.
struct NotchHubView: View {
    @Bindable var viewModel: AppViewModel
    let geometry: NotchGeometry
    var onOpenSettings: () -> Void
    var layout: NotchLayoutBridge

    @State private var isExpanded = false
    @State private var isHoverIntending = false
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
    private let stickyCloseDelay: Duration = .milliseconds(200)

    private var collapsedRadius: CGFloat { 11 }
    private var expandedRadius: CGFloat { 20 }

    // Collapsed footprint matches the physical notch exactly (derived from NSScreen
    // safeAreaInsets / auxiliaryTopLeft+RightArea in NotchGeometry). No extra width.
    private var collapsedWidth:  CGFloat { geometry.notchWidth }
    private var collapsedHeight: CGFloat { geometry.notchHeight }
    private var expandedWidth:   CGFloat { max(geometry.notchWidth, 380) }
    private var expandedHeight:  CGFloat {
        Self.estimatedExpandedBodyHeight(enabledProviderCount: enabledProviders.count)
    }

    /// Deterministic height estimate shared with `NotchHubController` so the panel
    /// frame and the SwiftUI layout always agree. Errs slightly tall rather than short.
    static func estimatedExpandedBodyHeight(enabledProviderCount: Int) -> CGFloat {
        let header: CGFloat = 40
        let perRow: CGFloat = 62
        let emptyState: CGFloat = 36
        let footer: CGFloat = 40
        let rows = enabledProviderCount > 0 ? CGFloat(enabledProviderCount) * perRow : emptyState
        return header + rows + footer
    }

    var body: some View {
        // `.frame(maxWidth: .infinity, alignment: .center)` is critical: without it,
        // NSHostingView left-aligns SwiftUI content. When the panel pre-expands to
        // 380pt before the SwiftUI animation starts, the island would sit at the
        // left edge instead of staying centered over the physical notch.
        island
            .frame(maxWidth: .infinity, alignment: .center)
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
            stickyCloseTask?.cancel()
            stickyCloseTask = nil
            guard !isExpanded else { return }
            openIntentTask?.cancel()
            openIntentTask = Task { @MainActor in
                // Immediately signal "charging up" so the island feels responsive
                // even during the 350ms debounce delay.
                withAnimation(.easeIn(duration: 0.12)) { isHoverIntending = true }
                try? await Task.sleep(for: openIntentDelay)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.1)) { isHoverIntending = false }
                layout.willExpand()
                withAnimation(openAnimation) { isExpanded = true }
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
                withAnimation(closeAnimation, completionCriteria: .logicallyComplete) {
                    isExpanded = false
                } completion: {
                    layout.didCollapse()
                }
            }
        }
    }

    // MARK: Island variants

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
        .background(NotchShape(bottomCornerRadius: radius).fill(Color.black))
        .overlay(
            NotchShape(bottomCornerRadius: radius)
                .fill(Color.white.opacity(isHoverIntending ? 0.07 : 0))
                .allowsHitTesting(false)
        )
        // 1px black strip at the very top edge hides any sub-pixel antialiasing gap
        // between the software shape and the physical hardware bezel.
        .overlay(alignment: .top) {
            Color.black.frame(height: 1).allowsHitTesting(false)
        }
        .contentShape(NotchShape(bottomCornerRadius: radius))
    }

    private var compactIsland: some View {
        VStack(spacing: 0) {
            collapsedBar
                .frame(width: collapsedWidth)
                .background(NotchShape(bottomCornerRadius: collapsedRadius).fill(Color.black))
                .overlay(
                    NotchShape(bottomCornerRadius: collapsedRadius)
                        .fill(Color.white.opacity(isHoverIntending ? 0.07 : 0))
                        .allowsHitTesting(false)
                )
                .overlay(alignment: .top) {
                    Color.black.frame(height: 1).allowsHitTesting(false)
                }
            expandedBody(rowsActive: isExpanded)
                .frame(width: expandedWidth, height: isExpanded ? expandedHeight : 0, alignment: .top)
                .clipped()
                .background(RoundedRectangle(cornerRadius: expandedRadius, style: .continuous).fill(Color.black))
                .opacity(isExpanded ? 1 : 0)
                .scaleEffect(isExpanded ? 1 : 0.97, anchor: .top)
        }
        .frame(width: isExpanded ? expandedWidth : collapsedWidth)
        .contentShape(Rectangle())
    }

    // MARK: Collapsed bar

    // A plain black bar that exactly covers the hardware notch. No content —
    // the physical notch is a camera housing, not a status display.
    private var collapsedBar: some View {
        Color.clear.frame(height: collapsedHeight)
    }

    // MARK: Expanded body

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
}


/// One provider row in the expanded hub: ring, name, countdown, trend, percent.
private struct NotchProviderRow: View {
    let name: String
    let snapshot: UsageSnapshot?
    let maskValues: Bool
    let trend: String?
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
            withAnimation(.smooth(duration: 0.5).delay(0.05)) { animatedPercent = percent ?? 0 }
        }
        .onChange(of: percent) { _, newValue in
            withAnimation(.smooth(duration: 0.5)) { animatedPercent = newValue ?? 0 }
        }
    }

    private func countdownStack(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(resetWindows.prefix(2)) { window in
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(windowLabel(window)).foregroundStyle(.white.opacity(0.4))
                    Text(MenuQuotaPresenter.liveResetCountdown(window, now: now) ?? "")
                        .foregroundStyle(.white.opacity(0.7))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
            }
        }
    }

    private var subtitleText: String? {
        guard let snapshot else { return "Waiting for data…" }
        return snapshot.note.isEmpty ? nil : snapshot.note
    }

    private var resetWindows: [UsageQuotaWindow] {
        snapshot?.quotaWindows.filter { $0.resetAt != nil } ?? []
    }

    private func windowLabel(_ window: UsageQuotaWindow) -> String {
        window.title.isEmpty ? "resets" : window.title
    }

    private var ringColor: Color {
        notchStatusColor(remainingPercent: percent, isOk: snapshot?.status == .ok)
    }
}

/// Three-tier health colour shared by all ring indicators in the hub.
private func notchStatusColor(remainingPercent pct: Double?, isOk: Bool) -> Color {
    guard isOk, let pct else {
        return Color(nsColor: NSColor(red: 0.55, green: 0.55, blue: 0.57, alpha: 1.0))
    }
    switch pct {
    case ..<20: return Color(nsColor: NSColor(red: 1.0, green: 0.18, blue: 0.33, alpha: 1.0))
    case ..<50: return Color(nsColor: NSColor(red: 1.0, green: 0.63, blue: 0.0, alpha: 1.0))
    default:    return Color(nsColor: NSColor(red: 0.0, green: 0.90, blue: 0.46, alpha: 1.0))
    }
}
