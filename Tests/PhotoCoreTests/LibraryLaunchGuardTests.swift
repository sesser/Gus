import Foundation
import Testing
@testable import PhotoCore

@Suite("Library launch guard")
struct LibraryLaunchGuardTests {
    static let release = "com.example.app"
    static let testCopy = "com.example.app.debugtest"

    static func options(_ arguments: String...) -> LaunchOptions {
        LaunchOptions(arguments: ["/path/to/executable"] + arguments)
    }

    static func decide(_ identifier: String?, _ options: LaunchOptions) -> LibraryLaunchGuard.Decision {
        LibraryLaunchGuard.decide(bundleIdentifier: identifier, releaseIdentifier: release, options: options)
    }

    @Test func releaseBundleWithoutFlagsOpensTheStandardLibrary() {
        #expect(Self.decide(Self.release, Self.options()) == .allowed)
    }

    @Test func releaseBundleWithLibraryRootIsAllowed() {
        #expect(Self.decide(Self.release, Self.options("--library-root", "/tmp/lib")) == .allowed)
    }

    @Test func otherBundleWithoutLibraryRootIsRefused() {
        #expect(Self.decide(Self.testCopy, Self.options())
            == .refused(.notReleaseBundle(identifier: Self.testCopy)))
        // A script does not change why: the identifier is reported first.
        #expect(Self.decide(Self.testCopy, Self.options("--debug-script", "quit"))
            == .refused(.notReleaseBundle(identifier: Self.testCopy)))
    }

    @Test func otherBundleWithLibraryRootIsAllowed() {
        #expect(Self.decide(Self.testCopy, Self.options("--library-root", "/tmp/lib")) == .allowed)
        #expect(Self.decide(Self.testCopy, Self.options("--library-root", "/tmp/lib", "--debug-script", "quit"))
            == .allowed)
    }

    @Test func noBundleIdentifierIsNotTheReleaseIdentifier() {
        // `swift run`: a bare executable has no bundle identifier.
        #expect(Self.decide(nil, Self.options()) == .refused(.notReleaseBundle(identifier: nil)))
        #expect(Self.decide(nil, Self.options("--library-root", "/tmp/lib")) == .allowed)
    }

    @Test(arguments: [["--debug-script", "wait 2; quit"], ["--benchmark-scroll", "/tmp/report.json"]])
    func releaseBundleWithScriptNeedsLibraryRoot(_ flag: [String]) {
        #expect(Self.decide(Self.release, LaunchOptions(arguments: ["exe"] + flag)) == .refused(.scriptedLaunch))
        #expect(Self.decide(Self.release, LaunchOptions(arguments: ["exe"] + flag + ["--library-root", "/tmp/lib"]))
            == .allowed)
        #expect(Self.decide(Self.release, LaunchOptions(arguments: ["exe", "--library-root", "/tmp/lib"] + flag))
            == .allowed)
    }

    @Test func libraryRootWithoutAValueDoesNotCount() {
        // The parser reads no folder from a trailing switch, so no library
        // folder was named.
        #expect(Self.decide(Self.testCopy, Self.options("--library-root"))
            == .refused(.notReleaseBundle(identifier: Self.testCopy)))
    }

    @Test func defaultReleaseIdentifierIsTheBrandedOne() {
        #expect(LibraryLaunchGuard.decide(bundleIdentifier: AppBranding.bundleIdentifier, options: Self.options())
            == .allowed)
        #expect(LibraryLaunchGuard.decide(bundleIdentifier: AppBranding.bundleIdentifier + ".debugtest",
                                          options: Self.options()) != .allowed)
    }

    @Test func diagnosticNamesTheMissingOption() {
        for reason in [LibraryLaunchGuard.Reason.notReleaseBundle(identifier: Self.testCopy),
                       .notReleaseBundle(identifier: nil), .scriptedLaunch] {
            #expect(LibraryLaunchGuard.diagnostic(for: reason).contains("--library-root"))
        }
        #expect(LibraryLaunchGuard.diagnostic(for: .notReleaseBundle(identifier: Self.testCopy))
            .contains(Self.testCopy))
    }

    @Test func optionsParseTheSwitchesTheGuardReads() {
        let parsed = Self.options("--library-root", "~/scratch", "--debug-script", "quit",
                                  "--benchmark-scroll", "/tmp/r.json")
        #expect(parsed.libraryRoot?.path == ("~/scratch" as NSString).expandingTildeInPath)
        #expect(parsed.debugScript == "quit")
        #expect(parsed.benchmarkScroll)
        let none = Self.options()
        #expect(none.libraryRoot == nil && none.debugScript == nil && !none.benchmarkScroll)
    }
}
