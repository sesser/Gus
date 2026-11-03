import Testing
@testable import PhotoCore

@Suite("Review layout")
struct ReviewLayoutTests {
    let windowed = ReviewLayout(showsSidebar: true, showsInspector: true, isFullScreen: false)

    @Test func entersAndRestores() {
        var session = ReviewSession()
        #expect(session.enter(from: windowed) == .review)
        #expect(session.isReviewing)
        #expect(session.exit(current: .review) == windowed)
        #expect(!session.isReviewing)
    }

    @Test func entersOnce() {
        var session = ReviewSession()
        _ = session.enter(from: windowed)
        #expect(session.enter(from: .review) == nil)
        #expect(session.exit(current: .review) == windowed)
        #expect(session.exit(current: windowed) == nil)
    }

    @Test func keepsFullScreenThatWasThere() {
        var session = ReviewSession()
        let full = ReviewLayout(showsSidebar: false, showsInspector: false, isFullScreen: true)
        _ = session.enter(from: full)
        #expect(session.exit(current: .review)?.isFullScreen == true)
    }

    @Test func inspectorBroughtBackStays() {
        var session = ReviewSession()
        let bare = ReviewLayout(showsSidebar: true, showsInspector: false, isFullScreen: false)
        _ = session.enter(from: bare)
        var during = ReviewLayout.review
        during.showsInspector = true
        #expect(session.exit(current: during)?.showsInspector == true)
    }
}
