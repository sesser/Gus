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
        // LibRaw 0.22.3, vendored and used under the GNU Lesser General Public
        // License 2.1 (Sources/CLibRaw/LICENSE.LGPL; LibRaw also offers CDDL 1.0,
        // which this project does not take). Built from source here, so it can
        // be changed and the apps built again with it (THIRD_PARTY_NOTICES.md).
        // Thread-safe: LIBRAW_NOTHREADS is not defined. Without zlib, libjpeg,
        // lcms, RawSpeed, the Adobe DNG SDK or the GPL demosaic packs. The
        // "_ph.cpp" files are upstream's stubs for builds without the real
        // sources beside them, and src/Makefile is upstream's own build.
        .target(
            name: "CLibRaw",
            path: "Sources/CLibRaw",
            exclude: ["LICENSE.LGPL", "LICENSE.CDDL", "COPYRIGHT", "src/Makefile",
                      "src/postprocessing/postprocessing_ph.cpp",
                      "src/preprocessing/preprocessing_ph.cpp", "src/write/write_ph.cpp"],
            sources: ["src"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .unsafeFlags(["-w"]),
            ]
        ),
        .target(
            name: "PhotoCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift"), "CLibRaw"]
        ),
        // UI shared by the library app and the standalone importer: the import
        // window and its model, colors and the String Catalog.
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
