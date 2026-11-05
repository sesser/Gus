import Foundation
import Testing
@testable import PhotoCore

@Suite("Per-source filter and sort")
struct SourceViewSettingsTests {
    private func store() -> (SourceViewSettingsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "SourceViewSettingsTests-\(UUID().uuidString)")!
        return (SourceViewSettingsStore(defaults: defaults), defaults)
    }

    @Test func eachSourceKeepsItsOwnSettings() {
        let (store, _) = store()
        let picks = SourceViewSettings(rating: .atLeast(Rating(clamping: 3)), flag: .picked, search: "sony",
                                       sort: LibrarySort(key: .rating, ascending: false))
        store.save(picks, for: "album:4")
        #expect(store.settings(for: "album:4") == picks)
        #expect(store.settings(for: "all") == SourceViewSettings())
    }

    @Test func survivesANewStoreOnTheSameDefaults() {
        let (store, defaults) = store()
        let settings = SourceViewSettings(rating: .unrated, flag: .notRejected, sort: LibrarySort(key: .fileName))
        store.save(settings, for: "keyword:9")
        #expect(SourceViewSettingsStore(defaults: defaults).settings(for: "keyword:9") == settings)
    }

    @Test func aSourceWithoutSettingsTakesTheDefaultSort() {
        let (store, _) = store()
        let sort = LibrarySort(key: .rating, ascending: false)
        #expect(store.settings(for: "project:2", defaultSort: sort) == SourceViewSettings(sort: sort))
    }

    @Test func defaultsAreNotStoredAndRemovedSourcesAreForgotten() {
        let (store, defaults) = store()
        store.save(SourceViewSettings(flag: .rejected), for: "album:1")
        store.save(SourceViewSettings(), for: "album:2")
        let data = defaults.data(forKey: "browser.sourceSettings") ?? Data()
        let saved = try? JSONDecoder().decode([String: SourceViewSettings].self, from: data)
        #expect(saved?.keys.sorted() == ["album:1"])
        store.remove("album:1")
        #expect(store.settings(for: "album:1") == SourceViewSettings())
    }

    @Test func everyRuleRoundTrips() throws {
        let rules: [LibraryFilter.RatingRule] = [.any, .unrated, .atLeast(Rating(clamping: 2)), .exactly(Rating(clamping: 5))]
        for rating in rules {
            for flag in LibraryFilter.FlagRule.allCases {
                let settings = SourceViewSettings(rating: rating, flag: flag, search: "a, b",
                                                  sort: LibrarySort(key: .fileName, ascending: false))
                let data = try JSONEncoder().encode(settings)
                #expect(try JSONDecoder().decode(SourceViewSettings.self, from: data) == settings)
            }
        }
    }
}

@Suite("Browser subtitle")
struct BrowserSubtitleTests {
    @Test func countsPhotosSelectionAndFilter() {
        #expect(BrowserSubtitle.grid(shown: 4623, total: 4623, selected: 1, isFiltered: false) == .photos(4623))
        #expect(BrowserSubtitle.grid(shown: 4623, total: 4623, selected: 12, isFiltered: false)
            == .selected(12, of: 4623, filtered: false))
        #expect(BrowserSubtitle.grid(shown: 87, total: 4623, selected: 1, isFiltered: true) == .filtered(87, of: 4623))
        #expect(BrowserSubtitle.grid(shown: 87, total: 4623, selected: 5, isFiltered: true)
            == .selected(5, of: 87, filtered: true))
    }

    @Test func aTotalNotYetCountedIsTheShownCount() {
        #expect(BrowserSubtitle.grid(shown: 87, total: nil, selected: 0, isFiltered: true) == .filtered(87, of: 87))
    }

    @Test func theLoupeNamesTheSourceAndTheFilter() {
        #expect(BrowserSubtitle.loupe(isFiltered: false) == .source(filtered: false))
        #expect(BrowserSubtitle.loupe(isFiltered: true) == .source(filtered: true))
    }
}

@Suite("Empty source states")
struct EmptySourceStateTests {
    private let kinds: [EmptySourceState.SourceKind] = [.album, .smartAlbum, .other]

    @Test func aSourceShowingPhotosHasNoEmptyState() {
        for kind in kinds {
            for filtered in [false, true] {
                #expect(EmptySourceState.resolve(shownCount: 3, libraryCount: 40, isFiltered: filtered, source: kind) == nil)
            }
        }
    }

    @Test func anEmptyLibraryIsNoPhotosYetWhateverTheSourceOrFilter() {
        for kind in kinds {
            for filtered in [false, true] {
                #expect(EmptySourceState.resolve(shownCount: 0, libraryCount: 0, isFiltered: filtered, source: kind)
                    == .emptyLibrary)
            }
        }
    }

    @Test func aFilterHidingEverythingIsNoPhotosMatchForEveryKind() {
        for kind in kinds {
            #expect(EmptySourceState.resolve(shownCount: 0, libraryCount: 40, isFiltered: true, source: kind) == .noMatches)
        }
    }

    @Test func anEmptyAlbumSaysHowToAddPhotos() {
        #expect(EmptySourceState.resolve(shownCount: 0, libraryCount: 40, isFiltered: false, source: .album)
            == .emptySource(.album))
    }

    @Test func anEmptySmartAlbumPointsAtItsRules() {
        #expect(EmptySourceState.resolve(shownCount: 0, libraryCount: 40, isFiltered: false, source: .smartAlbum)
            == .emptySource(.smartAlbum))
    }

    @Test func otherEmptySourcesGetTheTitleOnly() {
        #expect(EmptySourceState.resolve(shownCount: 0, libraryCount: 40, isFiltered: false, source: .other)
            == .emptySource(.other))
    }
}

@Suite("File ▸ Stop's job")
struct StoppableJobTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func nothingRunningIsNil() {
        #expect(StoppableJob.newest([:]) == nil)
    }

    @Test func aSingleJobIsTheOne() {
        for job in StoppableJob.allCases {
            #expect(StoppableJob.newest([job: start]) == job)
        }
    }

    @Test func theNewestStartWins() {
        #expect(StoppableJob.newest([.export: start, .addFolders: start.addingTimeInterval(5)]) == .addFolders)
        #expect(StoppableJob.newest([.export: start.addingTimeInterval(9), .addFolders: start.addingTimeInterval(5),
                                     .cardImport: start]) == .export)
        #expect(StoppableJob.newest([.cardImport: start.addingTimeInterval(1), .export: start]) == .cardImport)
    }

    @Test func equalStartsAreDecidedTheSameWayEveryTime() {
        let all = Dictionary(uniqueKeysWithValues: StoppableJob.allCases.map { ($0, start) })
        #expect(StoppableJob.newest(all) == .cardImport)
    }
}

@Suite("Activity")
struct ActivityLogTests {
    @Test func keepsRecentMessagesNewestLastAndCountsUnseen() {
        var log = ActivityLog(limit: 3)
        for text in ["a", "b", "c", "d"] { log.post(text) }
        #expect(log.messages.map(\.text) == ["b", "c", "d"])
        #expect(log.unseenCount == 3)
        log.markSeen()
        #expect(log.unseenCount == 0)
        log.post("b")
        #expect(log.messages.map(\.text) == ["c", "d", "b"])
        #expect(log.unseenCount == 1)
    }

    @Test func remembersWhetherAnUnseenMessageIsAWarning() {
        var log = ActivityLog()
        log.post("Imported 3 look-up tables.")
        #expect(!log.unseenHasWarning)
        log.post("Could not save the change.", title: "Set Rating", isWarning: true)
        log.post("Merged “a” into “b”.")
        #expect(log.unseenHasWarning)
        #expect(log.messages.last?.title == nil)
        #expect(log.messages[1].title == "Set Rating")
        log.markSeen()
        #expect(!log.unseenHasWarning)
    }

    @Test func keepsTwentyByDefault() {
        var log = ActivityLog()
        for index in 0..<25 { log.post("\(index)") }
        #expect(log.messages.count == 20)
        #expect(log.messages.first?.text == "5")
    }

    @Test func backgroundJobsShowAfterADelay() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(ActivityLog.shows(background: false, startedAt: start, now: start))
        #expect(!ActivityLog.shows(background: true, startedAt: start, now: start.addingTimeInterval(4.9)))
        #expect(ActivityLog.shows(background: true, startedAt: start, now: start.addingTimeInterval(5)))
    }
}
