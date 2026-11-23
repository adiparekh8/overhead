// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Overhead",
    platforms: [.macOS(.v14)],
    targets: [
        // Plain Swift: distance math, API parsing, selection, formatting, registry.
        .target(name: "OverheadCore"),
        // The menu bar app.
        .executableTarget(name: "Overhead", dependencies: ["OverheadCore"]),
        .testTarget(
            name: "OverheadCoreTests",
            dependencies: ["OverheadCore"],
            exclude: ["Fixtures"]
        ),
    ]
)
