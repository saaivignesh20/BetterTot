// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BetterTot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "BetterTot"),
        .testTarget(name: "BetterTotTests", dependencies: ["BetterTot"]),
    ]
)
