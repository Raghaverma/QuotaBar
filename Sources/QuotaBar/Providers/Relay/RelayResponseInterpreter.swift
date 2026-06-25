import Foundation
import QuotaBarDomain

/// Applies a manifest's `extract` rules to a decoded JSON response, producing a
/// `UsageSnapshot`. Pure — gets unit tests against recorded fixtures.
enum RelayResponseInterpreter {
    static func interpret(
        data: Data,
        manifest: RelayAdapterManifest,
        providerID: String,
        providerName: String,
        lowRemaining: Double = 0
    ) throws -> UsageSnapshot {
        let root = try RelayJSONExpressionEvaluator.parse(data)
        let extract = manifest.extract

        // Honor an explicit success flag if the manifest declares one.
        if let successExpr = extract.success {
            let v = RelayJSONExpressionEvaluator.evaluate(successExpr, root: root)
            if case .bool(let ok) = v, !ok {
                throw ProviderError.invalidResponse("Relay reported success=false")
            }
        }

        func number(_ expr: String?) -> Double? {
            guard let expr else { return nil }
            return RelayJSONExpressionEvaluator.evaluate(expr, root: root).doubleValue
        }
        func string(_ expr: String?) -> String? {
            guard let expr else { return nil }
            return RelayJSONExpressionEvaluator.evaluate(expr, root: root).stringValue
        }

        let remaining = number(extract.remaining)
        let used = number(extract.used)
        let limit = number(extract.limit)
        let unit = string(extract.unit) ?? "quota"
        let accountLabel = string(extract.accountLabel)

        // Derive remaining-% the same way `UsageSnapshot.remainingPercent` does, so
        // the status reflects the threshold instead of being hardcoded healthy.
        let remainingPercent: Double? = {
            guard let limit, limit > 0 else { return nil }
            if let remaining { return max(0, min(100, remaining / limit * 100)) }
            if let used { return max(0, min(100, (limit - used) / limit * 100)) }
            return nil
        }()
        let status: SnapshotStatus = (remainingPercent.map { $0 <= lowRemaining } ?? false) ? .warning : .ok

        return UsageSnapshot(
            source: providerID,
            status: status,
            fetchHealth: .ok,
            valueFreshness: .live,
            remaining: remaining,
            used: used,
            limit: limit,
            unit: unit,
            note: "",
            sourceLabel: "API",
            accountLabel: accountLabel
        ).withDefaultResetMetadata()
    }
}
