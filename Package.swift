// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenPad",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 3.0.x — 3.1.0 is <7 days old
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", .upToNextMinor(from: "3.0.1"))
    ],
    targets: [
        .executableTarget(name: "OpenPad", dependencies: ["KeyboardShortcuts"])
    ]
)
