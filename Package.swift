// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cadence",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Cadence",
            path: "Sources/Cadence"
        )
    ]
)
