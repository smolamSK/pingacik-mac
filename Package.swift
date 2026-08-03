// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Pingacik",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "PingacikCore"
        ),
        .executableTarget(
            name: "Pingacik",
            dependencies: ["PingacikCore"]
        ),
        .testTarget(
            name: "PingacikCoreTests",
            dependencies: ["PingacikCore"]
        )
    ]
)
