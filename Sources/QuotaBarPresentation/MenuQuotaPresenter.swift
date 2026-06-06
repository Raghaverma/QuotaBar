import Foundation
import StatsUsageDomain

/// Turns a quota window into display strings. Pure and unit-tested; views stay dumb.
public enum MenuQuotaPresenter {
    public static func remainingText(_ window: UsageQuotaWindow) -> String {
        "\(Int(window.remainingPercent.rounded()))% left"
    }

    /// Human-friendly countdown to reset, e.g. "resets in 3h 12m".
    public static func resetCountdown(_ window: UsageQuotaWindow, now: Date = Date()) -> String? {
        guard let resetAt = window.resetAt else { return nil }
        let remaining = resetAt.timeIntervalSince(now)
        if remaining <= 0 { return "resetting…" }
        let totalMinutes = Int(remaining / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "resets in \(days)d \(hours)h" }
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        return "resets in \(minutes)m"
    }

    /// A live, second-accurate countdown for views that tick every second, e.g.
    /// "2d 3h", "3h 12m", "12m 04s", "45s". Returns `nil` when there is no reset clock.
    /// Designed to be re-evaluated continuously (drive it from a `TimelineView`).
    public static func liveResetCountdown(_ window: UsageQuotaWindow, now: Date = Date()) -> String? {
        guard let resetAt = window.resetAt else { return nil }
        let remaining = Int(resetAt.timeIntervalSince(now).rounded(.down))
        if remaining <= 0 { return "now" }
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        let seconds = remaining % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(String(format: "%02d", minutes))m" }
        if minutes > 0 { return "\(minutes)m \(String(format: "%02d", seconds))s" }
        return "\(seconds)s"
    }

    /// A short trust label derived from confidence + freshness.
    public static func confidenceLabel(_ window: UsageQuotaWindow, freshness: ValueFreshness) -> String {
        if freshness == .cachedFallback { return "cached" }
        switch window.confidence {
        case .confirmed: return "confirmed"
        case .estimated: return "estimated"
        case .stale: return "stale"
        case .unknown: return "unknown"
        }
    }
}
