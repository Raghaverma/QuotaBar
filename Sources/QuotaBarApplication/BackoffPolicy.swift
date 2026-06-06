import Foundation

/// Decides how long to wait before the next refresh, widening after failures.
public enum BackoffPolicy {
    public static func delaySeconds(baseInterval: Int, consecutiveFailures: Int) -> Int {
        if consecutiveFailures <= 0 { return baseInterval }
        if consecutiveFailures == 1 { return 120 }   // 2 min after first failure
        return 300                                    // 5 min after repeated failures
    }
}
