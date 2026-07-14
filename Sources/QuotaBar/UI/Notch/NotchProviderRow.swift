import SwiftUI
import QuotaBarDomain
import QuotaBarPresentation

/// One provider's line in the expanded panel: a ring gauge of remaining quota, the
/// provider name, up to two live reset countdowns, an optional trend line, and the
/// remaining percentage.
struct NotchProviderRow: View {
    let name: String
    let snapshot: UsageSnapshot?
    let maskValues: Bool
    let trend: String?
    /// Only true while the panel is actually open, so the per-second countdown clock
    /// isn't kept ticking on an invisible view.
    let isActive: Bool

    @State private var animatedFraction: Double = 0

    var body: some View {
        HStack(spacing: 11) {
            ring
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)

                if !resetWindows.isEmpty {
                    if isActive {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            countdowns(now: context.date)
                        }
                    } else {
                        countdowns(now: Date())
                    }
                } else if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTheme.tertiaryText)
                        .lineLimit(1)
                }

                if let trend, !maskValues {
                    Text(trend)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 6)
            Text(percentText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(percent == nil ? NotchTheme.tertiaryText : NotchTheme.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(height: NotchMetrics.rowHeight, alignment: .center)
    }

    // MARK: Ring gauge

    private var ring: some View {
        ZStack {
            Circle().stroke(NotchTheme.ringTrack, lineWidth: 3)
            Circle()
                .trim(from: 0, to: animatedFraction)
                .stroke(status.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 26, height: 26)
        .onAppear {
            withAnimation(.smooth(duration: 0.5).delay(0.05)) {
                animatedFraction = fraction
            }
        }
        .onChange(of: fraction) { _, newValue in
            withAnimation(.smooth(duration: 0.5)) { animatedFraction = newValue }
        }
    }

    private func countdowns(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(resetWindows.prefix(2)) { window in
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(NotchTheme.tertiaryText)
                    Text(windowLabel(window))
                        .foregroundStyle(NotchTheme.tertiaryText)
                    Text(MenuQuotaPresenter.liveResetCountdown(window, now: now) ?? "")
                        .foregroundStyle(NotchTheme.secondaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .lineLimit(1)
            }
        }
    }

    // MARK: Derived data

    private var percent: Double? {
        guard !maskValues else { return nil }
        return snapshot?.remainingPercent ?? snapshot?.quotaWindows.first?.remainingPercent
    }

    private var fraction: Double {
        guard let percent else { return 0 }
        return max(0, min(1, percent / 100))
    }

    private var percentText: String {
        if maskValues { return StatusBarDisplayPresenter.maskedValueText }
        return percent.map { "\(Int($0.rounded()))%" } ?? "—"
    }

    private var status: NotchStatus {
        .from(remainingPercent: percent, isHealthy: snapshot?.status == .ok)
    }

    private var subtitle: String? {
        guard let snapshot else { return "Waiting for data…" }
        return snapshot.note.isEmpty ? nil : snapshot.note
    }

    private var resetWindows: [UsageQuotaWindow] {
        snapshot?.quotaWindows.filter { $0.resetAt != nil } ?? []
    }

    private func windowLabel(_ window: UsageQuotaWindow) -> String {
        window.title.isEmpty ? "resets" : window.title
    }
}
