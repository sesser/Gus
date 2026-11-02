import Testing
@testable import PhotoCore

@Suite("Culling description")
struct CullingDescriptionTests {
    private let three = Rating(clamping: 3)

    private func result(_ photo: Int64, rating: Int = 0, flag: Flag = .none,
                        label: ColorLabel = .none) -> CullingDescription.Result {
        CullingDescription.Result(photo: photo, rating: Rating(clamping: rating), flag: flag, colorLabel: label)
    }

    @Test func listsWhatIsSetInReadingOrder() {
        let parts = CullingDescription.value(rating: three, flag: .picked, colorLabel: .red, offline: true)
        #expect(parts == [.rating(three), .flag(.picked), .colorLabel(.red), .offline])
    }

    @Test func leavesOutDefaults() {
        #expect(CullingDescription.value(rating: .unrated, flag: .none, colorLabel: .none, offline: false).isEmpty)
        #expect(CullingDescription.value(rating: .unrated, flag: .rejected, colorLabel: .none, offline: false)
            == [.flag(.rejected)])
        #expect(CullingDescription.value(rating: .unrated, flag: .none, colorLabel: .gray, offline: true)
            == [.colorLabel(.gray), .offline])
    }

    @Test func onePhotoAnnouncesItsNewValueEvenADefault() {
        #expect(CullingDescription.announcement(of: .flag, results: [result(1, flag: .picked)])
            == .value(.flag(.picked), count: 1))
        #expect(CullingDescription.announcement(of: .rating, step: -1, results: [result(1)])
            == .value(.rating(.unrated), count: 1))
        #expect(CullingDescription.announcement(of: .colorLabel, results: [result(1, label: .none)])
            == .value(.colorLabel(.none), count: 1))
    }

    @Test func aKeyThatChangesNothingStillAnnounces() {
        // Raise Rating on a five-star photo leaves it at five.
        #expect(CullingDescription.announcement(of: .rating, step: 1, results: [result(1, rating: 5)])
            == .value(.rating(Rating(clamping: 5)), count: 1))
    }

    @Test func severalPhotosWithTheSameResultAnnounceTheValueAndCount() {
        let results = (1...12).map { result(Int64($0), flag: .picked) }
        #expect(CullingDescription.announcement(of: .flag, results: results) == .value(.flag(.picked), count: 12))
        // Raised from the same rating, they end the same.
        let raised = [result(1, rating: 3), result(2, rating: 3)]
        #expect(CullingDescription.announcement(of: .rating, step: 1, results: raised) == .value(.rating(three), count: 2))
    }

    @Test func mixedResultsAnnounceTheActionAndCount() {
        let results = [result(1, rating: 2), result(2, rating: 4), result(3, rating: 5)]
        #expect(CullingDescription.announcement(of: .rating, step: 1, results: results)
            == .ratingAdjusted(raised: true, count: 3))
        #expect(CullingDescription.announcement(of: .rating, step: -1, results: results)
            == .ratingAdjusted(raised: false, count: 3))
    }

    @Test func aRAWJPEGPairCountsAsOnePhoto() {
        let pair = CullingDescription.Result.photo(versionID: 8, partnerVersionID: 7)
        #expect(pair == CullingDescription.Result.photo(versionID: 7, partnerVersionID: 8))
        #expect(CullingDescription.Result.photo(versionID: 9, partnerVersionID: nil) == 9)
        // Both halves shown separately and selected: one photo, so no count.
        let results = [result(pair, flag: .rejected), result(pair, flag: .rejected)]
        #expect(CullingDescription.announcement(of: .flag, results: results) == .value(.flag(.rejected), count: 1))
        #expect(CullingDescription.announcement(of: .flag, results: results + [result(9, flag: .rejected)])
            == .value(.flag(.rejected), count: 2))
    }

    @Test func noResultsAnnounceNothing() {
        #expect(CullingDescription.announcement(of: .flag, results: []) == nil)
    }

    @Test func theNextPhotoAfterAdvancingAlwaysSaysItsRating() {
        #expect(CullingDescription.advancedTo(rating: .unrated, flag: .none, colorLabel: .none, offline: false)
            == [.rating(.unrated)])
        #expect(CullingDescription.advancedTo(rating: three, flag: .picked, colorLabel: .none, offline: true)
            == [.rating(three), .flag(.picked), .offline])
    }
}
