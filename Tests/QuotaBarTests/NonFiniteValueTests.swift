import XCTest
import QuotaBarDomain
import QuotaBarPresentation
@testable import QuotaBar

/// Provider JSON reaches the domain through parsers that accept *strings*, and
/// `Double("nan")` / `Double("inf")` both succeed. A non-finite value flowing into a
/// snapshot used to trap the first time a readout called `Int(_:)` on it — which every
/// percentage display does — crashing the app on a malformed upstream response.
final class NonFiniteValueTests: XCTestCase {

    func testStringParsersDoProduceNonFiniteDoubles() {
        // The premise: this is why sanitizing at the domain boundary is necessary.
        XCTAssertEqual(Double("inf"), .infinity)
        XCTAssertTrue(Double("nan")?.isNaN == true)
    }

    /// Non-finite means "no usable value", so it normalizes to 0 rather than to a
    /// plausible-looking number. For a quota monitor 0 is the safe direction: it shows
    /// as depleted/critical instead of falsely reassuring the user they have headroom.
    func testQuotaWindowNormalizesNonFinitePercentagesToZero() {
        let window = UsageQuotaWindow(
            id: "w", title: "Session",
            remainingPercent: .nan, usedPercent: .infinity
        )
        XCTAssertTrue(window.remainingPercent.isFinite)
        XCTAssertTrue(window.usedPercent.isFinite)
        XCTAssertEqual(window.remainingPercent, 0)
        XCTAssertEqual(window.usedPercent, 0)
    }

    func testQuotaWindowClampsOutOfRangePercentages() {
        let window = UsageQuotaWindow(
            id: "w", title: "Session", remainingPercent: 180, usedPercent: -40
        )
        XCTAssertEqual(window.remainingPercent, 100)
        XCTAssertEqual(window.usedPercent, 0)
    }

    func testSnapshotDropsNonFiniteAmounts() {
        let snapshot = UsageSnapshot(
            source: "relay", remaining: .infinity, used: .nan, limit: .infinity
        )
        XCTAssertNil(snapshot.remaining)
        XCTAssertNil(snapshot.used)
        XCTAssertNil(snapshot.limit)
        XCTAssertNil(snapshot.remainingPercent)
    }

    /// Documents why the *decode* path is not the risk: `JSONDecoder` rejects a literal
    /// that overflows `Double`, so non-finite values cannot enter that way. The live
    /// vector is the providers' string parsing, covered above and below.
    func testJSONDecoderRejectsNonFiniteLiterals() {
        let json = #"{"source":"x","quotaWindows":[{"id":"w","remainingPercent":1e999}]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8)))
    }

    /// Out-of-range (but finite) values *can* be persisted and re-read, so decoding
    /// still clamps.
    func testDecodingClampsOutOfRangePercentages() throws {
        let json = #"{"source":"x","quotaWindows":[{"id":"w","remainingPercent":420}]}"#
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.quotaWindows.first?.remainingPercent, 100)
    }

    /// The end-to-end property that actually matters: every percentage readout must be
    /// renderable without trapping, whatever the provider sent.
    func testEveryReadoutSurvivesHostileProviderValues() {
        for raw in [Double.nan, .infinity, -.infinity, -500, 10_000] {
            let window = UsageQuotaWindow(
                id: "w", title: "Session", remainingPercent: raw, usedPercent: raw
            )
            let snapshot = UsageSnapshot(
                source: "p", remaining: raw, used: raw, limit: raw, quotaWindows: [window]
            )
            // Each of these calls `Int(_:)` on a provider-derived Double.
            XCTAssertFalse(MenuQuotaPresenter.remainingText(window).isEmpty)
            let entry = StatusBarDisplayPresenter.makeEntry(name: "P", snapshot: snapshot)
            XCTAssertFalse(entry.percentText.isEmpty)
            XCTAssertNotNil(MenuBarWidgetRenderer.image(
                entries: [entry], style: .ring, history: [:], appearanceDark: false
            ))
        }
    }

    /// A relay response is the most realistic delivery vehicle: values are extracted
    /// from arbitrary JSON, including strings.
    func testRelayResponseWithNonFiniteStringsProducesSafeSnapshot() throws {
        let manifest = RelayAdapterManifest(
            id: "generic-newapi", displayName: "Generic",
            match: .init(hostPatterns: ["*"], defaultBalanceChannelEnabled: true),
            setup: .init(requiredInputs: []),
            authStrategies: [],
            balanceRequest: .init(method: "GET", path: "/api/user/self",
                                  authHeader: nil, authScheme: nil, userIDHeader: nil),
            tokenRequest: nil,
            extract: .init(success: nil, remaining: "data.quota", used: "data.used_quota",
                           limit: "data.total", unit: nil, accountLabel: nil),
            postprocessID: nil
        )
        let json = #"{"data":{"quota":"nan","used_quota":"inf","total":"inf"}}"#
        let snapshot = try RelayResponseInterpreter.interpret(
            data: Data(json.utf8), manifest: manifest, providerID: "site", providerName: "Site"
        )
        XCTAssertNil(snapshot.remaining)
        XCTAssertNil(snapshot.limit)
        XCTAssertFalse(StatusBarDisplayPresenter.makeEntry(name: "Site", snapshot: snapshot)
            .percentText.isEmpty)
    }
}
