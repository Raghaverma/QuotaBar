import XCTest
import QuotaBarDomain
@testable import QuotaBar

final class GeminiProviderTests: XCTestCase {
    private static func defaultOfficialGemini() -> ProviderDescriptor {
        ProviderDescriptor(
            id: "gemini",
            name: "Gemini",
            family: .official,
            type: .gemini,
            enabled: false,
            pollIntervalSec: 300,
            officialConfig: OfficialProviderConfig(sourceMode: .api)
        )
    }

    func testGeminiQuotaResponseParsesProAndFlashWindows() throws {
        let quotaRoot: [String: Any] = [
            "quotaInfos": [
                [
                    "quotaId": "gemini-2.5-pro",
                    "usage": ["utilization": 0.40, "resetAt": "2026-04-11T08:00:00Z"]
                ],
                [
                    "quotaId": "gemini-2.5-flash",
                    "usage": ["utilization": 20.0, "resetAt": "2026-04-11T02:00:00Z"]
                ]
            ]
        ]
        let codeAssistRoot: [String: Any] = ["tierId": "legacy-pro"]

        let snapshot = try GeminiProvider.parseQuotaSnapshot(
            root: quotaRoot,
            codeAssistRoot: codeAssistRoot,
            descriptor: Self.defaultOfficialGemini(),
            sourceLabel: "API",
            accountLabel: "gemini@example.com",
            projectLabel: "demo-project"
        )

        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertEqual(snapshot.accountLabel, "gemini@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Pro" })?.remainingPercent ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Flash" })?.remainingPercent ?? -1, 80, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "pro")
        XCTAssertEqual(snapshot.extras["project"], "demo-project")
        XCTAssertEqual(snapshot.rawMeta["gemini.rawModel.count"], "2")
        let rawModelIDs = snapshot.rawMeta
            .filter { $0.key.hasSuffix(".id") }
            .map(\.value)
        XCTAssertTrue(rawModelIDs.contains("gemini-2.5-pro"))
        XCTAssertTrue(rawModelIDs.contains("gemini-2.5-flash"))
    }

    func testGeminiQuotaResponseParsesBucketsShapeFromGeminiCLI() throws {
        let quotaRoot: [String: Any] = [
            "buckets": [
                [
                    "modelId": "gemini-2.5-pro",
                    "remainingAmount": "400",
                    "remainingFraction": 0.40,
                    "resetTime": "2026-04-11T08:00:00Z"
                ],
                [
                    "modelId": "gemini-2.5-flash",
                    "remainingAmount": "900",
                    "remainingFraction": 0.90,
                    "resetTime": "2026-04-11T02:00:00Z"
                ]
            ]
        ]
        let codeAssistRoot: [String: Any] = [
            "currentTier": ["id": "legacy-pro"],
            "cloudaicompanionProject": "demo-project"
        ]

        let snapshot = try GeminiProvider.parseQuotaSnapshot(
            root: quotaRoot,
            codeAssistRoot: codeAssistRoot,
            descriptor: Self.defaultOfficialGemini(),
            sourceLabel: "API",
            accountLabel: "gemini@example.com",
            projectLabel: "demo-project"
        )

        XCTAssertEqual(snapshot.sourceLabel, "API")
        XCTAssertEqual(snapshot.accountLabel, "gemini@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Pro" })?.remainingPercent ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first(where: { $0.title == "Flash" })?.remainingPercent ?? -1, 90, accuracy: 0.001)
    }
}
