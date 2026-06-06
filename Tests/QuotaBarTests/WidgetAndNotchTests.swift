import XCTest
import StatsUsagePresentation
@testable import StatsUsage

final class MenuBarWidgetRendererTests: XCTestCase {
    private func entry(_ pct: Double?) -> StatusBarDisplayEntry {
        StatusBarDisplayEntry(
            providerID: "codex", name: "Codex",
            percentText: pct.map { "\(Int($0))%" } ?? "—",
            remainingPercent: pct, isHealthy: true
        )
    }

    func testProducesImageForEveryStyle() {
        for style in MenuBarWidgetStyle.allCases {
            let image = MenuBarWidgetRenderer.image(
                entries: [entry(42)], style: style, history: ["codex": [80, 60, 42]], appearanceDark: true
            )
            XCTAssertNotNil(image, "expected an image for style \(style)")
            XCTAssertGreaterThan(image!.size.width, 0)
            XCTAssertGreaterThan(image!.size.height, 0)
        }
    }

    func testEmptyEntriesProduceNoImage() {
        XCTAssertNil(MenuBarWidgetRenderer.image(
            entries: [], style: .ring, history: [:], appearanceDark: false
        ))
    }

    func testColorThresholds() {
        XCTAssertEqual(
            MenuBarWidgetRenderer.color(forPercent: 5, healthy: true),
            NSColor(red: 1.0, green: 0.18, blue: 0.33, alpha: 1.0)
        )
        XCTAssertEqual(
            MenuBarWidgetRenderer.color(forPercent: 35, healthy: true),
            NSColor(red: 1.0, green: 0.63, blue: 0.0, alpha: 1.0)
        )
        XCTAssertEqual(
            MenuBarWidgetRenderer.color(forPercent: 80, healthy: true),
            NSColor(red: 0.0, green: 0.90, blue: 0.46, alpha: 1.0)
        )
        XCTAssertEqual(
            MenuBarWidgetRenderer.color(forPercent: 80, healthy: false),
            NSColor(red: 0.55, green: 0.55, blue: 0.57, alpha: 1.0)
        )
    }
}

final class NotchGeometryTests: XCTestCase {
    func testFallbackWhenNoScreen() {
        let g = NotchGeometry.resolve(for: nil)
        XCTAssertFalse(g.hasNotch)
        XCTAssertEqual(g.notchWidth, NotchGeometry.fallbackWidth)
        XCTAssertEqual(g.notchHeight, NotchGeometry.fallbackHeight)
    }
}

final class AppConfigNotchDecodingTests: XCTestCase {
    func testNewFieldsDefaultWhenAbsentInOldConfig() throws {
        // An "old" config without the notch/widget fields must still decode, with
        // the new fields taking their defaults (additive persistence).
        let json = #"{"language":"en","providers":[]}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.menuBarWidgetStyle, .percent)
        XCTAssertTrue(config.notchEnabled)
        XCTAssertTrue(config.notchExpandOnHover)
        XCTAssertNil(config.notchProviderID)
    }

    func testRoundTripPreservesNewFields() throws {
        var config = AppConfig.default
        config.menuBarWidgetStyle = .ring
        config.notchEnabled = false
        config.notchProviderID = "claude"
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.menuBarWidgetStyle, .ring)
        XCTAssertFalse(decoded.notchEnabled)
        XCTAssertEqual(decoded.notchProviderID, "claude")
    }
}
