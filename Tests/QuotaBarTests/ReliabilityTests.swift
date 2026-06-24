import XCTest
@testable import QuotaBar

final class ReliabilityTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaBar-Reliability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testConfigLoadMergesNewDefaultProviders() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = #"{"language":"en","providers":[]}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("config.json"))

        let config = try ConfigStore(baseDirectoryURL: directory).load()
        XCTAssertEqual(Set(config.providers.map(\.id)), Set(ProviderDefaultCatalog.seedProviders().map(\.id)))
    }

    func testHistoryPersistsAcrossStoreInstances() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples = [90.0, 75.0, 50.0].enumerated().map { index, value in
            HistorySample(at: Date(timeIntervalSince1970: Double(index) * 60), remainingPercent: value)
        }
        try HistoryStore(baseDirectoryURL: directory).save(["codex": samples])
        XCTAssertEqual(try HistoryStore(baseDirectoryURL: directory).load()["codex"], samples)
    }

    func testHistoryLoadIgnoresPreTimestampFormat() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyJSON = #"{"codex":[90,75,50]}"#
        try Data(legacyJSON.utf8).write(to: directory.appendingPathComponent("usage-history.json"))
        XCTAssertEqual(try HistoryStore(baseDirectoryURL: directory).load(), [:])
    }

    func testAtomicCredentialWriterCreatesBackupAndPreservesPermissions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("auth.json")
        try Data(#"{"old":true}"#.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)

        try AtomicCredentialFileWriter.writeJSON(["new": true], to: file)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.appendingPathExtension("quotabar-backup").path))
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testUpdaterOnlyTrustsHTTPSGitHubReleaseLocations() {
        XCTAssertTrue(AppUpdateService.isTrustedReleaseURL(URL(string: "https://github.com/a/b")!))
        XCTAssertTrue(AppUpdateService.isTrustedReleaseURL(URL(string: "https://objects.githubusercontent.com/a")!))
        XCTAssertFalse(AppUpdateService.isTrustedReleaseURL(URL(string: "http://github.com/a/b")!))
        XCTAssertFalse(AppUpdateService.isTrustedReleaseURL(URL(string: "https://example.com/update.zip")!))
    }

    func testOfficialCredentialFileUpdatesDefaultToOptIn() throws {
        let config = try JSONDecoder().decode(
            OfficialProviderConfig.self,
            from: Data(#"{"sourceMode":"api"}"#.utf8)
        )
        XCTAssertFalse(config.allowCredentialFileUpdates)
        XCTAssertEqual(ProviderDefaultCatalog.seedProviders().first?.supportedOfficialSourceModes, [.auto, .api])
    }
}
