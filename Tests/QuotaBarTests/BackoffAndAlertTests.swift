import XCTest
import StatsUsageDomain
@testable import StatsUsageApplication

final class BackoffPolicyTests: XCTestCase {
    func testBaseIntervalWithNoFailures() {
        XCTAssertEqual(BackoffPolicy.delaySeconds(baseInterval: 300, consecutiveFailures: 0), 300)
    }
    func testTwoMinutesAfterFirstFailure() {
        XCTAssertEqual(BackoffPolicy.delaySeconds(baseInterval: 300, consecutiveFailures: 1), 120)
    }
    func testFiveMinutesAfterRepeatedFailures() {
        XCTAssertEqual(BackoffPolicy.delaySeconds(baseInterval: 300, consecutiveFailures: 5), 300)
    }
}

final class AlertEngineTests: XCTestCase {
    func testAuthErrorTakesPriority() {
        let snap = UsageSnapshot(source: "x", fetchHealth: .authExpired, remaining: 5, limit: 100)
        let decision = AlertEngine.evaluate(snapshot: snap, consecutiveFailures: 0, rule: .default)
        XCTAssertEqual(decision, .authError)
    }

    func testRepeatedFailuresFire() {
        let snap = UsageSnapshot(source: "x")
        let decision = AlertEngine.evaluate(snapshot: snap, consecutiveFailures: 3, rule: .default)
        XCTAssertEqual(decision, .repeatedFailures(count: 3))
    }

    func testLowRemainingFires() {
        let snap = UsageSnapshot(source: "x", remaining: 5, limit: 100)   // 5%
        let decision = AlertEngine.evaluate(snapshot: snap, consecutiveFailures: 0, rule: .default)
        XCTAssertEqual(decision, .lowRemaining(percent: 5))
    }

    func testHealthyDoesNotFire() {
        let snap = UsageSnapshot(source: "x", remaining: 90, limit: 100)
        let decision = AlertEngine.evaluate(snapshot: snap, consecutiveFailures: 0, rule: .default)
        XCTAssertEqual(decision, .none)
    }
}
