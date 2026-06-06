import Foundation

/// Overall health of a single snapshot at a glance.
public enum SnapshotStatus: String, Codable, Sendable {
    case ok, warning, error, disabled
}

/// Why the fetch is in its current state — drives diagnostics copy.
public enum FetchHealth: String, Codable, Sendable {
    case ok, authExpired, rateLimited, endpointMisconfigured, unreachable
}

/// Is this value live, a cached fallback after a failed refresh, or absent?
public enum ValueFreshness: String, Codable, Sendable {
    case live, cachedFallback, empty
}

/// What kind of quota window this is.
public enum UsageQuotaKind: String, Codable, Sendable {
    case session, weekly, reviews, credits, extraUsage, modelWeekly, custom
}

/// Where the *reset time* came from.
public enum UsageQuotaResetSource: String, Codable, Sendable {
    case official, webObserved, localEstimate, userCalibrated, unknown
}

/// How confident we are in the reset time.
public enum UsageQuotaResetConfidence: String, Codable, Sendable {
    case confirmed, estimated, stale, unknown
}
