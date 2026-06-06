import XCTest
import StatsUsageDomain
@testable import StatsUsage

final class ClaudeProviderTests: XCTestCase {
    private static func defaultOfficialClaude() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "claude",
            name: "Claude",
            family: .official,
            type: .claude,
            enabled: false,
            pollIntervalSec: 300,
            officialConfig: OfficialProviderConfig(sourceMode: .api)
        )
    }

    func testClaudeOAuthResponseParsesWindowsAndExtraUsage() throws {
        let root: [String: Any] = [
            "five_hour": ["utilization": 30.0, "resets_at": "2026-04-11T10:00:00Z"],
            "seven_day": ["utilization": 55.0, "resets_at": "2026-04-17T00:00:00Z"],
            "seven_day_opus": ["utilization": 80.0, "resets_at": "2026-04-17T00:00:00Z"],
            "extra_usage": ["used_credits": 1200.0, "monthly_limit": 5000.0]
        ]

        let snapshot = try ClaudeProvider.parseClaudeSnapshot(
            root: root,
            descriptor: Self.defaultOfficialClaude(),
            sourceLabel: "API",
            accountLabel: "claude@example.com",
            planHint: "pro"
        )

        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertEqual(snapshot.accountLabel, "claude@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 3)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .session })?.remainingPercent ?? -1, 70, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.remainingPercent ?? -1, 45, accuracy: 0.001)
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.kind == .session })?.resetAt,
            ISO8601DateFormatter().date(from: "2026-04-11T10:00:00Z")
        )
        XCTAssertEqual(
            snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.resetAt,
            ISO8601DateFormatter().date(from: "2026-04-17T00:00:00Z")
        )
        XCTAssertEqual(snapshot.extras["extraUsageCost"], "1200.00")
        XCTAssertEqual(snapshot.extras["extraUsageLimit"], "5000.00")
    }

    func testClaudeOAuthResponseNormalizesKnownModelWindowTitles() throws {
        let root: [String: Any] = [
            "five_hour": ["utilization": 10.0, "resets_at": "2026-04-11T10:00:00Z"],
            "seven_day": ["utilization": 20.0, "resets_at": "2026-04-17T00:00:00Z"],
            "seven_day_sonnet_only": ["utilization": 12.0, "resets_at": "2026-04-17T12:00:00Z"],
            "seven_day_claude_design": ["utilization": 34.0, "resets_at": "2026-04-19T23:00:00Z"]
        ]

        let snapshot = try ClaudeProvider.parseClaudeSnapshot(
            root: root,
            descriptor: Self.defaultOfficialClaude(),
            sourceLabel: "API",
            accountLabel: nil,
            planHint: "max"
        )

        XCTAssertNotNil(snapshot.quotaWindows.first(where: { $0.title == "Sonnet only" }))
        XCTAssertNotNil(snapshot.quotaWindows.first(where: { $0.title == "Claude Design" }))
        XCTAssertEqual(
            snapshot.rawMeta["claude.parsedSevenDayKeys"],
            "seven_day_claude_design,seven_day_sonnet_only"
        )
    }

    func testClaudeCLIParsing() throws {
        let cliOutput = """
        Claude CLI v0.1.0
        Current session (5h):
          Tokens remaining: 45% left (used 55%)
          Resets at: 2026-04-11T10:00:00Z
        Current week (7d):
          Tokens remaining: 80% left
          Resets at: 2026-04-17T00:00:00Z
        """

        let snapshot = try ClaudeProvider.parseClaudeCLIOutput(cliOutput, descriptor: Self.defaultOfficialClaude())
        XCTAssertEqual(snapshot.sourceLabel, "CLI")
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .session })?.remainingPercent, 45)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.kind == .weekly })?.remainingPercent, 80)
    }
}
