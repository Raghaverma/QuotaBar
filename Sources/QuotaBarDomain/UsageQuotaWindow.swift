import Foundation

/// A single rolling quota window (e.g. a 5-hour session window or a weekly window),
/// each with its own reset clock and confidence metadata.
public struct UsageQuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var remainingPercent: Double
    public var usedPercent: Double
    public var resetAt: Date?
    public var kind: UsageQuotaKind
    public var resetSource: UsageQuotaResetSource
    public var observedAt: Date?
    public var serverClockSkew: TimeInterval?
    public var confidence: UsageQuotaResetConfidence
    public var windowIdentity: String?

    public init(
        id: String,
        title: String,
        remainingPercent: Double,
        usedPercent: Double,
        resetAt: Date? = nil,
        kind: UsageQuotaKind = .custom,
        resetSource: UsageQuotaResetSource = .unknown,
        observedAt: Date? = nil,
        serverClockSkew: TimeInterval? = nil,
        confidence: UsageQuotaResetConfidence = .unknown,
        windowIdentity: String? = nil
    ) {
        self.id = id
        self.title = title
        self.remainingPercent = remainingPercent
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.kind = kind
        self.resetSource = resetSource
        self.observedAt = observedAt
        self.serverClockSkew = serverClockSkew
        self.confidence = confidence
        self.windowIdentity = windowIdentity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        remainingPercent = try c.decodeIfPresent(Double.self, forKey: .remainingPercent) ?? 0
        usedPercent = try c.decodeIfPresent(Double.self, forKey: .usedPercent) ?? 0
        resetAt = try c.decodeIfPresent(Date.self, forKey: .resetAt)
        kind = try c.decodeIfPresent(UsageQuotaKind.self, forKey: .kind) ?? .custom
        resetSource = try c.decodeIfPresent(UsageQuotaResetSource.self, forKey: .resetSource) ?? .unknown
        observedAt = try c.decodeIfPresent(Date.self, forKey: .observedAt)
        serverClockSkew = try c.decodeIfPresent(TimeInterval.self, forKey: .serverClockSkew)
        confidence = try c.decodeIfPresent(UsageQuotaResetConfidence.self, forKey: .confidence) ?? .unknown
        windowIdentity = try c.decodeIfPresent(String.self, forKey: .windowIdentity)
    }
}
