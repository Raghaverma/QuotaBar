import XCTest
@testable import QuotaBar

/// The notch window is sized once for the fully expanded panel and never resized, so
/// while collapsed it is a large mostly-empty slab pinned to the top-centre of the
/// screen — directly over the region browsers use for tabs, the address bar and
/// bookmarks. Everything outside the *visible* island has to stay click-through.
final class NotchClickThroughTests: XCTestCase {

    /// A 3-provider window: 420 x 315pt, top-centre of a 1512x982pt display.
    private let windowFrame = CGRect(x: 546, y: 667, width: 420, height: 315)
    private let notchWidth: CGFloat = 190
    private let notchHeight: CGFloat = 37

    private func collapsedIsland() -> CGRect {
        NotchController.islandRect(
            windowFrame: windowFrame,
            notchWidth: notchWidth, notchHeight: notchHeight,
            isExpanded: false
        )
    }

    func testCollapsedIslandIsOnlyThePhysicalNotch() {
        let island = collapsedIsland()
        XCTAssertEqual(island.width, notchWidth)
        XCTAssertEqual(island.height, notchHeight)
        XCTAssertEqual(island.midX, windowFrame.midX, accuracy: 0.001)
        XCTAssertEqual(island.maxY, windowFrame.maxY, accuracy: 0.001)
    }

    /// The regression: the collapsed island must cover only a small share of the window,
    /// so the rest can be handed back to whatever is underneath.
    func testCollapsedIslandLeavesMostOfTheWindowPassThrough() {
        let island = collapsedIsland()
        let covered = (island.width * island.height) / (windowFrame.width * windowFrame.height)
        XCTAssertLessThan(covered, 0.10, "collapsed island should cover <10% of the window")
    }

    /// Points a browser's tab bar and toolbar actually occupy: inside the window, well
    /// outside the notch. These must not be treated as ours.
    func testPointsBesideAndBelowTheNotchAreOutsideTheIsland() {
        let island = collapsedIsland()
        let outside: [(String, CGPoint)] = [
            ("tab to the left of the notch", CGPoint(x: windowFrame.minX + 20, y: windowFrame.maxY - 10)),
            ("tab to the right of the notch", CGPoint(x: windowFrame.maxX - 20, y: windowFrame.maxY - 10)),
            ("address bar below the notch", CGPoint(x: windowFrame.midX, y: windowFrame.maxY - 120)),
            ("bookmarks bar", CGPoint(x: windowFrame.midX, y: windowFrame.minY + 40)),
            ("bottom-left of the slab", CGPoint(x: windowFrame.minX + 5, y: windowFrame.minY + 5))
        ]
        for (label, point) in outside {
            XCTAssertFalse(island.contains(point), "\(label) must be click-through")
            XCTAssertTrue(windowFrame.contains(point), "\(label) is inside the window (that is the hazard)")
        }
    }

    func testPointOnTheNotchItselfIsInsideTheIsland() {
        XCTAssertTrue(collapsedIsland().contains(
            CGPoint(x: windowFrame.midX, y: windowFrame.maxY - notchHeight / 2)
        ))
    }

    /// Expanded, the visible panel fills the window, so the whole frame is legitimately
    /// interactive — that is an open panel, not an invisible slab.
    func testExpandedIslandIsTheWholeWindow() {
        let island = NotchController.islandRect(
            windowFrame: windowFrame,
            notchWidth: notchWidth, notchHeight: notchHeight,
            isExpanded: true
        )
        XCTAssertEqual(island, windowFrame)
    }

    /// On a Mac with no hardware notch the faux island is still small relative to the
    /// window, so the same pass-through guarantee has to hold.
    func testFauxIslandOnNotchlessDisplayAlsoLeavesMarginsPassThrough() {
        let island = NotchController.islandRect(
            windowFrame: windowFrame,
            notchWidth: NotchGeometry.fallbackWidth,
            notchHeight: NotchGeometry.fallbackHeight,
            isExpanded: false
        )
        XCTAssertFalse(island.contains(CGPoint(x: windowFrame.minX + 10, y: windowFrame.midY)))
        XCTAssertLessThan(island.width, windowFrame.width)
    }
}
