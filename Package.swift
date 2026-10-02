// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Slovo",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Slovo",
            path: "Sources/Slovo",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
