// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeBuddy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClaudeBuddy", path: "Sources/ClaudeBuddy")
    ]
)
