import XCTest
@testable import StatsUsage

final class RelayJSONExpressionEvaluatorTests: XCTestCase {
    private func root(_ json: String) throws -> RelayJSONExpressionEvaluator.JSONValue {
        try RelayJSONExpressionEvaluator.parse(Data(json.utf8))
    }

    func testResolvesDottedPath() throws {
        let r = try root(#"{"data":{"quota":42}}"#)
        let v = RelayJSONExpressionEvaluator.evaluate("data.quota", root: r)
        XCTAssertEqual(v.doubleValue, 42)
    }

    func testAddFunctionSumsTwoPaths() throws {
        let r = try root(#"{"data":{"quota":10,"used_quota":5}}"#)
        let v = RelayJSONExpressionEvaluator.evaluate("add(data.quota,data.used_quota)", root: r)
        XCTAssertEqual(v.doubleValue, 15)
    }

    func testCoalesceFallsBackToLiteral() throws {
        let r = try root(#"{"data":{}}"#)
        let v = RelayJSONExpressionEvaluator.evaluate(#"coalesce(data.group,"Default Plan")"#, root: r)
        XCTAssertEqual(v.stringValue, "Default Plan")
    }

    func testCoalescePrefersPresentValue() throws {
        let r = try root(#"{"data":{"group":"VIP"}}"#)
        let v = RelayJSONExpressionEvaluator.evaluate(#"coalesce(data.group,"Default Plan")"#, root: r)
        XCTAssertEqual(v.stringValue, "VIP")
    }

    func testMissingPathYieldsNull() throws {
        let r = try root(#"{"data":{"quota":1}}"#)
        let v = RelayJSONExpressionEvaluator.evaluate("data.nope", root: r)
        XCTAssertTrue(v.isNullOrMissing)
    }
}
