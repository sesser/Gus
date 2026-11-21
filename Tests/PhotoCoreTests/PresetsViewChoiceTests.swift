import Foundation
import PhotoCore
import Testing

/// The Presets heading's view preference (#241, design §6 and §14).
@Suite("Presets view choice")
struct PresetsViewChoiceTests {
    @Test func defaultsToTheListWhenNothingIsStored() {
        #expect(PresetsViewChoice.choice(stored: nil) == .list)
    }

    @Test func readsTheStoredChoice() {
        #expect(PresetsViewChoice.choice(stored: "list") == .list)
        #expect(PresetsViewChoice.choice(stored: "thumbnails") == .thumbnails)
    }

    @Test func anythingElseIsTheList() {
        #expect(PresetsViewChoice.choice(stored: "grid") == .list)
        #expect(PresetsViewChoice.choice(stored: "Thumbnails") == .list)
        #expect(PresetsViewChoice.choice(stored: "") == .list)
        #expect(PresetsViewChoice.choice(stored: 1) == .list)
        #expect(PresetsViewChoice.choice(stored: true) == .list)
    }

    /// The raw values are what `UserDefaults` keeps: renaming a case would
    /// send everyone who chose thumbnails back to the list.
    @Test func storedValuesAndKeyAreStable() {
        #expect(PresetsViewChoice.list.rawValue == "list")
        #expect(PresetsViewChoice.thumbnails.rawValue == "thumbnails")
        #expect(PresetsViewChoice.defaultsKey == "adjust.presetsView")
    }

    /// A round trip through a real defaults domain, as the app stores it.
    @Test func roundTripsThroughUserDefaults() throws {
        let suite = "PresetsViewChoiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(PresetsViewChoice.choice(stored: defaults.object(forKey: PresetsViewChoice.defaultsKey)) == .list)
        defaults.set(PresetsViewChoice.thumbnails.rawValue, forKey: PresetsViewChoice.defaultsKey)
        #expect(PresetsViewChoice.choice(stored: defaults.object(forKey: PresetsViewChoice.defaultsKey)) == .thumbnails)
        defaults.set(PresetsViewChoice.list.rawValue, forKey: PresetsViewChoice.defaultsKey)
        #expect(PresetsViewChoice.choice(stored: defaults.object(forKey: PresetsViewChoice.defaultsKey)) == .list)
    }
}
