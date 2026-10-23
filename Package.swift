// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoWorkspace",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PhotoCore", targets: ["PhotoCore"]),
        .executable(name: "PhotoApp", targets: ["PhotoApp"]),
        .executable(name: "photobench", targets: ["PhotoBench"]),
        .executable(name: "catalog-strings", targets: ["StringCatalogCompiler"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0"),
    ],
    targets: [
        .target(
            name: "PhotoCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "PhotoApp",
            dependencies: ["PhotoCore"],
            // The String Catalog is compiled by Scripts/build-app.sh (the Command Line
            // Tools ship without xcstringstool), so SwiftPM must not try to process it.
            exclude: ["Resources/Localizable.xcstrings"]
        ),
        .executableTarget(
            name: "PhotoBench",
            dependencies: ["PhotoCore"]
        ),
        .executableTarget(
            name: "StringCatalogCompiler"
        ),
        .testTarget(
            name: "PhotoCoreTests",
            dependencies: ["PhotoCore"]
        ),
    ]
)
