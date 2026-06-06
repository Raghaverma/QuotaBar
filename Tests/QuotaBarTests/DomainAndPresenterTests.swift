import XCTest
import StatsUsageDomain
import StatsUsagePresentation

final class UsageSnapshotTests: XCTestCase {
    func testRemainingPercentComputation() {
        let snap = UsageSnapshot(source: "x", remaining: 25, limit: 100)
        XCTAssertEqual(snap.remainingPercent, 25)
    }

    func testDecodeToleratesMissingNewerFields() throws {
        // Minimal old-style JSON: only `source`.
        let json = #"{"source":"legacy"}"#
        let snap = try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snap.source, "legacy")
        XCTAssertEqual(snap.fetchHealth, .ok)
        XCTAssertEqual(snap.valueFreshness, .live)
        XCTAssertTrue(snap.extras.isEmpty)
    }

    func testDefaultResetMetadataInfersFromSourceLabel() {
        let window = UsageQuotaWindow(id: "w", title: "Session", remainingPercent: 50, usedPercent: 50)
        let snap = UsageSnapshot(source: "x", quotaWindows: [window], sourceLabel: "API")
            .withDefaultResetMetadata()
        XCTAssertEqual(snap.quotaWindows.first?.resetSource, .official)
        XCTAssertEqual(snap.quotaWindows.first?.confidence, .confirmed)
    }

    func testCachedFallbackBecomesStale() {
        let window = UsageQuotaWindow(id: "w", title: "Session", remainingPercent: 50, usedPercent: 50)
        let snap = UsageSnapshot(
            source: "x", valueFreshness: .cachedFallback, quotaWindows: [window], sourceLabel: "API"
        ).withDefaultResetMetadata()
        XCTAssertEqual(snap.quotaWindows.first?.confidence, .stale)
    }
}

final class PresenterTests: XCTestCase {
    func testStatusBarEntryUsesRemainingPercent() {
        let snap = UsageSnapshot(source: "codex", remaining: 33, limit: 100)
        let entry = StatusBarDisplayPresenter.makeEntry(name: "Codex", snapshot: snap)
        XCTAssertEqual(entry.percentText, "33%")
        XCTAssertTrue(entry.isHealthy)
    }

    func testResetCountdownFormatsHoursAndMinutes() {
        // Pin `now` so the assertion is deterministic (no elapsed-time truncation).
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetAt = now.addingTimeInterval(3 * 3600 + 12 * 60)
        let window = UsageQuotaWindow(
            id: "w", title: "Session", remainingPercent: 50, usedPercent: 50, resetAt: resetAt
        )
        let text = MenuQuotaPresenter.resetCountdown(window, now: now)
        XCTAssertEqual(text, "resets in 3h 12m")
    }
}
