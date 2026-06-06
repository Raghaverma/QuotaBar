import XCTest
@testable import StatsUsage

final class ConfigStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StatsUsageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = ConfigStore(baseDirectoryURL: tempDir)
        var config = AppConfig.default
        config.launchAtLoginEnabled = true
        config.statusBarProviderID = "codex"
        try store.save(config)

        let reloaded = try ConfigStore(baseDirectoryURL: tempDir).load()
        XCTAssertTrue(reloaded.launchAtLoginEnabled)
        XCTAssertEqual(reloaded.statusBarProviderID, "codex")
        XCTAssertFalse(store.lastLoadWasLossy)
    }

    func testLossyConfigSkipsBadProviderEntries() throws {
        // One valid provider, one with an unknown type → the bad one is dropped.
        let json = #"""
        {
          "language": "en",
          "providers": [
            { "id": "codex", "type": "codex", "family": "official" },
            { "id": "ghost", "type": "definitely-not-a-real-type", "family": "official" }
          ]
        }
        """#
        let url = tempDir.appendingPathComponent("config.json")
        try Data(json.utf8).write(to: url)

        let store = ConfigStore(baseDirectoryURL: tempDir)
        let config = try store.load()
        XCTAssertEqual(Set(config.providers.map(\.id)), Set(["codex", "claude", "gemini"]))
        XCTAssertTrue(store.lastLoadWasLossy)
    }

    func testCorruptPrimaryFallsBackToLastKnownGood() throws {
        let store = ConfigStore(baseDirectoryURL: tempDir)
        var config = AppConfig.default
        config.statusBarProviderID = "claude"
        try store.save(config)   // writes primary + shadow + lkg

        // Corrupt the primary file.
        let primary = tempDir.appendingPathComponent("config.json")
        try Data("not json".utf8).write(to: primary)

        let reloaded = try ConfigStore(baseDirectoryURL: tempDir).load()
        XCTAssertEqual(reloaded.statusBarProviderID, "claude")
    }
}
