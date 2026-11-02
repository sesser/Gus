// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoWorkspace",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PhotoCore", targets: ["PhotoCore"]),
        .executable(name: "PhotoApp", targets: ["PhotoApp"]),
        .executable(name: "PhotoImporter", targets: ["PhotoImporter"]),
        .executable(name: "photobench", targets: ["PhotoBench"]),
        .executable(name: "photocli", targets: ["PhotoCLI"]),
        .executable(name: "catalog-strings", targets: ["StringCatalogCompiler"]),
        .executable(name: "app-icon", targets: ["AppIconCompiler"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0"),
    ],
    targets: [
        .target(
            name: "PhotoCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        // UI shared by the library app and the standalone importer: the import
        // window and its model, colors, launch options and the String Catalog.
        .target(
            name: "PhotoUI",
            dependencies: ["PhotoCore"],
            // The String Catalog is compiled into each app bundle by Scripts/build-app.sh.
            // Processing it here would put the strings in Bundle.module, where SwiftUI
            // and String(localized:) do not look by default (they use Bundle.main).
            exclude: ["Resources/Localizable.xcstrings"]
        ),
        .executableTarget(
            name: "PhotoApp",
            dependencies: ["PhotoCore", "PhotoUI"]
        ),
        .executableTarget(
            name: "PhotoImporter",
            dependencies: ["PhotoCore", "PhotoUI"]
        ),
        .executableTarget(
            name: "PhotoBench",
            dependencies: ["PhotoCore", "PhotoFixtures"]
        ),
        // The headless command line: a thin dispatcher over PhotoCore's command
        // registry, with no AppKit or SwiftUI.
        .executableTarget(
            name: "PhotoCLI",
            dependencies: ["PhotoCore"]
        ),
        .target(
            name: "PhotoFixtures",
            dependencies: ["PhotoCore"]
        ),
        .executableTarget(
            name: "StringCatalogCompiler"
        ),
        .executableTarget(
            name: "AppIconCompiler"
        ),
        .testTarget(
            name: "PhotoCoreTests",
            dependencies: ["PhotoCore", "PhotoFixtures"],
            // Golden images and fixtures are read from the source tree, not bundled.
            exclude: ["Goldens", "Fixtures"]
        ),
    ]
)
