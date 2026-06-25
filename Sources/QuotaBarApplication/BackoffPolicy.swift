import Foundation

/// Decides how long to wait before the next refresh, widening after failures.
public enum BackoffPolicy {
    public static func delaySeconds(baseInterval: Int, consecutiveFailures: Int) -> Int {
        guard consecutiveFailures > 0 else { return baseInterval }
        // Back off after failures, but never poll *more* often than the configured
        // base interval — otherwise a failing provider in Relaxed/Low-power mode
        // would hammer the endpoint faster than the user asked for.
        if consecutiveFailures == 1 { return max(baseInterval, 120) }   // ≥2 min after first failure
        return max(baseInterval, 300)                                   // ≥5 min after repeated failures
    }
}
