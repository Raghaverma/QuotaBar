import Foundation
import StatsUsageDomain

/// Pure decision function: given the prior state and a new snapshot, decide
/// whether (and why) to fire an alert. No side effects — trivially unit-testable.
public enum AlertEngine {
    public enum Decision: Equatable, Sendable {
        case none
        case lowRemaining(percent: Double)
        case repeatedFailures(count: Int)
        case authError
    }

    public static func evaluate(
        snapshot: UsageSnapshot,
        consecutiveFailures: Int,
        rule: AlertRule
    ) -> Decision {
        if rule.notifyOnAuthError, snapshot.fetchHealth == .authExpired {
            return .authError
        }
        if consecutiveFailures >= rule.maxConsecutiveFailures, rule.maxConsecutiveFailures > 0 {
            return .repeatedFailures(count: consecutiveFailures)
        }
        if let pct = snapshot.remainingPercent, pct <= rule.lowRemaining {
            return .lowRemaining(percent: pct)
        }
        return .none
    }
}
