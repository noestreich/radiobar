// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RadioBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RadioBar",
            path: "Sources/RadioBar",
            exclude: ["Resources/Info.plist"],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        )
    ]
)
