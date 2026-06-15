// swift-tools-version: 5.10
// SPM-Build-Alternative zu xcodegen/xcodebuild — erlaubt Bauen ohne volles Xcode
// (nur Command Line Tools). Bundle-Assembly übernimmt build-spm.sh im Repo-Root.
//
// Tests: XCTest/swift-testing brauchen volles Xcode. Damit Tests auch mit reinen
// Command Line Tools laufen, liegt die reine Logik in der Foundation-only-Library
// `BlitztextCore` und wird von einem schlanken Plain-Swift-Runner geprüft:
//     swift run BlitztextCoreTests
import PackageDescription

let package = Package(
    name: "Blitztext",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "0.18.0")
    ],
    targets: [
        .target(
            name: "BlitztextCore",
            path: "Core"
        ),
        .executableTarget(
            name: "Blitztext",
            dependencies: [
                "BlitztextCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            path: ".",
            exclude: ["Resources", "project.yml", "Tests", "Core", "Package.resolved"],
            sources: ["App", "Features", "Services", "Views"]
        ),
        .executableTarget(
            name: "BlitztextCoreTests",
            dependencies: ["BlitztextCore"],
            path: "Tests"
        )
    ]
)
