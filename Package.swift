// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cadence",
    // macOS 26. Cadence is built on Liquid Glass — `glassEffect`,
    // `GlassEffectContainer` and the glass button styles — which does not exist
    // before Tahoe. There is no sensible fallback that still looks like this.
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Cadence",
            path: "Sources/Cadence"
        )
    ]
)
