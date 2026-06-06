import Foundation

/// The normalized result of fetching one provider once. Every other layer agrees
/// on this contract. Decodes defensively so old cached snapshots survive new fields.
public struct UsageSnapshot: Codable, Identifiable, Equatable, Sendable {
    public var id: String { source }
    public var source: String              // stable provider id
    public var status: SnapshotStatus
    public var fetchHealth: FetchHealth
    public var valueFreshness: ValueFreshness
    public var remaining: Double?
    public var used: Double?
    public var limit: Double?
    public var unit: String                // "quota", "USD", "credits", "%", ...
    public var updatedAt: Date
    public var note: String                // human-readable status / error line
    public var quotaWindows: [UsageQuotaWindow]
    public var sourceLabel: String         // "API" / "CLI" / "Web" — drives inference
    public var accountLabel: String?
    public var authSourceLabel: String?
    public var diagnosticCode: String?
    public var extras: [String: String]    // provider-specific display extras
    public var rawMeta: [String: String]   // raw fields kept for debugging

    public init(
        source: String,
        status: SnapshotStatus = .ok,
        fetchHealth: FetchHealth = .ok,
        valueFreshness: ValueFreshness = .live,
        remaining: Double? = nil,
        used: Double? = nil,
        limit: Double? = nil,
        unit: String = "quota",
        updatedAt: Date = Date(),
        note: String = "",
        quotaWindows: [UsageQuotaWindow] = [],
        sourceLabel: String = "",
        accountLabel: String? = nil,
        authSourceLabel: String? = nil,
        diagnosticCode: String? = nil,
        extras: [String: String] = [:],
        rawMeta: [String: String] = [:]
    ) {
        self.source = source
        self.status = status
        self.fetchHealth = fetchHealth
        self.valueFreshness = valueFreshness
        self.remaining = remaining
        self.used = used
        self.limit = limit
        self.unit = unit
        self.updatedAt = updatedAt
        self.note = note
        self.quotaWindows = quotaWindows
        self.sourceLabel = sourceLabel
        self.accountLabel = accountLabel
        self.authSourceLabel = authSourceLabel
        self.diagnosticCode = diagnosticCode
        self.extras = extras
        self.rawMeta = rawMeta
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(String.self, forKey: .source)
        status = try c.decodeIfPresent(SnapshotStatus.self, forKey: .status) ?? .ok
        fetchHealth = try c.decodeIfPresent(FetchHealth.self, forKey: .fetchHealth) ?? .ok
        valueFreshness = try c.decodeIfPresent(ValueFreshness.self, forKey: .valueFreshness) ?? .live
        remaining = try c.decodeIfPresent(Double.self, forKey: .remaining)
        used = try c.decodeIfPresent(Double.self, forKey: .used)
        limit = try c.decodeIfPresent(Double.self, forKey: .limit)
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? "quota"
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        quotaWindows = try c.decodeIfPresent([UsageQuotaWindow].self, forKey: .quotaWindows) ?? []
        sourceLabel = try c.decodeIfPresent(String.self, forKey: .sourceLabel) ?? ""
        accountLabel = try c.decodeIfPresent(String.self, forKey: .accountLabel)
        authSourceLabel = try c.decodeIfPresent(String.self, forKey: .authSourceLabel)
        diagnosticCode = try c.decodeIfPresent(String.self, forKey: .diagnosticCode)
        extras = try c.decodeIfPresent([String: String].self, forKey: .extras) ?? [:]
        rawMeta = try c.decodeIfPresent([String: String].self, forKey: .rawMeta) ?? [:]
    }

    /// Convenience for the common "remaining as a percentage" computation.
    public var remainingPercent: Double? {
        guard let limit, limit > 0 else { return nil }
        if let remaining { return max(0, min(100, remaining / limit * 100)) }
        if let used { return max(0, min(100, (limit - used) / limit * 100)) }
        return nil
    }
}

public extension UsageSnapshot {
    /// Back-fill missing reset metadata on each window by inference, so providers
    /// can stay terse. Mirrors the reference design's `withDefaultResetMetadata`.
    func withDefaultResetMetadata() -> UsageSnapshot {
        var copy = self
        copy.quotaWindows = quotaWindows.map { window in
            var w = window
            if w.resetSource == .unknown {
                w.resetSource = Self.inferResetSource(fromLabel: sourceLabel)
            }
            if w.confidence == .unknown {
                w.confidence = Self.inferConfidence(freshness: valueFreshness, source: w.resetSource)
            }
            return w
        }
        return copy
    }

    private static func inferResetSource(fromLabel label: String) -> UsageQuotaResetSource {
        let l = label.lowercased()
        if l.contains("api") { return .official }
        if l.contains("web") || l.contains("browser") { return .webObserved }
        if l.contains("cli") || l.contains("local") { return .localEstimate }
        return .unknown
    }

    private static func inferConfidence(
        freshness: ValueFreshness,
        source: UsageQuotaResetSource
    ) -> UsageQuotaResetConfidence {
        if freshness == .cachedFallback { return .stale }
        switch source {
        case .official, .userCalibrated: return .confirmed
        case .webObserved, .localEstimate: return .estimated
        case .unknown: return .unknown
        }
    }
}
