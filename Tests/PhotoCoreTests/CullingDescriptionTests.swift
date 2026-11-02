import Testing
@testable import PhotoCore

@Suite("Culling description")
struct CullingDescriptionTests {
    @Test func listsWhatIsSetInReadingOrder() {
        let parts = CullingDescription.value(rating: Rating(clamping: 3), flag: .picked, colorLabel: .red, offline: true)
        #expect(parts == [.rating(Rating(clamping: 3)), .flag(.picked), .colorLabel(.red), .offline])
    }

    @Test func leavesOutDefaults() {
        #expect(CullingDescription.value(rating: .unrated, flag: .none, colorLabel: .none, offline: false).isEmpty)
        #expect(CullingDescription.value(rating: .unrated, flag: .rejected, colorLabel: .none, offline: false)
            == [.flag(.rejected)])
        #expect(CullingDescription.value(rating: .unrated, flag: .none, colorLabel: .gray, offline: true)
            == [.colorLabel(.gray), .offline])
    }

    @Test func announcesTheNewValueOfWhatChangedEvenADefault() {
        let three = Rating(clamping: 3)
        #expect(CullingDescription.announcement(of: .rating, rating: three, flag: .picked, colorLabel: .red) == .rating(three))
        #expect(CullingDescription.announcement(of: .rating, rating: .unrated, flag: .picked, colorLabel: .red)
            == .rating(.unrated))
        #expect(CullingDescription.announcement(of: .flag, rating: three, flag: .none, colorLabel: .red) == .flag(.none))
        #expect(CullingDescription.announcement(of: .colorLabel, rating: three, flag: .picked, colorLabel: .none)
            == .colorLabel(.none))
    }
}
