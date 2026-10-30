import CoreGraphics
import Testing
@testable import PhotoCore

struct ScrollZoomTests {
    @Test func wheelAwayZoomsInAndBackOutReturns() {
        let zoomIn = ScrollZoom.factor(deltaY: 3, precise: false, inverted: false)
        let zoomOut = ScrollZoom.factor(deltaY: -3, precise: false, inverted: false)
        #expect(zoomIn > 1)
        #expect(zoomOut < 1)
        #expect(abs(zoomIn * zoomOut - 1) < 1e-9)
    }

    @Test func invertedScrollingZoomsTheSameWayForTheSameMotion() {
        // With natural scrolling the same physical motion reports the opposite delta.
        let natural = ScrollZoom.factor(deltaY: -4, precise: true, inverted: true)
        let classic = ScrollZoom.factor(deltaY: 4, precise: true, inverted: false)
        #expect(abs(natural - classic) < 1e-9)
        #expect(natural > 1)
    }

    @Test func preciseDeltasZoomLessPerUnitThanLines() {
        let line = ScrollZoom.factor(deltaY: 1, precise: false, inverted: false)
        let point = ScrollZoom.factor(deltaY: 1, precise: true, inverted: false)
        #expect(line > point)
        #expect(point > 1)
    }

    @Test func noDeltaKeepsTheMagnification() {
        #expect(ScrollZoom.factor(deltaY: 0, precise: false, inverted: false) == 1)
    }

    @Test func magnificationStaysBetweenFitAndMaximum() {
        #expect(ScrollZoom.magnification(0.5, factor: 0.1, minimum: 0.25, maximum: 8) == 0.25)
        #expect(ScrollZoom.magnification(4, factor: 10, minimum: 0.25, maximum: 8) == 8)
        #expect(ScrollZoom.magnification(1, factor: 2, minimum: 0.25, maximum: 8) == 2)
        // A fit above the maximum (never expected) wins rather than inverting the range.
        #expect(ScrollZoom.magnification(1, factor: 2, minimum: 9, maximum: 8) == 9)
    }

    @Test func anchorStaysAtTheSamePlaceInTheView() {
        let anchor = CGPoint(x: 300, y: 200)
        let origin = CGPoint(x: 100, y: 50)
        let old: CGFloat = 0.5
        let new: CGFloat = 2
        let moved = ScrollZoom.visibleOrigin(keeping: anchor, visibleOrigin: origin, from: old, to: new)
        // Distance from the visible origin in view points before and after.
        #expect(abs((anchor.x - origin.x) * old - (anchor.x - moved.x) * new) < 1e-9)
        #expect(abs((anchor.y - origin.y) * old - (anchor.y - moved.y) * new) < 1e-9)
    }

    @Test func anchorAtTheOriginKeepsTheOrigin() {
        let origin = CGPoint(x: 40, y: 60)
        #expect(ScrollZoom.visibleOrigin(keeping: origin, visibleOrigin: origin, from: 1, to: 3) == origin)
    }
}
