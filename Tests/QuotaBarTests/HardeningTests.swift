import XCTest
import QuotaBarDomain
@testable import QuotaBar

/// `parseUsedPercent` has to cope with Gemini reporting usage as either a 0…1 ratio or
/// a 0…100 percentage. Applying the magnitude heuristic to keys that already name their
/// unit turned a barely-used quota into a fully-consumed one.
final class GeminiPercentParsingTests: XCTestCase {
    private func descriptor() -> ProviderDescriptor {
        ProviderDescriptor(id: "gemini", name: "Gemini", family: .official, type: .gemini)
    }

    private func remaining(from entry: [String: Any]) throws -> Double {
        let snapshot = try GeminiProvider.parseQuotaSnapshot(
            root: ["quotaInfos": [entry]],
            codeAssistRoot: [:],
            descriptor: descriptor(),
            sourceLabel: "API",
            accountLabel: nil,
            projectLabel: nil
        )
        return try XCTUnwrap(snapshot.quotaWindows.first?.remainingPercent)
    }

    /// The regression: 1 % used must stay 1 % used, not become 100 %.
    func testExplicitPercentKeyIsNotRescaled() throws {
        let value = try remaining(from: ["quotaId": "pro", "usedPercent": 1.0])
        XCTAssertEqual(value, 99, accuracy: 0.001)
    }

    func testFractionalExplicitPercentIsNotRescaled() throws {
        let value = try remaining(from: ["quotaId": "pro", "used_percent": 0.5])
        XCTAssertEqual(value, 99.5, accuracy: 0.001)
    }

    func testRatioNamedKeyIsScaled() throws {
        let value = try remaining(from: ["quotaId": "pro", "usageRatio": 0.25])
        XCTAssertEqual(value, 75, accuracy: 0.001)
    }

    /// `utilization` is genuinely emitted in both forms, so it keeps the heuristic.
    func testAmbiguousUtilizationKeepsMagnitudeHeuristic() throws {
        XCTAssertEqual(try remaining(from: ["quotaId": "pro", "utilization": 0.4]), 60, accuracy: 0.001)
        XCTAssertEqual(try remaining(from: ["quotaId": "pro", "utilization": 20.0]), 80, accuracy: 0.001)
    }
}

final class ConfigStoreLastKnownGoodTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuotaBarLKG-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Last-known-good is promoted on a successful *read*, not on every write — so a
    /// config that saves fine but cannot be loaded back can no longer destroy the very
    /// fallback copy it exists to protect.
    func testLastKnownGoodIsPromotedOnSuccessfulLoad() throws {
        let store = ConfigStore(baseDirectoryURL: tempDir)
        var config = AppConfig.default
        config.statusBarProviderID = "claude"
        try store.save(config)

        let lkg = tempDir.appendingPathComponent("config.lkg.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: lkg.path),
                       "save() must not write last-known-good")

        _ = try ConfigStore(baseDirectoryURL: tempDir).load()
        XCTAssertTrue(FileManager.default.fileExists(atPath: lkg.path),
                      "a clean load promotes that file to last-known-good")
    }

    /// The scenario the fallback exists for: both live copies are unreadable, but an
    /// earlier good load left a recoverable snapshot behind.
    func testCorruptPrimaryAndShadowFallBackToPromotedLastKnownGood() throws {
        var config = AppConfig.default
        config.statusBarProviderID = "claude"
        try ConfigStore(baseDirectoryURL: tempDir).save(config)
        _ = try ConfigStore(baseDirectoryURL: tempDir).load()   // promotes LKG

        for name in ["config.json", "config.shadow.json"] {
            try Data("not json".utf8).write(to: tempDir.appendingPathComponent(name))
        }

        let reloaded = try ConfigStore(baseDirectoryURL: tempDir).load()
        XCTAssertEqual(reloaded.statusBarProviderID, "claude")
    }
}

final class ShellCommandTests: XCTestCase {
    func testCapturesStdoutAndStatus() throws {
        let result = try XCTUnwrap(ShellCommand.run(
            executable: "/bin/sh", arguments: ["-c", "echo hello"], timeout: 10
        ))
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
        XCTAssertEqual(result.status, 0)
        XCTAssertFalse(result.timedOut)
    }

    func testCapturesStderrSeparately() throws {
        let result = try XCTUnwrap(ShellCommand.run(
            executable: "/bin/sh", arguments: ["-c", "echo oops >&2; exit 3"], timeout: 10
        ))
        XCTAssertTrue(result.stderr.contains("oops"))
        XCTAssertEqual(result.status, 3)
    }

    /// The deadlock this runner exists to prevent: a child writing far more than the
    /// ~64 KB pipe buffer must not wedge waiting for a reader.
    func testLargeOutputDoesNotDeadlock() throws {
        let result = try XCTUnwrap(ShellCommand.run(
            executable: "/bin/sh",
            arguments: ["-c", "for i in $(seq 1 20000); do echo 'padding line for pipe buffer'; done"],
            timeout: 30
        ))
        XCTAssertFalse(result.timedOut, "draining the pipe concurrently must prevent a stall")
        XCTAssertEqual(result.status, 0)
        XCTAssertGreaterThan(result.stdout.count, 64 * 1024)
    }

    func testTimeoutTerminatesRunawayChild() throws {
        let result = try XCTUnwrap(ShellCommand.run(
            executable: "/bin/sh", arguments: ["-c", "sleep 30"], timeout: 1
        ))
        XCTAssertTrue(result.timedOut)
    }

    /// A process that exits before the caller finishes setting up must still be
    /// observed — the handler is installed before `run()` for exactly this reason.
    func testImmediatelyExitingProcessIsNotReportedAsTimedOut() throws {
        for _ in 0..<20 {
            let result = try XCTUnwrap(ShellCommand.run(
                executable: "/usr/bin/true", arguments: [], timeout: 5
            ))
            XCTAssertFalse(result.timedOut)
            XCTAssertEqual(result.status, 0)
        }
    }

    func testMissingExecutableReturnsNil() {
        XCTAssertNil(ShellCommand.run(
            executable: "/nonexistent/binary", arguments: [], timeout: 5
        ))
    }
}

final class RelayGroupIDTests: XCTestCase {
    /// Manifests written before `groupIDHeader` existed must still decode.
    func testManifestWithoutGroupIDHeaderStillDecodes() throws {
        let json = #"""
        {
          "id": "x", "displayName": "X",
          "match": { "hostPatterns": ["*"] },
          "setup": { "requiredInputs": [] },
          "authStrategies": [],
          "balanceRequest": { "method": "GET", "path": "/api/user/self" },
          "extract": {}
        }
        """#
        let manifest = try JSONDecoder().decode(RelayAdapterManifest.self, from: Data(json.utf8))
        XCTAssertNil(manifest.balanceRequest.groupIDHeader)
    }

    func testBundledManifestStillLoads() {
        let registry = RelayAdapterRegistry.loadFromBundle()
        XCTAssertNotNil(registry.manifest(id: "generic-newapi"))
    }
}
