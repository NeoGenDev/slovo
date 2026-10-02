// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Slovo",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Slovo",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Slovo",
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // Sparkle.framework is copied into Contents/Frameworks by scripts/build-app.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
