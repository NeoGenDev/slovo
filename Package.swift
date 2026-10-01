// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CCTranslator",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "CCTranslator",
            path: "Sources/CCTranslator",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
