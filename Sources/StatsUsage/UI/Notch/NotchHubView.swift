import SwiftUI
import StatsUsageDomain
import StatsUsagePresentation

/// The Dynamic-Island-style hub. Collapsed it straddles the notch with a compact
/// readout on each ear; on hover it expands downward into a live usage panel.
struct NotchHubView: View {
    @Bindable var viewModel: AppViewModel
    let geometry: NotchGeometry
    var onOpenSettings: () -> Void
    var layout: NotchLayoutBridge

    @State private var isExpanded = false

    /// Bottom-corner radius of the physical notch; the collapsed island matches it so
    /// the painted ears read as a seamless continuation of the bezel.
    private var collapsedRadius: CGFloat { 11 }
    private var expandedRadius: CGFloat { 20 }

    private var earWidth: CGFloat { 70 }
    private var collapsedWidth: CGFloat { geometry.notchWidth + earWidth * 2 }
    private var expandedWidth: CGFloat { max(collapsedWidth, 380) }
    private var collapsedHeight: CGFloat { geometry.notchHeight }

    var body: some View {
        // The island measures its own intrinsic size and reports it up so the panel
        // can shrink to fit. No outer fill/frame — the window is exactly the island.
        island
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: IslandSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(IslandSizePreferenceKey.self) { size in
                let measured = size
                Task { @MainActor in layout.report(measured) }
            }
    }

    private var island: some View {
        let radius = isExpanded ? expandedRadius : collapsedRadius
        return VStack(spacing: 0) {
            collapsedBar
            if isExpanded {
                expandedBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: isExpanded ? expandedWidth : collapsedWidth)
        .background(NotchShape(bottomRadius: radius).fill(Color.black))
        .contentShape(NotchShape(bottomRadius: radius))
        .onHover { hovering in
            guard viewModel.config.notchExpandOnHover else { return }
            // Critically damped (no overshoot) so the island settles cleanly instead of
            // bouncing — especially noticeable on collapse.
            withAnimation(.smooth(duration: 0.3)) {
                isExpanded = hovering
            }
        }
        .onTapGesture { onOpenSettings() }
    }

    // MARK: Collapsed

    private var collapsedBar: some View {
        HStack(spacing: 0) {
            ear(alignment: .leading) {
                if let snap = primarySnapshot {
                    HStack(spacing: 5) {
                        Circle().fill(color(for: snap)).frame(width: 7, height: 7)
                        Text(percentText(snap))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
            Spacer(minLength: geometry.notchWidth)   // reserve the camera gap
            ear(alignment: .trailing) {
                if let window = primaryWindow, window.resetAt != nil {
                    // A live, per-second ticking countdown so the time-to-reset is
                    // always accurate between data refreshes — not frozen at render.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 3) {
                            Image(systemName: "timer")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(MenuQuotaPresenter.liveResetCountdown(window, now: context.date) ?? "")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.78))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .lineLimit(1)
                        }
                    }
                } else if let snap = primarySnapshot {
                    Text(snap.unit)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(height: collapsedHeight)
        .padding(.horizontal, 10)
    }

    private func ear<Content: View>(alignment: Alignment, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: earWidth - 10, alignment: alignment)
    }

    // MARK: Expanded

    private var expandedBody: some View {
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
                NotchProviderRow(name: provider.name, snapshot: viewModel.snapshots[provider.id])
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
        if let pct = snap.remainingPercent ?? snap.quotaWindows.first?.remainingPercent {
            return "\(Int(pct.rounded()))%"
        }
        return "—"
    }

    private func name(for id: String) -> String {
        viewModel.config.providers.first(where: { $0.id == id })?.name ?? id
    }

    private func color(for snap: UsageSnapshot) -> Color {
        let pct = snap.remainingPercent ?? snap.quotaWindows.first?.remainingPercent
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

/// Reports the island's measured size up to the controller so the panel can be sized
/// to fit it exactly (and resized as it expands/collapses).
private struct IslandSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// One provider row in the expanded hub: dot, name, ring, percent, countdown.
/// `snapshot` is optional so providers still waiting on data remain listed.
private struct NotchProviderRow: View {
    let name: String
    let snapshot: UsageSnapshot?

    @State private var animatedPercent: Double = 0

    private var percent: Double? {
        snapshot?.remainingPercent ?? snapshot?.quotaWindows.first?.remainingPercent
    }

    var body: some View {
        HStack(spacing: 10) {
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

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                if !resetWindows.isEmpty {
                    // Live, per-second countdown for each window's reset clock.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(resetWindows.prefix(2)) { window in
                                HStack(spacing: 4) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.4))
                                    Text(windowLabel(window))
                                        .foregroundStyle(.white.opacity(0.4))
                                    Text(MenuQuotaPresenter.liveResetCountdown(window, now: context.date) ?? "")
                                        .foregroundStyle(.white.opacity(0.7))
                                        .monospacedDigit()
                                        .contentTransition(.numericText())
                                }
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                            }
                        }
                    }
                } else if let subtitle = subtitleText {
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            Spacer()
            Text(percent.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(percent == nil ? .white.opacity(0.4) : .white)
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
