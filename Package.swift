// swift-tools-version: 6.0
import PackageDescription

// Debug builds compile the two targets that hold per-pixel Swift with the
// optimizer on. Unoptimized, generic and SIMD code is not specialized and a
// pixel costs microseconds: the HDR merge's measuring (`HDRMerger.plan`) took
// 5 s for a 600 x 400 copy and a bracket fixture 1 s a frame, which made the
// merge suites 11 of `swift test`'s 12 minutes (issue #150, PR #258;
// docs/features/hdr-merge/status.md, "Test and CI time"). With the flags the
// whole run takes about 78 s.
//
// `-assert-config Debug` keeps what -O alone would turn off: `assert`, and
// the standard library's debug-only checks, among them the bounds checks on
// unsafe buffer pointers (a read past the end of one still stops a test
// instead of reading the memory beside it; code review C25). It costs about
// 6% of the merge suites' time. Release builds, and so the app, never had
// those checks and are as before.
//
// The flags follow SwiftPM's own -Onone on the command line, so they win
// (checked with both build systems). `@testable import` is as before: it
// needs -enable-testing, not -Onone. The cost: a debugger steps through
// optimized code in these two targets, and a clean debug build takes about
// 45% more processor time (288 s to 417 s on an M4 Pro). The test target
// stays unoptimized.
let optimizedInDebug: [SwiftSetting] = [
    .unsafeFlags(["-O", "-assert-config", "Debug"], .when(configuration: .debug)),
]

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
                // Release builds would otherwise compile LibRaw at SwiftPM's -Os; at -O3
                // its full-size decodes are about twice as fast for Bayer raws and 13%
                // faster for X-Trans, with the same output bit for bit (issue #195).
                // The flag comes after -Os on clang's command line, so it wins. Debug
                // builds keep -O0.
                .unsafeFlags(["-O3"], .when(configuration: .release)),
            ]
        ),
        .target(
            name: "PhotoCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift"), "CLibRaw"],
            swiftSettings: optimizedInDebug
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
        // PhotoFixtures for the debug script's fake Immich server (issue #271,
        // R25: `import server fake …`), started only by a scripted launch.
        .executableTarget(
            name: "PhotoApp",
            dependencies: ["PhotoCore", "PhotoUI", "PhotoFixtures"]
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
            dependencies: ["PhotoCore"],
            swiftSettings: optimizedInDebug
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
