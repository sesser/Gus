import Foundation
@testable import PhotoCore

extension CommandEnvironment {
    /// The only way tests build a command environment. A command given no
    /// `--library-root` falls back on the environment's standard library, and
    /// with no `defaultLibraryRoot` that is the owner's real one
    /// (`LibraryLocations.standard()`): `render --version`, `query` and the
    /// write commands use it. Here the standard library is `standardLibrary`, by
    /// default a folder that is never created, so no test reads the real
    /// library whatever its arguments. `HermeticCommandTests` fails on any
    /// other construction in the tests.
    static func hermetic(currentDirectory: URL, standardLibrary: URL? = nil) -> CommandEnvironment {
        CommandEnvironment(currentDirectory: currentDirectory,
                           defaultLibraryRoot: standardLibrary ?? FileManager.default.temporaryDirectory
                               .appending(path: "photocore-tests-no-library-\(UUID().uuidString)",
                                          directoryHint: .isDirectory))
    }
}
