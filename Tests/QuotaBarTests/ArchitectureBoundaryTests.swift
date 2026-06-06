import XCTest

/// Enforces layering rules by scanning source files. For example, `Domain` must
/// never import AppKit/SwiftUI — it is the dependency-free contract layer.
final class ArchitectureBoundaryTests: XCTestCase {

    /// Walk up from this test file to the package root (where `Package.swift` lives).
    private func packageRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        return url
    }

    private func swiftFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    func testDomainDoesNotImportUIFrameworks() throws {
        let domainDir = packageRoot()
            .appendingPathComponent("Sources/StatsUsageDomain")
        let files = swiftFiles(in: domainDir)
        XCTAssertFalse(files.isEmpty, "Expected to find Domain source files")
        let forbidden = ["import AppKit", "import SwiftUI", "import UserNotifications"]
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for needle in forbidden {
                XCTAssertFalse(
                    contents.contains(needle),
                    "\(file.lastPathComponent) must not contain '\(needle)' — Domain is UI-free"
                )
            }
        }
    }

    func testApplicationLayerStaysUIFree() throws {
        let appDir = packageRoot()
            .appendingPathComponent("Sources/StatsUsageApplication")
        for file in swiftFiles(in: appDir) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(contents.contains("import AppKit"),
                           "\(file.lastPathComponent): Application must remain AppKit-free")
            XCTAssertFalse(contents.contains("import SwiftUI"),
                           "\(file.lastPathComponent): Application must remain SwiftUI-free")
        }
    }
}
